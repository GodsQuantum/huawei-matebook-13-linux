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
/*
 * Goodix FP 1.1.141.36 configuration +0x45e is
 * retry_count_for_common_init. Its compiled default is 3; the optional
 * RetryCountForComminInit registry value replaces it only when >= 1.
 */
#define GXFP_COMMON_INIT_RETRY_COUNT 3u

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

static bool evk_result_is_retryable(enum gxfp_attempt_result evk)
{
    /*
     * Windows GetEvkVersionWithRetry receives a BOOL from GetEvkVersion and
     * retries any false result.  CANCELLED and INVALID are local research
     * states with no Windows equivalent and remain terminal for safety.
     */
    return evk == GXFP_ATTEMPT_ACK_TIMEOUT ||
           evk == GXFP_ATTEMPT_RESPONSE_TIMEOUT ||
           evk == GXFP_ATTEMPT_IO_ERROR;
}

/*
 * Goodix FP 1.1.141.36 GetEvkVersionWithRetry:
 *
 * - run up to retry_count_for_common_init initial GetEvkVersion attempts;
 * - stop immediately on success;
 * - cancellation / transport errors remain terminal in this research harness;
 * - after exhausted protocol timeouts, perform the proven hard reset;
 * - immediately make exactly one final GetEvkVersion attempt.
 *
 * The target 1.1.141.36 Windows configuration field is +0x45e and its
 * compiled default is three attempts.
 */
static enum gxfp_probe_result
run_common_init_evk(const struct gxfp_probe_reset_ops *reset,
                    const struct gxfp_attempt_backend *attempt,
                    const uint8_t a4_payload[2],
                    enum gxfp_attempt_result *last_evk,
                    struct gxfp_probe_report *report)
{
    unsigned attempt_index;

    for (attempt_index = 0;
         attempt_index < GXFP_COMMON_INIT_RETRY_COUNT;
         attempt_index++) {
        *last_evk = gxfp_get_evk_attempt(attempt, a4_payload);

        if (*last_evk == GXFP_ATTEMPT_OK)
            return GXFP_PROBE_OK;

        if (!evk_result_is_retryable(*last_evk))
            return map_evk(*last_evk);
    }

    /*
     * The Windows D0Exit guard has no direct Linux equivalent inside this
     * synchronous one-shot harness.  Cancellation is already terminal above,
     * so reaching this point means the bounded experiment remains active.
     */
    /*
     * Exact Windows behavior: HardResetMcu's BOOL return is ignored here.
     * Preserve the result for diagnostics/safety accounting, then execute the
     * one final GetEvkVersion attempt unconditionally.
     */
    report->common_init_reset_performed = true;
    report->common_init_reset_result = gxfp_probe_restore_reset(reset);

    *last_evk = gxfp_get_evk_attempt(attempt, a4_payload);
    return map_evk(*last_evk);
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
        report->driver_state_reset_result = GXFP_IO_OK;
        report->common_init_reset_performed = false;
        report->common_init_reset_result = GXFP_IO_OK;
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
        /*
         * SetDriverState performs HardResetMcu after its retries.  Its caller
         * send_driver_install_to_MCU then overwrites/ignores SetDriverState's
         * return and continues into init_MCU.
         */
        report->driver_state_reset_performed = true;
        report->driver_state_reset_result = gxfp_probe_restore_reset(reset);
    } else if (driver_state != GXFP_DRIVER_STATE_OK) {
        /*
         * Cancellation is a local safety condition and remains terminal.
         * Other non-timeout transport errors are currently kept fail-closed;
         * the evidenced silent target path reaches the ACK_TIMEOUT branch.
         */
        primary = map_driver_result(driver_state);
        goto cleanup;
    }

    primary = run_common_init_evk(reset, attempt, a4_payload, &evk, report);

cleanup:
    cleanup = gxfp_probe_restore_reset(reset);
    report->primary_result = primary;
    report->evk_result = evk;
    report->cleanup_result = cleanup;

    if (cleanup != GXFP_IO_OK)
        return GXFP_PROBE_CLEANUP_ERROR;
    return primary;
}
