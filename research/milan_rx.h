#ifndef GXFP_MILAN_RX_H
#define GXFP_MILAN_RX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum gxfp_milan_evk_frame_kind {
    GXFP_MILAN_EVK_OTHER = 0,
    GXFP_MILAN_EVK_ACK,
    GXFP_MILAN_EVK_RESPONSE,
};

struct gxfp_milan_evk_frame {
    enum gxfp_milan_evk_frame_kind kind;
    uint8_t cmd0;
    uint8_t cmd1;
    const uint8_t *payload;
    size_t payload_len;
    uint8_t ack_status;
};

/* Return true only for the explicit 0xff 0xff 0xff 0xff no-data sentinel. */
bool gxfp_milan_rx_is_ff_header(const uint8_t header[4]);

/*
 * Validate a Milan outer A-frame header and return the exact body length.
 * The caller must clock exactly this many bytes and no more.
 */
bool gxfp_milan_rx_outer_body_len(const uint8_t header[4], size_t *body_len);

/*
 * Parse one complete outer-A body for the GetEvkVersion path only.
 *
 * Windows 1.1.141.36 classifies cmd0=B/cmd1=0 as the message/ACK path;
 * its first payload byte is the packed command being acknowledged.  For A/4
 * this byte is 0xA8.  A normal A/4 frame is the separate EVK response path.
 * Fragmented frames (packed-command bit0 set) are intentionally unsupported.
 */
bool gxfp_milan_rx_classify_evk(const uint8_t *body,
                                size_t body_len,
                                struct gxfp_milan_evk_frame *frame);

#endif
