#ifndef GXFP_MILAN_RX_DRAIN_H
#define GXFP_MILAN_RX_DRAIN_H

#include "milan_attempt.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum gxfp_evk_rx_stop_reason {
    GXFP_EVK_RX_STOP_NONE = 0,
    GXFP_EVK_RX_STOP_FF_HEADER,
    GXFP_EVK_RX_STOP_INVALID_FRAME,
    GXFP_EVK_RX_STOP_OVERSIZE,
    GXFP_EVK_RX_STOP_IO_ERROR,
};

struct gxfp_evk_rx_io {
    void *ctx;
    int (*get_irq_level)(void *ctx);
    enum gxfp_io_result (*wait_irq_high)(void *ctx, unsigned timeout_ms);
    enum gxfp_io_result (*read_exact)(void *ctx, uint8_t *buf, size_t len);
    uint64_t (*monotonic_ms)(void *ctx);
    int (*is_cancelled)(void *ctx);
};

struct gxfp_evk_rx_adapter {
    struct gxfp_evk_rx_io io;
    bool ack_seen;
    uint8_t ack_status;
    bool response_seen;
    uint8_t response[64];
    size_t response_len;
    bool terminal;
    enum gxfp_evk_rx_stop_reason stop_reason;
};

bool gxfp_evk_rx_adapter_init(struct gxfp_evk_rx_adapter *adapter,
                              const struct gxfp_evk_rx_io *io);

enum gxfp_io_result gxfp_evk_rx_wait_ack(void *ctx,
                                          uint8_t cmd0,
                                          uint8_t cmd1,
                                          unsigned timeout_ms);

enum gxfp_io_result gxfp_evk_rx_wait_response(void *ctx,
                                               uint8_t event_index,
                                               unsigned timeout_ms);

const uint8_t *gxfp_evk_rx_response(const struct gxfp_evk_rx_adapter *adapter,
                                    size_t *response_len);

#endif
