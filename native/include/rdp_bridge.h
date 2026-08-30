#ifndef RDP_BRIDGE_H
#define RDP_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RDP_BRIDGE_EVENT_CONNECTED 1
#define RDP_BRIDGE_EVENT_DISCONNECTED 2
#define RDP_BRIDGE_EVENT_ERROR 3

#define RDP_MOUSE_LEFT 0
#define RDP_MOUSE_RIGHT 1
#define RDP_MOUSE_ACTION_DOWN 0
#define RDP_MOUSE_ACTION_UP 1
#define RDP_MOUSE_ACTION_MOVE 2
#define RDP_MOUSE_ACTION_SCROLL 3

#define RDP_KEY_ACTION_DOWN 0
#define RDP_KEY_ACTION_UP 1

/// 返回 1 表示 FreeRDP 已链接，0 表示 stub
int rdp_bridge_is_available(void);

const char* rdp_bridge_version(void);

/// POSIX TCP 探测/连接。成功返回 fd（probe 会立刻 close，返回 0），失败返回 -1 并写入 error。
int rdp_bridge_tcp_connect_fd(const char* hostname, int port, int timeout_ms, char* error, int error_len);
int rdp_bridge_tcp_probe(const char* hostname, int port, int timeout_ms, char* error, int error_len);

typedef struct rdp_bridge_config {
    const char* hostname;
    int port;
    const char* username;
    const char* password;
    int width;
    int height;
    int enable_nla;
    int enable_speaker;
    int enable_microphone;
} rdp_bridge_config;

typedef struct rdp_bridge_frame {
    int width;
    int height;
    const uint8_t* pixels;
    int stride;
    double timestamp;
} rdp_bridge_frame;

typedef struct rdp_bridge_audio_chunk {
    const int16_t* samples;
    int sample_count;
    int sample_rate;
    int channels;
} rdp_bridge_audio_chunk;

typedef struct rdp_bridge_cursor {
    const uint8_t* pixels;
    int width;
    int height;
    int stride;
    int hotspot_x;
    int hotspot_y;
    int x;
    int y;
    int visible;
    int has_image;
} rdp_bridge_cursor;

typedef void (*rdp_bridge_frame_callback)(const rdp_bridge_frame* frame, void* user_data);
typedef void (*rdp_bridge_event_callback)(int event_type, const char* message, void* user_data);
typedef void (*rdp_bridge_metrics_callback)(double rtt_ms, double loss_percent, int kbps, void* user_data);
typedef void (*rdp_bridge_audio_playback_callback)(const rdp_bridge_audio_chunk* chunk, void* user_data);
typedef void (*rdp_bridge_cursor_callback)(const rdp_bridge_cursor* cursor, void* user_data);

typedef struct rdp_bridge_callbacks {
    rdp_bridge_frame_callback on_frame;
    rdp_bridge_event_callback on_event;
    rdp_bridge_metrics_callback on_metrics;
    rdp_bridge_audio_playback_callback on_audio_playback;
    rdp_bridge_cursor_callback on_cursor;
    void* user_data;
} rdp_bridge_callbacks;

void* rdp_bridge_create(void);
void rdp_bridge_destroy(void* handle);

/// 异步连接，结果通过 on_event 回调（CONNECTED / ERROR）
int rdp_bridge_connect(void* handle, const rdp_bridge_config* config, const rdp_bridge_callbacks* callbacks);

void rdp_bridge_disconnect(void* handle);
int rdp_bridge_set_resolution(void* handle, int width, int height);

void rdp_bridge_send_mouse(void* handle, int x, int y, int button, int action, int delta_x, int delta_y);
void rdp_bridge_send_key(void* handle, uint16_t key_code, int action, uint8_t modifiers);
void rdp_bridge_send_text(void* handle, const char* text);

/// iOS 采集到 PCM 后喂给远程麦克风（audin）
void rdp_bridge_send_capture_audio(void* handle, const int16_t* samples, int sample_count, int sample_rate, int channels);

#ifdef __cplusplus
}
#endif

#endif /* RDP_BRIDGE_H */
