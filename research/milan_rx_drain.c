#include "milan_rx_drain.h"

#include "milan_rx.h"

#include <limits.h>
#include <string.h>

#define GXFP_EVK_CMD0 0x0au
#define GXFP_EVK_CMD1 0x04u
#define GXFP_EVK_EVENT_INDEX 9u
#define GXFP_EVK_MAX_BODY 68u

static unsigned remaining_ms(const struct gxfp_evk_rx_adapter *adapter,
                             uint64_t deadline_ms)
{
    uint64_t now = adapter->io.monotonic_ms(adapter->io.ctx);
    uint64_t remaining;

    if (now >= deadline_ms)
        return 0;

    remaining = deadline_ms - now;
    if (remaining > UINT_MAX)
        return UINT_MAX;
    return (unsigned)remaining;
}

static void stop_terminal(struct gxfp_evk_rx_adapter *adapter,
                          enum gxfp_evk_rx_stop_reason reason)
{
    adapter->terminal = true;
    adapter->stop_reason = reason;
}

static enum gxfp_io_result wait_for_target(struct gxfp_evk_rx_adapter *adapter,
                                           bool want_ack,
                                           uint8_t ack_cmd0,
                                           uint8_t ack_cmd1,
                                           unsigned timeout_ms)
{
    uint64_t start_ms;
    uint64_t deadline_ms;

    if (adapter == NULL || adapter->terminal)
        return GXFP_IO_ERROR;

    if ((want_ack && adapter->ack_seen) || (!want_ack && adapter->response_seen))
        return GXFP_IO_OK;
    if (timeout_ms == 0)
        return GXFP_IO_TIMEOUT;

    start_ms = adapter->io.monotonic_ms(adapter->io.ctx);
    deadline_ms = start_ms + (uint64_t)timeout_ms;
    if (deadline_ms < start_ms)
        deadline_ms = UINT64_MAX;

    for (;;) {
        uint8_t header[4];
        uint8_t body[GXFP_EVK_MAX_BODY];
        size_t body_len;
        struct gxfp_milan_evk_frame frame;
        enum gxfp_io_result io;
        int irq_level;
        unsigned wait_ms;

        if (adapter->io.is_cancelled(adapter->io.ctx))
            return GXFP_IO_CANCELLED;

        irq_level = adapter->io.get_irq_level(adapter->io.ctx);
        if (irq_level < 0)
            return GXFP_IO_ERROR;

        if (irq_level == 0) {
            wait_ms = remaining_ms(adapter, deadline_ms);
            if (wait_ms == 0)
                return GXFP_IO_TIMEOUT;

            io = adapter->io.wait_irq_high(adapter->io.ctx, wait_ms);
            if (io != GXFP_IO_OK)
                return io;
            continue;
        }

        io = adapter->io.read_exact(adapter->io.ctx, header, sizeof(header));
        if (io != GXFP_IO_OK) {
            stop_terminal(adapter, GXFP_EVK_RX_STOP_IO_ERROR);
            return io;
        }

        if (gxfp_milan_rx_is_ff_header(header)) {
            stop_terminal(adapter, GXFP_EVK_RX_STOP_FF_HEADER);
            return GXFP_IO_ERROR;
        }

        if (!gxfp_milan_rx_outer_body_len(header, &body_len)) {
            stop_terminal(adapter, GXFP_EVK_RX_STOP_INVALID_FRAME);
            return GXFP_IO_ERROR;
        }

        if (body_len > sizeof(body)) {
            stop_terminal(adapter, GXFP_EVK_RX_STOP_OVERSIZE);
            return GXFP_IO_ERROR;
        }

        io = adapter->io.read_exact(adapter->io.ctx, body, body_len);
        if (io != GXFP_IO_OK) {
            stop_terminal(adapter, GXFP_EVK_RX_STOP_IO_ERROR);
            return io;
        }

        if (!gxfp_milan_rx_classify_evk(body, body_len, &frame)) {
            stop_terminal(adapter, GXFP_EVK_RX_STOP_INVALID_FRAME);
            return GXFP_IO_ERROR;
        }

        if (frame.kind == GXFP_MILAN_EVK_ACK &&
            frame.ack_cmd0 == ack_cmd0 && frame.ack_cmd1 == ack_cmd1) {
            adapter->ack_seen = true;
            adapter->ack_status = frame.ack_status;
        } else if (frame.kind == GXFP_MILAN_EVK_RESPONSE) {
            memcpy(adapter->response, frame.payload, frame.payload_len);
            adapter->response_len = frame.payload_len;
            adapter->response_seen = true;
        }

        if ((want_ack && adapter->ack_seen) || (!want_ack && adapter->response_seen))
            return GXFP_IO_OK;

        if (remaining_ms(adapter, deadline_ms) == 0)
            return GXFP_IO_TIMEOUT;
    }
}

bool gxfp_evk_rx_adapter_init(struct gxfp_evk_rx_adapter *adapter,
                              const struct gxfp_evk_rx_io *io)
{
    if (adapter == NULL || io == NULL || io->get_irq_level == NULL ||
        io->wait_irq_high == NULL || io->read_exact == NULL ||
        io->monotonic_ms == NULL || io->is_cancelled == NULL)
        return false;

    memset(adapter, 0, sizeof(*adapter));
    adapter->io = *io;
    return true;
}

enum gxfp_io_result gxfp_evk_rx_wait_ack(void *ctx,
                                          uint8_t cmd0,
                                          uint8_t cmd1,
                                          unsigned timeout_ms)
{
    struct gxfp_evk_rx_adapter *adapter = ctx;

    if (adapter == NULL || cmd0 > 0x0fu || cmd1 > 0x07u)
        return GXFP_IO_ERROR;

    /* Each wait_ack call follows a fresh command send (initial or retransmit). */
    adapter->ack_seen = false;
    adapter->ack_status = 0;
    adapter->response_seen = false;
    adapter->response_len = 0;

    return wait_for_target(adapter, true, cmd0, cmd1, timeout_ms);
}

enum gxfp_io_result gxfp_evk_rx_wait_response(void *ctx,
                                               uint8_t event_index,
                                               unsigned timeout_ms)
{
    struct gxfp_evk_rx_adapter *adapter = ctx;

    if (adapter == NULL || event_index != GXFP_EVK_EVENT_INDEX)
        return GXFP_IO_ERROR;

    return wait_for_target(adapter, false, GXFP_EVK_CMD0, GXFP_EVK_CMD1, timeout_ms);
}

const uint8_t *gxfp_evk_rx_response(const struct gxfp_evk_rx_adapter *adapter,
                                    size_t *response_len)
{
    if (adapter == NULL || response_len == NULL || !adapter->response_seen)
        return NULL;

    *response_len = adapter->response_len;
    return adapter->response;
}
