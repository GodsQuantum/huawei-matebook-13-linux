#ifndef GXFP_LINUX_ACTIVE_BACKEND_H
#define GXFP_LINUX_ACTIVE_BACKEND_H

#include "linux_spi.h"
#include "../milan_attempt.h"
#include "../milan_rx_drain.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum gxfp_io_result (*gxfp_linux_sleep_ms_fn)(void *ctx,
                                                       unsigned ms);

enum gxfp_linux_transfer_direction {
    GXFP_LINUX_TRANSFER_WRITE = 0,
    GXFP_LINUX_TRANSFER_READ,
};

typedef void (*gxfp_linux_transfer_trace_fn)(
    void *ctx,
    enum gxfp_linux_transfer_direction direction,
    size_t len,
    int rc);

/*
 * GPIO48 is ACPI level-triggered ActiveHigh and its Intel pad is firmware
 * configuration-locked on the target.  The research backend therefore reads
 * only the current logical level and polls it in bounded sleeps.  It does not
 * request edge detection or alter IRQ trigger configuration.
 */
struct gxfp_linux_level_ops {
    void *ctx;
    int (*get_value)(void *ctx);
    int64_t (*monotonic_now_ns)(void *ctx);
    int (*is_cancelled)(void *ctx);
};

struct gxfp_linux_active_backend {
    struct gxfp_spi *spi;
    struct gxfp_linux_level_ops level_ops;
    gxfp_linux_sleep_ms_fn sleep_ms_fn;
    void *sleep_ctx;
    struct gxfp_evk_rx_adapter rx;
    gxfp_linux_transfer_trace_fn trace_fn;
    void *trace_ctx;
};

bool gxfp_linux_active_backend_init(struct gxfp_linux_active_backend *backend,
                                    struct gxfp_spi *spi,
                                    const struct gxfp_linux_level_ops *level_ops,
                                    gxfp_linux_sleep_ms_fn sleep_ms_fn,
                                    void *sleep_ctx);

void gxfp_linux_active_backend_set_trace(
    struct gxfp_linux_active_backend *backend,
    gxfp_linux_transfer_trace_fn trace_fn,
    void *trace_ctx);

bool gxfp_linux_active_backend_attempt(struct gxfp_linux_active_backend *backend,
                                       struct gxfp_attempt_backend *attempt);

enum gxfp_io_result
gxfp_linux_active_backend_send_driver_install(
    struct gxfp_linux_active_backend *backend);

const uint8_t *gxfp_linux_active_backend_response(
    const struct gxfp_linux_active_backend *backend,
    size_t *response_len);

#endif
