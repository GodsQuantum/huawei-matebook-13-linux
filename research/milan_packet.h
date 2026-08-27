#ifndef GXFP_MILAN_PACKET_H
#define GXFP_MILAN_PACKET_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct gxfp_wire_packet {
    uint8_t outer[4];
    uint8_t inner[8];
    size_t inner_len;
};

/* Deliberately restricted builders: no generic/arbitrary Milan command API. */
bool gxfp_build_nop(struct gxfp_wire_packet *packet);
bool gxfp_build_driver_state_install(struct gxfp_wire_packet *packet);
bool gxfp_build_a4(const uint8_t payload[2], struct gxfp_wire_packet *packet);

#endif
