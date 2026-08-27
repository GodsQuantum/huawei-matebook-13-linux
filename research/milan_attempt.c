#include "milan_attempt.h"

#define GXFP_OTHER_CMD0 0x0a
#define GXFP_EVK_CMD1 0x04
#define GXFP_EVK_RESPONSE_EVENT 9u
#define GXFP_NOP_POST_DELAY_MS 5u
#define GXFP_EFFECTIVE_ACK_TIMEOUT_MS 1000u
#define GXFP_EFFECTIVE_RESPONSE_TIMEOUT_MS 1000u

static enum gxfp_attempt_result map_io_error(enum gxfp_io_result result)
{
    if (result == GXFP_IO_CANCELLED)
        return GXFP_ATTEMPT_CANCELLED;
    return GXFP_ATTEMPT_IO_ERROR;
}

enum gxfp_attempt_result
gxfp_get_evk_attempt(const struct gxfp_attempt_backend *backend,
                     const uint8_t a4_payload[2])
{
    enum gxfp_io_result io;
    unsigned send_index;

    if (!backend || !a4_payload ||
        !backend->send_nop || !backend->sleep_ms || !backend->send_a4 ||
        !backend->wait_ack || !backend->wait_response)
        return GXFP_ATTEMPT_INVALID;

    io = backend->send_nop(backend->ctx);
    if (io != GXFP_IO_OK)
        return map_io_error(io);

    io = backend->sleep_ms(backend->ctx, GXFP_NOP_POST_DELAY_MS);
    if (io != GXFP_IO_OK)
        return map_io_error(io);

    for (send_index = 0; send_index < 2; send_index++) {
        io = backend->send_a4(backend->ctx, a4_payload);
        if (io != GXFP_IO_OK)
            return map_io_error(io);

        io = backend->wait_ack(backend->ctx,
                               GXFP_OTHER_CMD0,
                               GXFP_EVK_CMD1,
                               GXFP_EFFECTIVE_ACK_TIMEOUT_MS);
        if (io == GXFP_IO_OK)
            break;
        if (io == GXFP_IO_CANCELLED)
            return GXFP_ATTEMPT_CANCELLED;
        if (io != GXFP_IO_TIMEOUT)
            return GXFP_ATTEMPT_IO_ERROR;
        if (send_index == 1)
            return GXFP_ATTEMPT_ACK_TIMEOUT;
    }

    io = backend->wait_response(backend->ctx,
                                GXFP_EVK_RESPONSE_EVENT,
                                GXFP_EFFECTIVE_RESPONSE_TIMEOUT_MS);
    if (io == GXFP_IO_OK)
        return GXFP_ATTEMPT_OK;
    if (io == GXFP_IO_TIMEOUT)
        return GXFP_ATTEMPT_RESPONSE_TIMEOUT;
    if (io == GXFP_IO_CANCELLED)
        return GXFP_ATTEMPT_CANCELLED;
    return GXFP_ATTEMPT_IO_ERROR;
}
