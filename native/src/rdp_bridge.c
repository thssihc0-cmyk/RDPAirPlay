#include "rdp_bridge_internal.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#ifdef RDP_BRIDGE_HAS_FREERDP
#include "rdp_bridge_freerdp.h"
#endif

static const char* kBridgeVersion = "0.3.3-posix";

static char* dup_string(const char* value) {
    if (!value) {
        return NULL;
    }
    size_t length = strlen(value) + 1;
    char* copy = (char*)malloc(length);
    if (copy) {
        memcpy(copy, value, length);
    }
    return copy;
}

static void free_config_strings(rdp_bridge_handle* bridge) {
    free(bridge->hostname_copy);
    free(bridge->username_copy);
    free(bridge->password_copy);
    bridge->hostname_copy = NULL;
    bridge->username_copy = NULL;
    bridge->password_copy = NULL;
}

static int copy_config(rdp_bridge_handle* bridge, const rdp_bridge_config* config) {
    free_config_strings(bridge);
    bridge->hostname_copy = dup_string(config->hostname);
    bridge->username_copy = dup_string(config->username);
    bridge->password_copy = dup_string(config->password);
    if (!bridge->hostname_copy || !bridge->username_copy || !bridge->password_copy) {
        free_config_strings(bridge);
        return -1;
    }

    bridge->config = *config;
    bridge->config.hostname = bridge->hostname_copy;
    bridge->config.username = bridge->username_copy;
    bridge->config.password = bridge->password_copy;
    return 0;
}

static void tcp_set_error(char* error, int error_len, const char* format, ...) {
    va_list args;
    if (!error || error_len <= 0)
        return;
    va_start(args, format);
    vsnprintf(error, (size_t)error_len, format, args);
    va_end(args);
}

static int tcp_wait_writable(int fd, int timeout_ms) {
    struct pollfd pfd;
    int remaining = timeout_ms > 0 ? timeout_ms : 20000;

    pfd.fd = fd;
    pfd.events = POLLOUT;
    pfd.revents = 0;

    while (remaining > 0) {
        int slice = remaining > 250 ? 250 : remaining;
        int rc = poll(&pfd, 1, slice);
        if (rc > 0)
            return (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) ? -1 : 0;
        if (rc < 0 && errno != EINTR)
            return -1;
        remaining -= slice;
    }
    errno = ETIMEDOUT;
    return -1;
}

static int tcp_is_retryable(int err) {
    return err == EHOSTUNREACH || err == ENETUNREACH || err == EADDRNOTAVAIL ||
           err == ETIMEDOUT || err == ECONNRESET || err == ENETDOWN || err == EAGAIN;
}

static int tcp_connect_one(const struct addrinfo* addr, int timeout_ms) {
    int fd;
    int flags;
    int so_error = 0;
    socklen_t len = sizeof(so_error);
    int nodelay = 1;

    fd = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
    if (fd < 0)
        return -1;

    flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        close(fd);
        return -1;
    }

    if (connect(fd, addr->ai_addr, addr->ai_addrlen) < 0 && errno != EINPROGRESS) {
        close(fd);
        return -1;
    }

    if (tcp_wait_writable(fd, timeout_ms) < 0) {
        close(fd);
        return -1;
    }

    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_error, &len) < 0 || so_error != 0) {
        if (so_error != 0)
            errno = so_error;
        close(fd);
        return -1;
    }

    (void)fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
    (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
#ifdef SO_NOSIGPIPE
    {
        int nosig = 1;
        (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof(nosig));
    }
#endif
    return fd;
}

int rdp_bridge_tcp_connect_fd(const char* hostname, int port, int timeout_ms, char* error, int error_len) {
    struct addrinfo hints;
    struct addrinfo* result = NULL;
    struct addrinfo* cursor = NULL;
    struct addrinfo* ipv4 = NULL;
    struct addrinfo* ipv6 = NULL;
    char port_str[16];
    int fd = -1;
    int status;

    if (error && error_len > 0)
        error[0] = '\0';

    if (!hostname || hostname[0] == '\0' || port <= 0 || port > 65535) {
        tcp_set_error(error, error_len, "无效主机或端口");
        return -1;
    }

    snprintf(port_str, sizeof(port_str), "%d", port);
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    status = getaddrinfo(hostname, port_str, &hints, &result);
    if (status != 0 || !result) {
        tcp_set_error(error, error_len, "DNS/解析失败 %s: %s", hostname, gai_strerror(status));
        return -1;
    }

    for (cursor = result; cursor; cursor = cursor->ai_next) {
        if (!ipv4 && cursor->ai_family == AF_INET)
            ipv4 = cursor;
        if (!ipv6 && cursor->ai_family == AF_INET6)
            ipv6 = cursor;
    }

    {
        int attempt;
        int last_err = 0;
        for (attempt = 0; attempt < 3 && fd < 0; attempt++) {
            if (attempt > 0)
                usleep(400000);
            if (ipv4)
                fd = tcp_connect_one(ipv4, timeout_ms);
            if (fd < 0 && ipv6)
                fd = tcp_connect_one(ipv6, timeout_ms);
            if (fd < 0) {
                for (cursor = result; cursor && fd < 0; cursor = cursor->ai_next) {
                    if (cursor == ipv4 || cursor == ipv6)
                        continue;
                    fd = tcp_connect_one(cursor, timeout_ms);
                }
            }
            last_err = errno;
            if (fd < 0 && !tcp_is_retryable(last_err))
                break;
        }
        if (fd < 0)
            errno = last_err;
    }

    freeaddrinfo(result);

    if (fd < 0) {
        tcp_set_error(error, error_len, "POSIX connect %s:%d 失败: %s", hostname, port, strerror(errno));
        return -1;
    }
    return fd;
}

int rdp_bridge_tcp_probe(const char* hostname, int port, int timeout_ms, char* error, int error_len) {
    int fd = rdp_bridge_tcp_connect_fd(hostname, port, timeout_ms, error, error_len);
    if (fd < 0)
        return -1;
    close(fd);
    tcp_set_error(error, error_len, "POSIX TCP 探测成功 %s:%d", hostname, port);
    return 0;
}

int rdp_bridge_is_available(void) {
#ifdef RDP_BRIDGE_HAS_FREERDP
    return 1;
#else
    return 0;
#endif
}

const char* rdp_bridge_version(void) {
    return kBridgeVersion;
}

void rdp_bridge_emit_event(rdp_bridge_handle* handle, int type, const char* message) {
    if (handle && handle->callbacks.on_event) {
        handle->callbacks.on_event(type, message ? message : "", handle->callbacks.user_data);
    }
}

void* rdp_bridge_create(void) {
    rdp_bridge_handle* handle = calloc(1, sizeof(rdp_bridge_handle));
    if (!handle) {
        return NULL;
    }
    pthread_mutex_init(&handle->mutex, NULL);
    return handle;
}

void rdp_bridge_destroy(void* handle) {
    rdp_bridge_handle* bridge = (rdp_bridge_handle*)handle;
    if (!bridge) {
        return;
    }
    rdp_bridge_disconnect(handle);
    free_config_strings(bridge);
    pthread_mutex_destroy(&bridge->mutex);
    free(bridge);
}

int rdp_bridge_connect(void* handle, const rdp_bridge_config* config, const rdp_bridge_callbacks* callbacks) {
    rdp_bridge_handle* bridge = (rdp_bridge_handle*)handle;
    if (!bridge || !config || !callbacks) {
        return -1;
    }

    pthread_mutex_lock(&bridge->mutex);
    bridge->callbacks = *callbacks;
    if (copy_config(bridge, config) != 0) {
        pthread_mutex_unlock(&bridge->mutex);
        return -1;
    }
    bridge->connected = 0;
    pthread_mutex_unlock(&bridge->mutex);

#ifdef RDP_BRIDGE_HAS_FREERDP
    return rdp_freerdp_connect_async(bridge);
#else
    rdp_bridge_emit_event(bridge, RDP_BRIDGE_EVENT_ERROR, "FreeRDP not built. Run scripts/build_freerdp_ios.sh");
    return -2;
#endif
}

void rdp_bridge_disconnect(void* handle) {
    rdp_bridge_handle* bridge = (rdp_bridge_handle*)handle;
    if (!bridge) {
        return;
    }
#ifdef RDP_BRIDGE_HAS_FREERDP
    rdp_freerdp_disconnect(bridge);
#endif
    bridge->connected = 0;
}

int rdp_bridge_set_resolution(void* handle, int width, int height) {
#ifdef RDP_BRIDGE_HAS_FREERDP
    return rdp_freerdp_set_resolution((rdp_bridge_handle*)handle, width, height);
#else
    (void)handle;
    (void)width;
    (void)height;
    return -1;
#endif
}

void rdp_bridge_send_mouse(void* handle, int x, int y, int button, int action, int delta_x, int delta_y) {
#ifdef RDP_BRIDGE_HAS_FREERDP
    rdp_freerdp_send_mouse((rdp_bridge_handle*)handle, x, y, button, action, delta_x, delta_y);
#else
    (void)handle; (void)x; (void)y; (void)button; (void)action; (void)delta_x; (void)delta_y;
#endif
}

void rdp_bridge_send_key(void* handle, uint16_t key_code, int action, uint8_t modifiers) {
#ifdef RDP_BRIDGE_HAS_FREERDP
    rdp_freerdp_send_key((rdp_bridge_handle*)handle, key_code, action, modifiers);
#else
    (void)handle; (void)key_code; (void)action; (void)modifiers;
#endif
}

void rdp_bridge_send_text(void* handle, const char* text) {
#ifdef RDP_BRIDGE_HAS_FREERDP
    rdp_freerdp_send_text((rdp_bridge_handle*)handle, text);
#else
    (void)handle; (void)text;
#endif
}

void rdp_bridge_send_capture_audio(void* handle, const int16_t* samples, int sample_count, int sample_rate, int channels) {
#ifdef RDP_BRIDGE_HAS_FREERDP
    rdp_freerdp_send_capture_audio((rdp_bridge_handle*)handle, samples, sample_count, sample_rate, channels);
#else
    (void)handle; (void)samples; (void)sample_count; (void)sample_rate; (void)channels;
#endif
}
