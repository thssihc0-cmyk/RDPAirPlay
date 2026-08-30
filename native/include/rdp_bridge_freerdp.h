#ifndef RDP_BRIDGE_FREERDP_H
#define RDP_BRIDGE_FREERDP_H

#include <pthread.h>
#include <stdint.h>

typedef struct rdp_bridge_handle rdp_bridge_handle;

typedef struct rdp_freerdp_context {
    void* instance;
    pthread_t thread;
    int running;
} rdp_freerdp_context;

int rdp_freerdp_connect_async(rdp_bridge_handle* handle);
void rdp_freerdp_disconnect(rdp_bridge_handle* handle);
int rdp_freerdp_set_resolution(rdp_bridge_handle* handle, int width, int height);

void rdp_freerdp_send_mouse(rdp_bridge_handle* handle, int x, int y, int button, int action, int delta_x, int delta_y);
void rdp_freerdp_send_key(rdp_bridge_handle* handle, uint16_t key_code, int action, uint8_t modifiers);
void rdp_freerdp_send_text(rdp_bridge_handle* handle, const char* text);
void rdp_freerdp_send_capture_audio(rdp_bridge_handle* handle, const int16_t* samples, int sample_count, int sample_rate, int channels);

#endif
