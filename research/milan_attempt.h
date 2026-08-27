#ifndef GXFP_MILAN_ATTEMPT_H
#define GXFP_MILAN_ATTEMPT_H

#include <stdint.h>

enum gxfp_io_result {
    GXFP_IO_OK = 0,
    GXFP_IO_TIMEOUT,
    GXFP_IO_CANCELLED,
    GXFP_IO_ERROR,
};

enum gxfp_attempt_result {
    GXFP_ATTEMPT_OK = 0,
    GXFP_ATTEMPT_ACK_TIMEOUT,
    GXFP_ATTEMPT_RESPONSE_TIMEOUT,
    GXFP_ATTEMPT_CANCELLED,
    GXFP_ATTEMPT_IO_ERROR,
    GXFP_ATTEMPT_INVALID,
};

struct gxfp_attempt_backend {
    void *ctx;
    enum gxfp_io_result (*send_nop)(void *ctx);
    enum gxfp_io_result (*sleep_ms)(void *ctx, unsigned ms);
    enum gxfp_io_result (*send_a4)(void *ctx, const uint8_t payload[2]);
    enum gxfp_io_result (*wait_ack)(void *ctx,
                                    uint8_t cmd0,
                                    uint8_t cmd1,
                                    unsigned timeout_ms);
    enum gxfp_io_result (*wait_response)(void *ctx,
                                         uint8_t event_index,
                                         unsigned timeout_ms);
};

/*
 * Executes one GetEvkVersion transport attempt only.
 *
 * The two A/4 payload bytes are deliberately caller-supplied: their Windows
 * values are not statically proven and this layer must never invent them.
 * This function performs no GPIO reset and no multi-attempt fallback.
 */
enum gxfp_attempt_result
gxfp_get_evk_attempt(const struct gxfp_attempt_backend *backend,
                     const uint8_t a4_payload[2]);

#endif
