#ifndef GXFP_PROBE_HARNESS_H
#define GXFP_PROBE_HARNESS_H

#include "milan_attempt.h"

#include <stdint.h>

enum gxfp_probe_result {
    GXFP_PROBE_OK = 0,
    GXFP_PROBE_INITIAL_RESET_ERROR,
    GXFP_PROBE_PREAMBLE_ERROR,
    GXFP_PROBE_ACK_TIMEOUT,
    GXFP_PROBE_RESPONSE_TIMEOUT,
    GXFP_PROBE_CANCELLED,
    GXFP_PROBE_IO_ERROR,
    GXFP_PROBE_CLEANUP_ERROR,
    GXFP_PROBE_INVALID,
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
};

enum gxfp_io_result
gxfp_probe_restore_reset(const struct gxfp_probe_reset_ops *reset);

struct gxfp_probe_report {
    enum gxfp_probe_result primary_result;
    enum gxfp_attempt_result evk_result;
    enum gxfp_io_result cleanup_result;
};

/*
 * Runs one deliberately narrow experiment:
 * proven reset -> fixed historical DriverState preamble -> one GetEvkVersion
 * attempt -> unconditional proven reset cleanup.
 *
 * The DriverState preamble intentionally reproduces the earlier Linux test:
 * NOP, 5 ms, Install, 100 ms, Install, 100 ms.  It does not add the separate
 * Windows DriverState hard-reset branch.
 */
enum gxfp_probe_result
gxfp_probe_run(const struct gxfp_probe_reset_ops *reset,
               const struct gxfp_probe_preamble_ops *preamble,
               const struct gxfp_attempt_backend *attempt,
               const uint8_t a4_payload[2],
               struct gxfp_probe_report *report);

#endif
