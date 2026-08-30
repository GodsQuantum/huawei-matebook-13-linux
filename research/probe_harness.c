#include "probe_harness.h"

#include <string.h>

#define GXFP_RESET_HIGH_MS 10u
#define GXFP_RESET_LOW_MS 100u
#define GXFP_PREAMBLE_NOP_DELAY_MS 5u
#define GXFP_DRIVERSTATE_CMD0 0x09u
#define GXFP_DRIVERSTATE_CMD1 0x03u
#define GXFP_DRIVERSTATE_ACK_TIMEOUT_MS 1000u
#define GXFP_DRIVERSTATE_WRAPPER_CALLS 2u
#define GXFP_DRIVERSTATE_SENDS_PER_WRAPPER 2u

enum gxfp_io_result
gxfp_probe_restore_reset(const struct gxfp_probe_reset_ops *ops)
{
    enum gxfp_io_result first = GXFP_IO_OK;
    enum gxfp_io_result r;

    r = ops->set_level(ops->ctx, 1);
    if (first == GXFP_IO_OK && r != GXFP_IO_OK)
        first = r;

    r = ops->sleep_ms(ops->ctx, GXFP_RESET_HIGH_MS);
    if (first == GXFP_IO_OK && r != GXFP_IO_OK)
        first = r;

    /* Always attempt the safe final LOW state even after an earlier failure. */
    r = ops->set_level(ops->ctx, 0);
    if (first == GXFP_IO_OK && r != GXFP_IO_OK)
        first = r;

    r = ops->sleep_ms(ops->ctx, GXFP_RESET_LOW_MS);
    if (first == GXFP_IO_OK && r != GXFP_IO_OK)
        first = r;

    return first;
}

static enum gxfp_driver_state_result map_driver_io(enum gxfp_io_result io)
{
    if (io == GXFP_IO_CANCELLED)
        return GXFP_DRIVER_STATE_CANCELLED;
    return GXFP_DRIVER_STATE_IO_ERROR;
}

static enum gxfp_probe_result map_driver_result(enum gxfp_driver_state_result result)
{
    if (result == GXFP_DRIVER_STATE_CANCELLED)
        return GXFP_PROBE_CANCELLED;
    return GXFP_PROBE_IO_ERROR;
}

static enum gxfp_driver_state_result
run_driverstate_wrapper(const struct gxfp_probe_preamble_ops *preamble)
{
    unsigned send_index;

    for (send_index = 0; send_index < GXFP_DRIVERSTATE_SENDS_PER_WRAPPER;
         send_index++) {
        enum gxfp_io_result io;

        io = preamble->send_driver_install(preamble->ctx);
        if (io != GXFP_IO_OK)
            return map_driver_io(io);

        io = preamble->wait_ack(preamble->ctx,
                                GXFP_DRIVERSTATE_CMD0,
                                GXFP_DRIVERSTATE_CMD1,
                                GXFP_DRIVERSTATE_ACK_TIMEOUT_MS);
        if (io == GXFP_IO_OK)
            return GXFP_DRIVER_STATE_OK;
        if (io == GXFP_IO_CANCELLED)
            return GXFP_DRIVER_STATE_CANCELLED;
        if (io != GXFP_IO_TIMEOUT)
            return GXFP_DRIVER_STATE_IO_ERROR;
    }

    return GXFP_DRIVER_STATE_ACK_TIMEOUT;
}

static enum gxfp_driver_state_result
run_driverstate(const struct gxfp_probe_preamble_ops *preamble)
{
    enum gxfp_io_result io;
    unsigned wrapper_index;

    io = preamble->send_nop(preamble->ctx);
    if (io != GXFP_IO_OK)
        return map_driver_io(io);

    io = preamble->sleep_ms(preamble->ctx, GXFP_PREAMBLE_NOP_DELAY_MS);
    if (io != GXFP_IO_OK)
        return map_driver_io(io);

    for (wrapper_index = 0; wrapper_index < GXFP_DRIVERSTATE_WRAPPER_CALLS;
         wrapper_index++) {
        enum gxfp_driver_state_result result = run_driverstate_wrapper(preamble);

        if (result != GXFP_DRIVER_STATE_ACK_TIMEOUT)
            return result;
    }

    return GXFP_DRIVER_STATE_ACK_TIMEOUT;
}

static enum gxfp_probe_result map_evk(enum gxfp_attempt_result evk)
{
    switch (evk) {
    case GXFP_ATTEMPT_OK:
        return GXFP_PROBE_OK;
    case GXFP_ATTEMPT_ACK_TIMEOUT:
        return GXFP_PROBE_ACK_TIMEOUT;
    case GXFP_ATTEMPT_RESPONSE_TIMEOUT:
        return GXFP_PROBE_RESPONSE_TIMEOUT;
    case GXFP_ATTEMPT_CANCELLED:
        return GXFP_PROBE_CANCELLED;
    case GXFP_ATTEMPT_IO_ERROR:
        return GXFP_PROBE_IO_ERROR;
    case GXFP_ATTEMPT_INVALID:
    default:
        return GXFP_PROBE_IO_ERROR;
    }
}

enum gxfp_probe_result
gxfp_probe_run(const struct gxfp_probe_reset_ops *reset,
               const struct gxfp_probe_preamble_ops *preamble,
               const struct gxfp_attempt_backend *attempt,
               const uint8_t a4_payload[2],
               struct gxfp_probe_report *report)
{
    enum gxfp_probe_result primary = GXFP_PROBE_INVALID;
    enum gxfp_driver_state_result driver_state = GXFP_DRIVER_STATE_INVALID;
    enum gxfp_attempt_result evk = GXFP_ATTEMPT_INVALID;
    enum gxfp_io_result cleanup;

    if (report != NULL) {
        memset(report, 0, sizeof(*report));
        report->primary_result = GXFP_PROBE_INVALID;
        report->driver_state_result = GXFP_DRIVER_STATE_INVALID;
        report->driver_state_reset_performed = false;
        report->evk_result = GXFP_ATTEMPT_INVALID;
        report->cleanup_result = GXFP_IO_ERROR;
    }

    if (reset == NULL || reset->set_level == NULL || reset->sleep_ms == NULL ||
        preamble == NULL || preamble->send_nop == NULL ||
        preamble->send_driver_install == NULL || preamble->sleep_ms == NULL ||
        preamble->wait_ack == NULL || attempt == NULL || a4_payload == NULL ||
        report == NULL)
        return GXFP_PROBE_INVALID;

    driver_state = run_driverstate(preamble);
    report->driver_state_result = driver_state;

    if (driver_state == GXFP_DRIVER_STATE_ACK_TIMEOUT) {
        report->driver_state_reset_performed = true;
        if (gxfp_probe_restore_reset(reset) != GXFP_IO_OK) {
            primary = GXFP_PROBE_DRIVERSTATE_RESET_ERROR;
            goto cleanup;
        }
    } else if (driver_state != GXFP_DRIVER_STATE_OK) {
        primary = map_driver_result(driver_state);
        goto cleanup;
    }

    evk = gxfp_get_evk_attempt(attempt, a4_payload);
    primary = map_evk(evk);

cleanup:
    cleanup = gxfp_probe_restore_reset(reset);
    report->primary_result = primary;
    report->evk_result = evk;
    report->cleanup_result = cleanup;

    if (cleanup != GXFP_IO_OK)
        return GXFP_PROBE_CLEANUP_ERROR;
    return primary;
}
