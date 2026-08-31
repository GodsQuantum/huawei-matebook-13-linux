
#define _POSIX_C_SOURCE 200809L
#include "kernel_irq_runtime.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define NS_PER_SECOND 1000000000LL
#define NS_PER_MS 1000000L

static int runtime_is_cancelled(void *ctx)
{
    struct gxfp_kernel_irq_runtime *runtime = ctx;

    if (runtime == NULL)
        return 1;
    if (runtime->cancel_fn == NULL)
        return 0;
    return runtime->cancel_fn(runtime->cancel_ctx) != 0;
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

static enum gxfp_io_result runtime_wait_high(void *ctx, unsigned timeout_ms)
{
    struct gxfp_kernel_irq_runtime *runtime = ctx;
    struct gxfp_irq_wait_request request;

    if (runtime == NULL || runtime->fd < 0)
        return GXFP_IO_ERROR;
    if (runtime_is_cancelled(runtime))
        return GXFP_IO_CANCELLED;

    memset(&request, 0, sizeof(request));
    request.timeout_ms = timeout_ms;
    runtime->wait_count++;

    if (ioctl(runtime->fd, GXFP_IRQ_WAIT_WAIT, &request) == 0) {
        runtime->event_count++;
        return GXFP_IO_OK;
    }

    if (errno == ETIMEDOUT)
        return GXFP_IO_TIMEOUT;
    if (errno == EINTR)
        return GXFP_IO_CANCELLED;
    return GXFP_IO_ERROR;
}

bool gxfp_kernel_irq_runtime_open(struct gxfp_kernel_irq_runtime *runtime,
                                  const char *path,
                                  gxfp_kernel_irq_cancel_fn cancel_fn,
                                  void *cancel_ctx)
{
    if (runtime == NULL || path == NULL || *path == '\0')
        return false;

    memset(runtime, 0, sizeof(*runtime));
    runtime->fd = -1;
    runtime->cancel_fn = cancel_fn;
    runtime->cancel_ctx = cancel_ctx;

    runtime->fd = open(path, O_RDWR | O_CLOEXEC);
    if (runtime->fd < 0)
        return false;

    if (ioctl(runtime->fd, GXFP_IRQ_WAIT_GET_INFO, &runtime->info) < 0) {
        gxfp_kernel_irq_runtime_close(runtime);
        return false;
    }

    return true;
}

void gxfp_kernel_irq_runtime_close(struct gxfp_kernel_irq_runtime *runtime)
{
    if (runtime == NULL)
        return;
    if (runtime->fd >= 0)
        close(runtime->fd);
    runtime->fd = -1;
}

void gxfp_kernel_irq_runtime_get_level_ops(
    struct gxfp_kernel_irq_runtime *runtime,
    struct gxfp_linux_level_ops *ops)
{
    if (ops == NULL)
        return;

    memset(ops, 0, sizeof(*ops));
    if (runtime == NULL)
        return;

    ops->ctx = runtime;
    ops->get_value = NULL;
    ops->wait_high = runtime_wait_high;
    ops->monotonic_now_ns = runtime_monotonic_now_ns;
    ops->is_cancelled = runtime_is_cancelled;
}

enum gxfp_io_result gxfp_kernel_irq_runtime_sleep_ms(void *ctx,
                                                     unsigned ms)
{
    struct gxfp_kernel_irq_runtime *runtime = ctx;
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
