#ifdef RDP_BRIDGE_HAS_FREERDP

#include "rdp_bridge_internal.h"

#include <freerdp/channels/channels.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/codec/color.h>
#include <freerdp/error.h>
#include <freerdp/freerdp.h>
#include <freerdp/settings.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/graphics.h>
#include <freerdp/input.h>
#include <freerdp/transport_io.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/channels/audin.h>
#include <winpr/crt.h>
#include <winpr/string.h>
#include <winpr/handle.h>
#include <winpr/synch.h>
#include <openssl/crypto.h>
#include <openssl/err.h>
#include <openssl/provider.h>
#include <openssl/ssl.h>

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define TAG "rdp_bridge"

static char g_last_tcp_error[256];
static char g_last_stage[128];

static void bridge_set_stage(const char* stage) {
    snprintf(g_last_stage, sizeof(g_last_stage), "%s", stage ? stage : "");
}

static void bridge_init_openssl(void) {
    static int once = 0;
    if (once)
        return;
    once = 1;
    OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, NULL);
    OPENSSL_init_ssl(OPENSSL_INIT_NO_LOAD_CONFIG | OPENSSL_INIT_LOAD_SSL_STRINGS, NULL);
    (void)OSSL_PROVIDER_load(NULL, "default");
    if (!OSSL_PROVIDER_load(NULL, "legacy"))
        ERR_clear_error();
    ERR_clear_error();
}

typedef struct {
    rdpContext _p;
    rdp_bridge_handle* owner;
    int pointer_x;
    int pointer_y;
} bridge_rdp_context;

typedef struct {
    rdpPointer pointer;
    BYTE* rgba;
    UINT32 width;
    UINT32 height;
    UINT32 hotspot_x;
    UINT32 hotspot_y;
} bridge_pointer;

static pTransportConnectLayer g_default_connect_layer;
static pTransportFkt g_default_tls_connect;

static int bridge_posix_tcp_connect(rdpContext* context, rdpSettings* settings,
                                    const char* hostname, int port, DWORD timeout) {
    int fd;
    (void)settings;
    bridge_set_stage("POSIX TCPConnect");
    fd = rdp_bridge_tcp_connect_fd(hostname, port, (int)timeout, g_last_tcp_error,
                                   (int)sizeof(g_last_tcp_error));
    if (fd < 0) {
        bridge_set_stage("POSIX TCP 失败");
        if (context)
            freerdp_set_last_error_if_not(context, FREERDP_ERROR_CONNECT_TRANSPORT_FAILED);
        return -1;
    }
    snprintf(g_last_tcp_error, sizeof(g_last_tcp_error), "POSIX TCP 已连接 fd=%d", fd);
    bridge_set_stage("POSIX TCP 成功，交给 FreeRDP 包装");
    return fd;
}

typedef struct {
    int fd;
    HANDLE event;
} bridge_posix_layer;

static int bridge_layer_read(void* userContext, void* data, int bytes) {
    bridge_posix_layer* layer = (bridge_posix_layer*)userContext;
    ssize_t n;
    if (!layer || layer->fd < 0 || !data || bytes <= 0)
        return 0;
    n = recv(layer->fd, data, (size_t)bytes, 0);
    if (n > 0)
        return (int)n;
    if (n == 0) {
        errno = ECONNRESET;
        return -1;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
        errno = EAGAIN;
        return -1;
    }
    return -1;
}

static int bridge_layer_write(void* userContext, const void* data, int bytes) {
    bridge_posix_layer* layer = (bridge_posix_layer*)userContext;
    ssize_t n;
    if (!layer || layer->fd < 0 || !data || bytes <= 0)
        return 0;
    n = send(layer->fd, data, (size_t)bytes, 0);
    if (n > 0)
        return (int)n;
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
        errno = EAGAIN;
        return -1;
    }
    return -1;
}

static BOOL bridge_layer_close(void* userContext) {
    bridge_posix_layer* layer = (bridge_posix_layer*)userContext;
    if (!layer)
        return FALSE;
    if (layer->fd >= 0) {
        close(layer->fd);
        layer->fd = -1;
    }
    if (layer->event) {
        CloseHandle(layer->event);
        layer->event = NULL;
    }
    return TRUE;
}

static BOOL bridge_layer_wait(void* userContext, BOOL waitWrite, DWORD timeout) {
    bridge_posix_layer* layer = (bridge_posix_layer*)userContext;
    struct pollfd pfd;
    int rc;
    if (!layer || layer->fd < 0)
        return FALSE;
    pfd.fd = layer->fd;
    pfd.events = waitWrite ? POLLOUT : POLLIN;
    pfd.revents = 0;
    do {
        rc = poll(&pfd, 1, (int)timeout);
    } while (rc < 0 && errno == EINTR);
    return rc > 0;
}

static HANDLE bridge_layer_get_event(void* userContext) {
    bridge_posix_layer* layer = (bridge_posix_layer*)userContext;
    return layer ? layer->event : NULL;
}

static rdpTransportLayer* bridge_posix_connect_layer(rdpTransport* transport, const char* hostname,
                                                     int port, DWORD timeout) {
    rdpContext* context = transport_get_context(transport);
    rdpTransportLayer* layer = NULL;
    bridge_posix_layer* posix = NULL;
    int fd;
    int flags;

    bridge_set_stage("POSIX 传输层重试");
    fd = rdp_bridge_tcp_connect_fd(hostname, port, (int)timeout, g_last_tcp_error,
                                   (int)sizeof(g_last_tcp_error));
    if (fd < 0) {
        bridge_set_stage("POSIX TCP 失败");
        if (context)
            freerdp_set_last_error_if_not(context, FREERDP_ERROR_CONNECT_TRANSPORT_FAILED);
        return NULL;
    }

    flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0)
        (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    layer = transport_layer_new(transport, sizeof(bridge_posix_layer));
    if (!layer) {
        close(fd);
        return NULL;
    }
    layer->Read = bridge_layer_read;
    layer->Write = bridge_layer_write;
    layer->Close = bridge_layer_close;
    layer->Wait = bridge_layer_wait;
    layer->GetEvent = bridge_layer_get_event;

    posix = (bridge_posix_layer*)layer->userContext;
    posix->fd = fd;
    posix->event = CreateFileDescriptorEventA(NULL, TRUE, FALSE, fd, WINPR_FD_READ);
    if (!posix->event) {
        transport_layer_free(layer);
        close(fd);
        snprintf(g_last_tcp_error, sizeof(g_last_tcp_error), "无法创建 socket 事件");
        bridge_set_stage("CreateFileDescriptorEvent 失败");
        return NULL;
    }
    snprintf(g_last_tcp_error, sizeof(g_last_tcp_error), "POSIX 传输层 fd=%d", fd);
    bridge_set_stage("POSIX 传输层已建立，开始协议协商");
    return layer;
}

static rdpTransportLayer* bridge_connect_layer(rdpTransport* transport, const char* hostname,
                                               int port, DWORD timeout) {
    rdpTransportLayer* layer;

    bridge_set_stage("FreeRDP 包装传输层");
    if (!g_default_connect_layer)
        return bridge_posix_connect_layer(transport, hostname, port, timeout);
    layer = g_default_connect_layer(transport, hostname, port, timeout);
    if (layer) {
        bridge_set_stage("传输层已包装，开始协议协商");
        return layer;
    }
    if (strstr(g_last_stage, "POSIX TCP 失败"))
        return NULL;
    return bridge_posix_connect_layer(transport, hostname, port, timeout);
}

static BOOL bridge_tls_connect(rdpTransport* transport) {
    BOOL ok;

    bridge_set_stage("TLS 握手");
    if (!g_default_tls_connect)
        return FALSE;
    ok = g_default_tls_connect(transport);
    bridge_set_stage(ok ? "TLS 握手成功" : "TLS 握手失败");
    return ok;
}

static BOOL bridge_install_posix_transport(rdpContext* context) {
    rdpTransportIo io;
    const rdpTransportIo* current;

    current = freerdp_get_io_callbacks(context);
    if (!current)
        return FALSE;
    /* PreConnect 会再进一次，不能把包装函数存成「默认」否则会递归 */
    if (current->TCPConnect == bridge_posix_tcp_connect)
        return TRUE;
    io = *current;
    if (!g_default_connect_layer)
        g_default_connect_layer = current->ConnectLayer;
    if (!g_default_tls_connect)
        g_default_tls_connect = current->TLSConnect;
    io.TCPConnect = bridge_posix_tcp_connect;
    io.ConnectLayer = bridge_connect_layer;
    io.TLSConnect = bridge_tls_connect;
    return freerdp_set_io_callbacks(context, &io);
}

static freerdp* bridge_instance(rdp_bridge_handle* handle) {
    if (!handle || !handle->freerdp || !handle->freerdp->instance)
        return NULL;
    return (freerdp*)handle->freerdp->instance;
}

static char* bridge_strdup(const char* value) {
    size_t length;
    char* copy;

    if (!value)
        return NULL;
    length = strlen(value);
    copy = (char*)malloc(length + 1);
    if (!copy)
        return NULL;
    memcpy(copy, value, length + 1);
    return copy;
}

static void bridge_parse_username(rdpSettings* settings, const char* username) {
    char* user_copy = NULL;
    char* separator = NULL;
    char* domain = NULL;
    char* user = NULL;

    if (!settings || !username || username[0] == '\0')
        return;

    user_copy = bridge_strdup(username);
    if (!user_copy)
        return;

    separator = strchr(user_copy, '\\');
    if (!separator)
        separator = strchr(user_copy, '/');
    if (separator) {
        *separator = '\0';
        domain = user_copy;
        user = separator + 1;
        if (domain[0] != '\0')
            freerdp_settings_set_string(settings, FreeRDP_Domain, domain);
        if (user[0] != '\0')
            freerdp_settings_set_string(settings, FreeRDP_Username, user);
    } else {
        freerdp_settings_set_string(settings, FreeRDP_Username, user_copy);
        /* 本地账户：空域在 NLA/CredSSP 上经常失败，"." 表示本机 */
        freerdp_settings_set_string(settings, FreeRDP_Domain, ".");
    }

    free(user_copy);
}

static BOOL bridge_authenticate_ex(freerdp* instance, char** username, char** password, char** domain,
                                   rdp_auth_reason reason) {
    rdpSettings* settings;

    (void)reason;
    if (!instance || !instance->context || !username || !password || !domain)
        return FALSE;

    settings = instance->context->settings;
    if (!settings)
        return FALSE;

    if (*username && (*username)[0] != '\0' && *password && (*password)[0] != '\0')
        return TRUE;

    if (freerdp_settings_get_string(settings, FreeRDP_Username) &&
        freerdp_settings_get_string(settings, FreeRDP_Password)) {
        free(*username);
        free(*password);
        free(*domain);
        *username = bridge_strdup(freerdp_settings_get_string(settings, FreeRDP_Username));
        *password = bridge_strdup(freerdp_settings_get_string(settings, FreeRDP_Password));
        *domain = bridge_strdup(freerdp_settings_get_string(settings, FreeRDP_Domain));
        return (*username && *password) ? TRUE : FALSE;
    }

    return FALSE;
}

static DWORD bridge_verify_certificate_ex(freerdp* instance, const char* host, UINT16 port,
                                          const char* common_name, const char* subject,
                                          const char* issuer, const char* fingerprint, DWORD flags) {
    (void)host;
    (void)port;
    (void)common_name;
    (void)subject;
    (void)issuer;
    (void)fingerprint;
    (void)flags;
    (void)instance;
    return 1;
}

static DWORD bridge_verify_changed_certificate_ex(freerdp* instance, const char* host, UINT16 port,
                                                const char* common_name, const char* subject,
                                                const char* issuer, const char* fingerprint,
                                                const char* old_subject, const char* old_issuer,
                                                const char* old_fingerprint, DWORD flags) {
    (void)old_subject;
    (void)old_issuer;
    (void)old_fingerprint;
    return bridge_verify_certificate_ex(instance, host, port, common_name, subject, issuer,
                                      fingerprint, flags);
}

static SSIZE_T bridge_retry_dialog(freerdp* instance, const char* what, size_t current,
                                   void* user_data) {
    (void)instance;
    (void)what;
    (void)current;
    (void)user_data;
    return -1;
}

static void bridge_emit_connect_error(rdp_bridge_handle* handle, freerdp* instance) {
    char message[512];
    UINT32 error = FREERDP_ERROR_CONNECT_UNDEFINED;
    const char* name;
    const char* detail;

    if (instance && instance->context)
        error = freerdp_get_last_error(instance->context);

    name = freerdp_get_last_error_name(error);
    detail = freerdp_get_last_error_string(error);
    snprintf(message, sizeof(message), "RDP 连接失败: %s — %s | 阶段=%s | 传输=%s",
             name ? name : "UNKNOWN",
             detail ? detail : "无详细信息",
             g_last_stage[0] ? g_last_stage : "未知",
             g_last_tcp_error[0] ? g_last_tcp_error : "无");
    if (strstr(g_last_stage, "TLS") || strstr(g_last_stage, "握手") ||
        strstr(g_last_stage, "协议协商")) {
        unsigned long sslerr;
        size_t used = strlen(message);
        while ((sslerr = ERR_get_error()) != 0 && used + 16 < sizeof(message)) {
            char ssl[96];
            ERR_error_string_n(sslerr, ssl, sizeof(ssl));
            used += (size_t)snprintf(message + used, sizeof(message) - used, " | SSL=%s", ssl);
        }
    } else {
        ERR_clear_error();
    }
    rdp_bridge_emit_event(handle, RDP_BRIDGE_EVENT_ERROR, message);
}

static BOOL bridge_apply_performance_settings(rdpSettings* settings, int optimize_for_speed) {
    if (optimize_for_speed) {
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableWallpaper, TRUE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableFullWindowDrag, TRUE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableMenuAnims, TRUE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableThemes, TRUE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_AllowFontSmoothing, FALSE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_AllowDesktopComposition, FALSE))
            return FALSE;
    } else {
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableWallpaper, FALSE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableFullWindowDrag, FALSE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableMenuAnims, FALSE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_DisableThemes, FALSE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_AllowFontSmoothing, TRUE))
            return FALSE;
        if (!freerdp_settings_set_bool(settings, FreeRDP_AllowDesktopComposition, TRUE))
            return FALSE;
    }
    freerdp_performance_flags_make(settings);
    return TRUE;
}

static BOOL bridge_apply_settings(rdp_bridge_handle* handle, rdpSettings* settings) {
    const rdp_bridge_config* cfg = &handle->config;

    if (!freerdp_settings_set_string(settings, FreeRDP_ServerHostname, cfg->hostname))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, (UINT32)cfg->port))
        return FALSE;
    if (!freerdp_settings_set_string(settings, FreeRDP_Password, cfg->password))
        return FALSE;
    bridge_parse_username(settings, cfg->username);
    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, (UINT32)cfg->width))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, (UINT32)cfg->height))
        return FALSE;

    if (!freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, cfg->enable_nla ? TRUE : FALSE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_AutoLogonEnabled, TRUE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_PreferIPv6OverIPv4, FALSE))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_ForceIPvX, 4))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_TcpConnectTimeout, 30000))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_TlsSecLevel, FREERDP_TLS_SECLEVEL_0))
        return FALSE;
    if (!freerdp_settings_set_string(settings, FreeRDP_ClientHostname, "RDPAirPlay"))
        return FALSE;

    if (!freerdp_settings_set_bool(settings, FreeRDP_AudioPlayback, cfg->enable_speaker ? TRUE : FALSE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_AudioCapture, cfg->enable_microphone ? TRUE : FALSE))
        return FALSE;

    /* rdpsnd/audin 与 Windows 音频设备枚举相关；播放或采集任一开启时需启用 */
    if (cfg->enable_speaker || cfg->enable_microphone) {
        if (!freerdp_settings_set_bool(settings, FreeRDP_DeviceRedirection, TRUE))
            return FALSE;
    }

    if (cfg->enable_microphone) {
        const char* audin_args[] = { AUDIN_CHANNEL_NAME, "ios" };
        if (!freerdp_client_add_dynamic_channel(settings, ARRAYSIZE(audin_args), audin_args))
            return FALSE;
    }

    if (!freerdp_settings_set_bool(settings, FreeRDP_GrabKeyboard, FALSE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_GrabMouse, FALSE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_AutoReconnectionEnabled, FALSE))
        return FALSE;
    if (!freerdp_settings_set_bool(settings, FreeRDP_MouseMotion, TRUE))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_PointerCacheSize, 20))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_ColorPointerCacheSize, 20))
        return FALSE;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_LargePointerFlag, 1))
        return FALSE;

    if (!bridge_apply_performance_settings(settings, cfg->optimize_for_speed))
        return FALSE;

    return TRUE;
}

static void bridge_emit_frame(bridge_rdp_context* ctx) {
    rdpGdi* gdi;
    rdp_bridge_frame frame;

    if (!ctx || !ctx->owner || !ctx->owner->callbacks.on_frame)
        return;
    gdi = ctx->_p.gdi;
    if (!gdi || !gdi->primary_buffer)
        return;

    frame.width = (int)gdi->width;
    frame.height = (int)gdi->height;
    frame.pixels = gdi->primary_buffer;
    frame.stride = (int)gdi->stride;
    frame.timestamp = (double)time(NULL);
    ctx->owner->callbacks.on_frame(&frame, ctx->owner->callbacks.user_data);
}

static void bridge_emit_cursor(bridge_rdp_context* ctx, const BYTE* rgba, int width, int height,
                               int hotspot_x, int hotspot_y, int visible, int has_image) {
    rdp_bridge_cursor cursor;

    if (!ctx || !ctx->owner || !ctx->owner->callbacks.on_cursor)
        return;
    memset(&cursor, 0, sizeof(cursor));
    cursor.pixels = rgba;
    cursor.width = width;
    cursor.height = height;
    cursor.stride = width * 4;
    cursor.hotspot_x = hotspot_x;
    cursor.hotspot_y = hotspot_y;
    cursor.x = ctx->pointer_x;
    cursor.y = ctx->pointer_y;
    cursor.visible = visible ? 1 : 0;
    cursor.has_image = has_image ? 1 : 0;
    ctx->owner->callbacks.on_cursor(&cursor, ctx->owner->callbacks.user_data);
}

static BOOL bridge_Pointer_New(rdpContext* context, rdpPointer* pointer) {
    bridge_pointer* ptr = (bridge_pointer*)pointer;
    size_t size;

    if (!context || !pointer || !context->gdi)
        return FALSE;
    size = 4ull * pointer->width * pointer->height;
    if (size == 0)
        return FALSE;
    ptr->rgba = (BYTE*)winpr_aligned_malloc(size, 16);
    if (!ptr->rgba)
        return FALSE;
    if (!freerdp_image_copy_from_pointer_data(
            ptr->rgba, PIXEL_FORMAT_RGBA32, 0, 0, 0, pointer->width, pointer->height,
            pointer->xorMaskData, pointer->lengthXorMask, pointer->andMaskData,
            pointer->lengthAndMask, pointer->xorBpp, &context->gdi->palette)) {
        winpr_aligned_free(ptr->rgba);
        ptr->rgba = NULL;
        return FALSE;
    }
    ptr->width = pointer->width;
    ptr->height = pointer->height;
    ptr->hotspot_x = pointer->xPos;
    ptr->hotspot_y = pointer->yPos;
    return TRUE;
}

static void bridge_Pointer_Free(rdpContext* context, rdpPointer* pointer) {
    bridge_pointer* ptr = (bridge_pointer*)pointer;
    (void)context;
    if (!ptr)
        return;
    winpr_aligned_free(ptr->rgba);
    ptr->rgba = NULL;
}

static BOOL bridge_Pointer_Set(rdpContext* context, rdpPointer* pointer) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)context;
    bridge_pointer* ptr = (bridge_pointer*)pointer;

    if (!ctx || !ptr)
        return FALSE;
    bridge_emit_cursor(ctx, ptr->rgba, (int)ptr->width, (int)ptr->height, (int)ptr->hotspot_x,
                       (int)ptr->hotspot_y, 1, 1);
    return TRUE;
}

static BOOL bridge_Pointer_SetPosition(rdpContext* context, UINT32 x, UINT32 y) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)context;
    if (!ctx)
        return FALSE;
    ctx->pointer_x = (int)x;
    ctx->pointer_y = (int)y;
    bridge_emit_cursor(ctx, NULL, 0, 0, 0, 0, 1, 0);
    return TRUE;
}

static BOOL bridge_Pointer_SetNull(rdpContext* context) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)context;
    if (!ctx)
        return FALSE;
    bridge_emit_cursor(ctx, NULL, 0, 0, 0, 0, 0, 0);
    return TRUE;
}

static BOOL bridge_Pointer_SetDefault(rdpContext* context) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)context;
    if (!ctx)
        return FALSE;
    bridge_emit_cursor(ctx, NULL, 0, 0, 1, 1, 1, 0);
    return TRUE;
}

static BOOL bridge_register_pointer(rdpGraphics* graphics) {
    rdpPointer pointer = { 0 };

    if (!graphics)
        return FALSE;
    pointer.size = sizeof(bridge_pointer);
    pointer.New = bridge_Pointer_New;
    pointer.Free = bridge_Pointer_Free;
    pointer.Set = bridge_Pointer_Set;
    pointer.SetNull = bridge_Pointer_SetNull;
    pointer.SetDefault = bridge_Pointer_SetDefault;
    pointer.SetPosition = bridge_Pointer_SetPosition;
    graphics_register_pointer(graphics, &pointer);
    return TRUE;
}

static BOOL bridge_end_paint(rdpContext* context) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)context;
    rdpGdi* gdi = context->gdi;
    HGDI_DC hdc;
    HGDI_WND hwnd;

    if (!gdi || !gdi->primary)
        return TRUE;
    hdc = gdi->primary->hdc;
    if (!hdc || !hdc->hwnd)
        return TRUE;
    hwnd = hdc->hwnd;
    if (!hwnd->invalid || hwnd->invalid->null)
        return TRUE;

    bridge_emit_frame(ctx);
    hwnd->invalid->null = TRUE;
    return TRUE;
}

static BOOL bridge_pre_connect(freerdp* instance) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)instance->context;
    rdpSettings* settings = instance->context->settings;

    if (!bridge_apply_settings(ctx->owner, settings))
        return FALSE;

    if (!bridge_install_posix_transport(instance->context))
        return FALSE;

    bridge_set_stage("PreConnect 完成");
    return TRUE;
}

static BOOL bridge_post_connect(freerdp* instance) {
    rdpUpdate* update = instance->context->update;

    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32))
        return FALSE;
    if (!bridge_register_pointer(instance->context->graphics))
        return FALSE;

    update->EndPaint = bridge_end_paint;
    return TRUE;
}

static void bridge_post_disconnect(freerdp* instance) {
    gdi_free(instance);
}

static BOOL bridge_client_new(freerdp* instance, rdpContext* context) {
    bridge_rdp_context* ctx = (bridge_rdp_context*)context;
    bridge_init_openssl();
    ctx->owner = NULL;
    instance->PreConnect = bridge_pre_connect;
    instance->PostConnect = bridge_post_connect;
    instance->PostDisconnect = bridge_post_disconnect;
    instance->AuthenticateEx = bridge_authenticate_ex;
    instance->VerifyCertificateEx = bridge_verify_certificate_ex;
    instance->VerifyChangedCertificateEx = bridge_verify_changed_certificate_ex;
    instance->RetryDialog = bridge_retry_dialog;
    (void)bridge_install_posix_transport(context);
    return TRUE;
}

static void bridge_client_free(freerdp* instance, rdpContext* context) {
    (void)instance;
    (void)context;
}

static int bridge_client_entry(RDP_CLIENT_ENTRY_POINTS* pEntryPoints) {
    ZeroMemory(pEntryPoints, sizeof(RDP_CLIENT_ENTRY_POINTS));
    pEntryPoints->Version = RDP_CLIENT_INTERFACE_VERSION;
    pEntryPoints->Size = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
    pEntryPoints->ContextSize = sizeof(bridge_rdp_context);
    pEntryPoints->ClientNew = bridge_client_new;
    pEntryPoints->ClientFree = bridge_client_free;
    return 0;
}

static freerdp* bridge_create_instance(void) {
    RDP_CLIENT_ENTRY_POINTS clientEntryPoints = { 0 };
    rdpContext* context;

    bridge_client_entry(&clientEntryPoints);
    context = freerdp_client_context_new(&clientEntryPoints);
    if (!context)
        return NULL;
    return context->instance;
}

static void bridge_input_queue_init(rdp_bridge_input_queue* queue);
static void bridge_input_queue_free(rdp_bridge_input_queue* queue);
static void bridge_drain_input_queue(rdp_bridge_handle* handle);

static void* bridge_thread_main(void* arg) {
    rdp_bridge_handle* handle = (rdp_bridge_handle*)arg;
    freerdp* instance = bridge_instance(handle);
    bridge_rdp_context* ctx = (bridge_rdp_context*)instance->context;
    DWORD status;
    DWORD count;
    HANDLE events[MAXIMUM_WAIT_OBJECTS];

    ctx->owner = handle;
    g_last_tcp_error[0] = '\0';
    bridge_init_openssl();
    bridge_set_stage("freerdp_connect 开始");

    if (!freerdp_connect(instance)) {
        bridge_emit_connect_error(handle, instance);
        handle->freerdp->running = 0;
        return NULL;
    }

    handle->connected = 1;
    rdp_bridge_emit_event(handle, RDP_BRIDGE_EVENT_CONNECTED, "");

    while (handle->connected && !freerdp_shall_disconnect_context(instance->context)) {
        count = freerdp_get_event_handles(instance->context, events, ARRAYSIZE(events));
        if (count == 0)
            break;

        status = WaitForMultipleObjects(count, events, FALSE, 100);
        if (status == WAIT_FAILED)
            break;

        if (!freerdp_check_event_handles(instance->context))
            break;

        bridge_drain_input_queue(handle);
    }

    bridge_drain_input_queue(handle);

    freerdp_disconnect(instance);
    handle->connected = 0;
    rdp_bridge_emit_event(handle, RDP_BRIDGE_EVENT_DISCONNECTED, "");
    handle->freerdp->running = 0;
    return NULL;
}

int rdp_freerdp_connect_async(rdp_bridge_handle* handle) {
    if (!handle)
        return -1;

    if (!handle->freerdp) {
        handle->freerdp = calloc(1, sizeof(rdp_freerdp_context));
        if (!handle->freerdp)
            return -1;
        bridge_input_queue_init(&handle->freerdp->input_queue);
    }

    if (handle->freerdp->running)
        return -1;

    handle->freerdp->instance = bridge_create_instance();
    if (!handle->freerdp->instance) {
        rdp_bridge_emit_event(handle, RDP_BRIDGE_EVENT_ERROR, "无法创建 FreeRDP 实例");
        return -1;
    }

    handle->freerdp->running = 1;
    if (pthread_create(&handle->freerdp->thread, NULL, bridge_thread_main, handle) != 0) {
        handle->freerdp->running = 0;
        freerdp_client_context_free(bridge_instance(handle)->context);
        handle->freerdp->instance = NULL;
        rdp_bridge_emit_event(handle, RDP_BRIDGE_EVENT_ERROR, "无法启动 RDP 线程");
        return -1;
    }
    return 0;
}

void rdp_freerdp_disconnect(rdp_bridge_handle* handle) {
    if (!handle || !handle->freerdp)
        return;

    handle->connected = 0;
    if (handle->freerdp->instance) {
        freerdp* instance = bridge_instance(handle);
        if (instance)
            freerdp_abort_connect_context(instance->context);
    }

    if (handle->freerdp->running)
        pthread_join(handle->freerdp->thread, NULL);

    if (handle->freerdp) {
        bridge_input_queue_free(&handle->freerdp->input_queue);
    }

    if (handle->freerdp->instance) {
        freerdp* instance = bridge_instance(handle);
        if (instance)
            freerdp_client_context_free(instance->context);
        handle->freerdp->instance = NULL;
    }
    handle->freerdp->running = 0;
}

int rdp_freerdp_set_resolution(rdp_bridge_handle* handle, int width, int height) {
    freerdp* instance;
    rdpSettings* settings;

    if (!handle || !handle->freerdp || !handle->freerdp->instance)
        return -1;

    instance = bridge_instance(handle);
    if (!instance)
        return -1;
    settings = instance->context->settings;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, (UINT32)width))
        return -1;
    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, (UINT32)height))
        return -1;

    if (handle->connected && instance->context->gdi) {
        rdpSettings* settings = instance->context->settings;
        (void)settings;
        /* Display Control 需 disp 通道；暂仅更新设置，重连后生效 */
    }

    return 0;
}

static rdpInput* bridge_input(rdp_bridge_handle* handle) {
    freerdp* instance = bridge_instance(handle);
    if (!instance)
        return NULL;
    return instance->context->input;
}

#define BRIDGE_INPUT_QUEUE_MAX 512

static size_t bridge_input_queue_count(rdp_bridge_input_queue* queue) {
    rdp_bridge_input_item* item;
    size_t count = 0;

    if (!queue)
        return 0;

    pthread_mutex_lock(&queue->mutex);
    for (item = queue->head; item; item = item->next)
        count++;
    pthread_mutex_unlock(&queue->mutex);
    return count;
}

static void bridge_input_queue_drop_oldest(rdp_bridge_input_queue* queue) {
    rdp_bridge_input_item* item;
    rdp_bridge_input_item* prev;

    if (!queue)
        return;

    pthread_mutex_lock(&queue->mutex);
    item = queue->head;
    if (item) {
        queue->head = item->next;
        if (!queue->head)
            queue->tail = NULL;
    }
    pthread_mutex_unlock(&queue->mutex);

    if (!item)
        return;
    if (item->type == RDP_BRIDGE_INPUT_TEXT)
        free(item->u.text);
    free(item);
}

static void bridge_input_queue_init(rdp_bridge_input_queue* queue) {
    if (!queue)
        return;
    queue->head = NULL;
    queue->tail = NULL;
    pthread_mutex_init(&queue->mutex, NULL);
}

static void bridge_input_queue_free(rdp_bridge_input_queue* queue) {
    rdp_bridge_input_item* item;
    rdp_bridge_input_item* next;

    if (!queue)
        return;

    pthread_mutex_lock(&queue->mutex);
    item = queue->head;
    queue->head = NULL;
    queue->tail = NULL;
    pthread_mutex_unlock(&queue->mutex);

    while (item) {
        next = item->next;
        if (item->type == RDP_BRIDGE_INPUT_TEXT)
            free(item->u.text);
        free(item);
        item = next;
    }

    pthread_mutex_destroy(&queue->mutex);
}

static void bridge_input_queue_enqueue(rdp_bridge_input_queue* queue, rdp_bridge_input_item* item) {
    if (!queue || !item)
        return;

    while (bridge_input_queue_count(queue) >= BRIDGE_INPUT_QUEUE_MAX)
        bridge_input_queue_drop_oldest(queue);

    item->next = NULL;
    pthread_mutex_lock(&queue->mutex);
    if (queue->tail)
        queue->tail->next = item;
    else
        queue->head = item;
    queue->tail = item;
    pthread_mutex_unlock(&queue->mutex);
}

static rdp_bridge_input_item* bridge_input_queue_dequeue_all(rdp_bridge_input_queue* queue) {
    rdp_bridge_input_item* items;

    if (!queue)
        return NULL;

    pthread_mutex_lock(&queue->mutex);
    items = queue->head;
    queue->head = NULL;
    queue->tail = NULL;
    pthread_mutex_unlock(&queue->mutex);
    return items;
}

static void bridge_send_mouse_impl(rdp_bridge_handle* handle, int x, int y, int button, int action, int delta_x, int delta_y) {
    rdpInput* input = bridge_input(handle);
    freerdp* instance = bridge_instance(handle);
    bridge_rdp_context* ctx = instance ? (bridge_rdp_context*)instance->context : NULL;
    UINT16 flags = 0;

    if (!input)
        return;

    if (ctx) {
        ctx->pointer_x = x;
        ctx->pointer_y = y;
    }

    (void)delta_x;
    if (action == RDP_MOUSE_ACTION_MOVE) {
        freerdp_input_send_mouse_event(input, PTR_FLAGS_MOVE, (UINT16)x, (UINT16)y);
        return;
    }

    if (button == RDP_MOUSE_RIGHT)
        flags |= PTR_FLAGS_BUTTON2;
    else
        flags |= PTR_FLAGS_BUTTON1;

    if (action == RDP_MOUSE_ACTION_DOWN)
        flags |= PTR_FLAGS_DOWN;

    if (action == RDP_MOUSE_ACTION_SCROLL) {
        flags = PTR_FLAGS_WHEEL;
        if (delta_y < 0)
            flags |= PTR_FLAGS_WHEEL_NEGATIVE;
        freerdp_input_send_mouse_event(input, flags, (UINT16)x, (UINT16)y);
        return;
    }

    freerdp_input_send_mouse_event(input, flags, (UINT16)x, (UINT16)y);
}

static void bridge_send_key_impl(rdp_bridge_handle* handle, uint16_t key_code, int action, uint8_t modifiers) {
    rdpInput* input = bridge_input(handle);
    BOOL down;

    if (!input)
        return;

    (void)modifiers;
    down = (action == RDP_KEY_ACTION_DOWN) ? TRUE : FALSE;
    freerdp_input_send_keyboard_event_ex(input, down, FALSE, (UINT32)key_code);
}

static void bridge_send_text_impl(rdp_bridge_handle* handle, const char* text) {
    rdpInput* input = bridge_input(handle);
    WCHAR* wide = NULL;
    size_t length = 0;
    size_t i;

    if (!input || !text || text[0] == '\0')
        return;

    wide = ConvertUtf8ToWCharAlloc(text, &length);
    if (!wide)
        return;
    for (i = 0; i < length; i++) {
        if (wide[i] == 0)
            continue;
        freerdp_input_send_unicode_keyboard_event(input, 0, (UINT16)wide[i]);
        freerdp_input_send_unicode_keyboard_event(input, KBD_FLAGS_RELEASE, (UINT16)wide[i]);
    }
    free(wide);
}

static void bridge_drain_input_queue(rdp_bridge_handle* handle) {
    rdp_bridge_input_item* items;
    rdp_bridge_input_item* item;
    rdp_bridge_input_item* next;

    if (!handle || !handle->freerdp)
        return;

    items = bridge_input_queue_dequeue_all(&handle->freerdp->input_queue);
    for (item = items; item; item = next) {
        next = item->next;
        switch (item->type) {
        case RDP_BRIDGE_INPUT_MOUSE:
            bridge_send_mouse_impl(handle, item->u.mouse.x, item->u.mouse.y, item->u.mouse.button,
                                   item->u.mouse.action, item->u.mouse.delta_x, item->u.mouse.delta_y);
            break;
        case RDP_BRIDGE_INPUT_KEY:
            bridge_send_key_impl(handle, item->u.key.key_code, item->u.key.action, item->u.key.modifiers);
            break;
        case RDP_BRIDGE_INPUT_TEXT:
            if (item->u.text)
                bridge_send_text_impl(handle, item->u.text);
            free(item->u.text);
            break;
        default:
            break;
        }
        free(item);
    }
}

void rdp_freerdp_send_mouse(rdp_bridge_handle* handle, int x, int y, int button, int action, int delta_x, int delta_y) {
    rdp_bridge_input_item* item;

    if (!handle || !handle->freerdp)
        return;

    item = (rdp_bridge_input_item*)calloc(1, sizeof(rdp_bridge_input_item));
    if (!item)
        return;

    item->type = RDP_BRIDGE_INPUT_MOUSE;
    item->u.mouse.x = x;
    item->u.mouse.y = y;
    item->u.mouse.button = button;
    item->u.mouse.action = action;
    item->u.mouse.delta_x = delta_x;
    item->u.mouse.delta_y = delta_y;
    bridge_input_queue_enqueue(&handle->freerdp->input_queue, item);
}

void rdp_freerdp_send_key(rdp_bridge_handle* handle, uint16_t key_code, int action, uint8_t modifiers) {
    rdp_bridge_input_item* item;

    if (!handle || !handle->freerdp)
        return;

    item = (rdp_bridge_input_item*)calloc(1, sizeof(rdp_bridge_input_item));
    if (!item)
        return;

    item->type = RDP_BRIDGE_INPUT_KEY;
    item->u.key.key_code = key_code;
    item->u.key.action = action;
    item->u.key.modifiers = modifiers;
    bridge_input_queue_enqueue(&handle->freerdp->input_queue, item);
}

void rdp_freerdp_send_text(rdp_bridge_handle* handle, const char* text) {
    rdp_bridge_input_item* item;
    char* copy;

    if (!handle || !handle->freerdp || !text || text[0] == '\0')
        return;

    copy = bridge_strdup(text);
    if (!copy)
        return;

    item = (rdp_bridge_input_item*)calloc(1, sizeof(rdp_bridge_input_item));
    if (!item) {
        free(copy);
        return;
    }

    item->type = RDP_BRIDGE_INPUT_TEXT;
    item->u.text = copy;
    bridge_input_queue_enqueue(&handle->freerdp->input_queue, item);
}

void rdp_freerdp_send_capture_audio(rdp_bridge_handle* handle, const int16_t* samples, int sample_count, int sample_rate, int channels) {
    (void)handle;
    (void)samples;
    (void)sample_count;
    (void)sample_rate;
    (void)channels;
    /* audin 由 FreeRDP ios 子系统 (AudioQueue) 直接采集，无需 Swift 喂 PCM */
}

#else /* !RDP_BRIDGE_HAS_FREERDP */

#include "rdp_bridge_internal.h"

int rdp_freerdp_connect_async(rdp_bridge_handle* handle) {
    rdp_bridge_emit_event(
        handle,
        RDP_BRIDGE_EVENT_ERROR,
        "FreeRDP not built. Run scripts/build_openssl_ios.sh && scripts/build_freerdp_ios.sh"
    );
    return -1;
}

void rdp_freerdp_disconnect(rdp_bridge_handle* handle) {
    (void)handle;
}

int rdp_freerdp_set_resolution(rdp_bridge_handle* handle, int width, int height) {
    (void)handle; (void)width; (void)height;
    return -1;
}

void rdp_freerdp_send_mouse(rdp_bridge_handle* handle, int x, int y, int button, int action, int delta_x, int delta_y) {
    (void)handle; (void)x; (void)y; (void)button; (void)action; (void)delta_x; (void)delta_y;
}

void rdp_freerdp_send_key(rdp_bridge_handle* handle, uint16_t key_code, int action, uint8_t modifiers) {
    (void)handle; (void)key_code; (void)action; (void)modifiers;
}

void rdp_freerdp_send_text(rdp_bridge_handle* handle, const char* text) {
    (void)handle; (void)text;
}

void rdp_freerdp_send_capture_audio(rdp_bridge_handle* handle, const int16_t* samples, int sample_count, int sample_rate, int channels) {
    (void)handle; (void)samples; (void)sample_count; (void)sample_rate; (void)channels;
}

#endif /* RDP_BRIDGE_HAS_FREERDP */
