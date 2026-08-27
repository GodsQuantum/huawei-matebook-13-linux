#define _POSIX_C_SOURCE 200809L
#include "active_runtime.h"

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#define NS_PER_SECOND 1000000000LL
#define NS_PER_MS 1000000L

static int runtime_get_value(void *ctx)
{
    struct gxfp_linux_active_runtime *runtime = ctx;

    if (runtime == NULL || runtime->irq == NULL)
        return -1;
    return gxfp_gpiod_irq_get_value(runtime->irq);
}

static int64_t runtime_monotonic_now_ns(void *ctx)
{
    struct timespec ts;
    int64_t base;
    (void)ctx;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0)
        return -1;
    if (ts.tv_sec < 0 || ts.tv_sec > INT64_MAX / NS_PER_SECOND)
        return -1;

    base = (int64_t)ts.tv_sec * NS_PER_SECOND;
    if (ts.tv_nsec < 0 || ts.tv_nsec >= NS_PER_SECOND ||
        ts.tv_nsec > INT64_MAX - base)
        return -1;
    return base + ts.tv_nsec;
}

static int runtime_is_cancelled(void *ctx)
{
    struct gxfp_linux_active_runtime *runtime = ctx;

    if (runtime == NULL)
        return 1;
    if (runtime->cancel_fn == NULL)
        return 0;
    return runtime->cancel_fn(runtime->cancel_ctx) != 0;
}

bool gxfp_linux_active_runtime_init(struct gxfp_linux_active_runtime *runtime,
                                    struct gxfp_gpiod_irq *irq,
                                    gxfp_linux_cancel_fn cancel_fn,
                                    void *cancel_ctx)
{
    if (runtime == NULL || irq == NULL)
        return false;

    memset(runtime, 0, sizeof(*runtime));
    runtime->irq = irq;
    runtime->cancel_fn = cancel_fn;
    runtime->cancel_ctx = cancel_ctx;
    return true;
}

void gxfp_linux_active_runtime_get_level_ops(
    struct gxfp_linux_active_runtime *runtime,
    struct gxfp_linux_level_ops *ops)
{
    if (ops == NULL)
        return;

    memset(ops, 0, sizeof(*ops));
    if (runtime == NULL)
        return;

    ops->ctx = runtime;
    ops->get_value = runtime_get_value;
    ops->monotonic_now_ns = runtime_monotonic_now_ns;
    ops->is_cancelled = runtime_is_cancelled;
}

enum gxfp_io_result gxfp_linux_active_runtime_sleep_ms(void *ctx,
                                                        unsigned ms)
{
    struct gxfp_linux_active_runtime *runtime = ctx;
    struct timespec req;
    struct timespec rem;

    if (runtime == NULL)
        return GXFP_IO_ERROR;
    if (runtime_is_cancelled(runtime))
        return GXFP_IO_CANCELLED;

    req.tv_sec = (time_t)(ms / 1000u);
    req.tv_nsec = (long)(ms % 1000u) * NS_PER_MS;

    while (nanosleep(&req, &rem) < 0) {
        if (errno != EINTR)
            return GXFP_IO_ERROR;
        if (runtime_is_cancelled(runtime))
            return GXFP_IO_CANCELLED;
        req = rem;
    }

    if (runtime_is_cancelled(runtime))
        return GXFP_IO_CANCELLED;
    return GXFP_IO_OK;
}
