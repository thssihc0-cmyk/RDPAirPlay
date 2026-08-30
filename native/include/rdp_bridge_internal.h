#ifndef RDP_BRIDGE_INTERNAL_H
#define RDP_BRIDGE_INTERNAL_H

#include "rdp_bridge.h"
#include "rdp_bridge_freerdp.h"

#include <pthread.h>

typedef struct rdp_bridge_handle {
    rdp_bridge_callbacks callbacks;
    rdp_bridge_config config;
    char* hostname_copy;
    char* username_copy;
    char* password_copy;
    int connected;
    pthread_mutex_t mutex;
    rdp_freerdp_context* freerdp;
} rdp_bridge_handle;

void rdp_bridge_emit_event(rdp_bridge_handle* handle, int type, const char* message);

#endif
