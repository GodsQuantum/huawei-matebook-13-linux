#include "milan_packet.h"

#include <string.h>

static void build_outer(uint8_t inner_len, uint8_t outer[4])
{
    outer[0] = 0xa0;
    outer[1] = inner_len;
    outer[2] = 0x00;
    outer[3] = (uint8_t)(outer[0] + outer[1] + outer[2]);
}

bool gxfp_build_nop(struct gxfp_wire_packet *packet)
{
    static const uint8_t inner[] = {
        0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa5,
    };

    if (!packet)
        return false;

    memset(packet, 0, sizeof(*packet));
    packet->inner_len = sizeof(inner);
    memcpy(packet->inner, inner, sizeof(inner));
    build_outer((uint8_t)packet->inner_len, packet->outer);
    return true;
}

bool gxfp_build_driver_state_install(struct gxfp_wire_packet *packet)
{
    static const uint8_t inner[] = {
        0x96, 0x03, 0x00, 0x01, 0x00, 0x10,
    };

    if (!packet)
        return false;

    memset(packet, 0, sizeof(*packet));
    packet->inner_len = sizeof(inner);
    memcpy(packet->inner, inner, sizeof(inner));
    build_outer((uint8_t)packet->inner_len, packet->outer);
    return true;
}

bool gxfp_build_a4(const uint8_t payload[2], struct gxfp_wire_packet *packet)
{
    uint8_t checksum;

    if (!payload || !packet)
        return false;

    memset(packet, 0, sizeof(*packet));
    packet->inner_len = 6;
    packet->inner[0] = 0xa8;
    packet->inner[1] = 0x03;
    packet->inner[2] = 0x00;
    packet->inner[3] = payload[0];
    packet->inner[4] = payload[1];

    checksum = (uint8_t)(0xaa - packet->inner[0] - packet->inner[1] -
                         packet->inner[2] - packet->inner[3] -
                         packet->inner[4]);
    packet->inner[5] = checksum;

    build_outer((uint8_t)packet->inner_len, packet->outer);
    return true;
}
