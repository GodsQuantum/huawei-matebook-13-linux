#ifndef GXFP_PROBE_HARNESS_H
#define GXFP_PROBE_HARNESS_H

#include "milan_attempt.h"

#include <stdbool.h>
#include <stdint.h>

enum gxfp_probe_result {
    GXFP_PROBE_OK = 0,
    GXFP_PROBE_INITIAL_RESET_ERROR,
    GXFP_PROBE_PREAMBLE_ERROR,
    GXFP_PROBE_DRIVERSTATE_RESET_ERROR,
    GXFP_PROBE_ACK_TIMEOUT,
    GXFP_PROBE_RESPONSE_TIMEOUT,
    GXFP_PROBE_CANCELLED,
    GXFP_PROBE_IO_ERROR,
    GXFP_PROBE_CLEANUP_ERROR,
    GXFP_PROBE_INVALID,
};

enum gxfp_driver_state_result {
    GXFP_DRIVER_STATE_OK = 0,
    GXFP_DRIVER_STATE_ACK_TIMEOUT,
    GXFP_DRIVER_STATE_CANCELLED,
    GXFP_DRIVER_STATE_IO_ERROR,
    GXFP_DRIVER_STATE_INVALID,
};

struct gxfp_probe_reset_ops {
    void *ctx;
    enum gxfp_io_result (*set_level)(void *ctx, int level);
    enum gxfp_io_result (*sleep_ms)(void *ctx, unsigned ms);
};

struct gxfp_probe_preamble_ops {
    void *ctx;
    enum gxfp_io_result (*send_nop)(void *ctx);
    enum gxfp_io_result (*send_driver_install)(void *ctx);
    enum gxfp_io_result (*sleep_ms)(void *ctx, unsigned ms);
    enum gxfp_io_result (*wait_ack)(void *ctx,
                                    uint8_t cmd0,
                                    uint8_t cmd1,
                                    unsigned timeout_ms);
};

enum gxfp_io_result
gxfp_probe_restore_reset(const struct gxfp_probe_reset_ops *reset);

struct gxfp_probe_report {
    enum gxfp_probe_result primary_result;
    enum gxfp_driver_state_result driver_state_result;
    bool driver_state_reset_performed;
    enum gxfp_attempt_result evk_result;
    enum gxfp_io_result cleanup_result;
};

/*
 * Runs one deliberately narrow experiment:
 * proven reset -> Windows-faithful DriverState:Install ACK/retry/reset path ->
 * one GetEvkVersion attempt -> unconditional proven reset cleanup.
 *
 * DriverState uses generic B/0 ACK bookkeeping for logical CHIP 9/3, whose
 * packed command is 0x96.  Each of the two Windows wrapper calls may send the
 * exact Install packet twice under the effective 1000 ms ACK timeout.  Only
 * after both wrapper calls time out is the proven hard reset performed.
 */
enum gxfp_probe_result
gxfp_probe_run(const struct gxfp_probe_reset_ops *reset,
               const struct gxfp_probe_preamble_ops *preamble,
               const struct gxfp_attempt_backend *attempt,
               const uint8_t a4_payload[2],
               struct gxfp_probe_report *report);

#endif
