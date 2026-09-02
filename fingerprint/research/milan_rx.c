#include "milan_rx.h"

#include <stddef.h>
#include <stdint.h>

#define GXFP_OUTER_A_CLASS 0x0au
#define GXFP_CMD_OTHER 0x0au
#define GXFP_CMD_MSG 0x0bu
#define GXFP_CMD1_EVK 0x04u
#define GXFP_CMD1_MSG_ACK 0x00u
#define GXFP_EVK_MAX_RESPONSE 64u

static uint8_t sum8(const uint8_t *buf, size_t len)
{
    uint8_t sum = 0;
    size_t i;

    for (i = 0; i < len; i++)
        sum = (uint8_t)(sum + buf[i]);

    return sum;
}

bool gxfp_milan_rx_is_ff_header(const uint8_t header[4])
{
    return header != NULL && header[0] == 0xffu && header[1] == 0xffu &&
           header[2] == 0xffu && header[3] == 0xffu;
}

bool gxfp_milan_rx_outer_body_len(const uint8_t header[4], size_t *body_len)
{
    size_t len;

    if (header == NULL || body_len == NULL)
        return false;

    if ((header[0] >> 4) != GXFP_OUTER_A_CLASS)
        return false;

    if ((uint8_t)(header[0] + header[1] + header[2]) != header[3])
        return false;

    len = (size_t)header[1] | ((size_t)header[2] << 8);
    if (len < 4)
        return false;

    *body_len = len;
    return true;
}

bool gxfp_milan_rx_classify_evk(const uint8_t *body,
                                size_t body_len,
                                struct gxfp_milan_evk_frame *frame)
{
    uint8_t packed;
    uint8_t cmd0;
    uint8_t cmd1;
    size_t inner_len;
    size_t payload_len;
    const uint8_t *payload;

    if (body == NULL || frame == NULL || body_len < 4)
        return false;

    packed = body[0];
    if ((packed & 0x01u) != 0)
        return false;

    inner_len = (size_t)body[1] | ((size_t)body[2] << 8);
    if (inner_len < 1 || inner_len + 3 != body_len)
        return false;

    if (sum8(body, body_len) != 0xaau)
        return false;

    payload_len = inner_len - 1;
    payload = body + 3;
    cmd0 = (uint8_t)(packed >> 4);
    cmd1 = (uint8_t)((packed & 0x0eu) >> 1);

    frame->kind = GXFP_MILAN_EVK_OTHER;
    frame->cmd0 = cmd0;
    frame->cmd1 = cmd1;
    frame->payload = payload;
    frame->payload_len = payload_len;
    frame->ack_cmd0 = 0;
    frame->ack_cmd1 = 0;
    frame->ack_status = 0;

    if (cmd0 == GXFP_CMD_MSG && cmd1 == GXFP_CMD1_MSG_ACK &&
        payload_len >= 2) {
        uint8_t ack_packed = payload[0];

        if ((ack_packed & 0x01u) != 0)
            return false;
        frame->kind = GXFP_MILAN_EVK_ACK;
        frame->ack_cmd0 = (uint8_t)(ack_packed >> 4);
        frame->ack_cmd1 = (uint8_t)((ack_packed & 0x0eu) >> 1);
        frame->ack_status = payload[1];
        return true;
    }

    if (cmd0 == GXFP_CMD_OTHER && cmd1 == GXFP_CMD1_EVK) {
        if (payload_len > GXFP_EVK_MAX_RESPONSE)
            return false;
        frame->kind = GXFP_MILAN_EVK_RESPONSE;
    }

    return true;
}
