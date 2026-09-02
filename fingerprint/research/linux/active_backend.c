#include "active_backend.h"

#include "../milan_packet.h"

#include <limits.h>
#include <string.h>

#define GXFP_PACKET_GAP_MS 2u
#define GXFP_IRQ_POLL_SLICE_MS 5u
#define NS_PER_MS 1000000LL

static int cancelled(struct gxfp_linux_active_backend *backend)
{
    return backend->level_ops.is_cancelled(backend->level_ops.ctx);
}

static void trace_transfer(struct gxfp_linux_active_backend *backend,
                           enum gxfp_linux_transfer_direction direction,
                           size_t len,
                           int rc)
{
    if (backend->trace_fn != NULL)
        backend->trace_fn(backend->trace_ctx, direction, len, rc);
}

static enum gxfp_io_result send_packet(struct gxfp_linux_active_backend *backend,
                                       const struct gxfp_wire_packet *packet)
{
    enum gxfp_io_result io;

    if (backend == NULL || packet == NULL)
        return GXFP_IO_ERROR;
    if (cancelled(backend))
        return GXFP_IO_CANCELLED;

    {
        int rc = gxfp_spi_write_exact(backend->spi, packet->outer,
                                      sizeof(packet->outer));
        trace_transfer(backend, GXFP_LINUX_TRANSFER_WRITE,
                       sizeof(packet->outer), rc);
        if (rc < 0)
            return GXFP_IO_ERROR;
    }

    io = backend->sleep_ms_fn(backend->sleep_ctx, GXFP_PACKET_GAP_MS);
    if (io != GXFP_IO_OK)
        return io;

    if (cancelled(backend))
        return GXFP_IO_CANCELLED;

    {
        int rc = gxfp_spi_write_exact(backend->spi, packet->inner,
                                      packet->inner_len);
        trace_transfer(backend, GXFP_LINUX_TRANSFER_WRITE,
                       packet->inner_len, rc);
        if (rc < 0)
            return GXFP_IO_ERROR;
    }

    return GXFP_IO_OK;
}

static enum gxfp_io_result active_send_nop(void *ctx)
{
    struct gxfp_linux_active_backend *backend = ctx;
    struct gxfp_wire_packet packet;

    if (backend == NULL || !gxfp_build_nop(&packet))
        return GXFP_IO_ERROR;
    return send_packet(backend, &packet);
}

static enum gxfp_io_result active_sleep_ms(void *ctx, unsigned ms)
{
    struct gxfp_linux_active_backend *backend = ctx;

    if (backend == NULL)
        return GXFP_IO_ERROR;
    if (cancelled(backend))
        return GXFP_IO_CANCELLED;
    return backend->sleep_ms_fn(backend->sleep_ctx, ms);
}

static enum gxfp_io_result active_send_a4(void *ctx,
                                           const uint8_t payload[2])
{
    struct gxfp_linux_active_backend *backend = ctx;
    struct gxfp_wire_packet packet;

    if (backend == NULL || payload == NULL || !gxfp_build_a4(payload, &packet))
        return GXFP_IO_ERROR;
    return send_packet(backend, &packet);
}

static int rx_get_irq_level(void *ctx)
{
    struct gxfp_linux_active_backend *backend = ctx;

    if (backend == NULL || backend->level_ops.get_value == NULL)
        return -1;
    return backend->level_ops.get_value(backend->level_ops.ctx);
}

static unsigned ceil_ns_to_ms(int64_t ns)
{
    int64_t ms;

    if (ns <= 0)
        return 0;

    ms = ns / NS_PER_MS;
    if (ns % NS_PER_MS != 0)
        ms++;
    if (ms > (int64_t)UINT_MAX)
        return UINT_MAX;
    return (unsigned)ms;
}

static enum gxfp_io_result rx_wait_irq_high(void *ctx, unsigned timeout_ms)
{
    struct gxfp_linux_active_backend *backend = ctx;
    int64_t now;
    int64_t deadline;
    int64_t delta;

    if (backend == NULL)
        return GXFP_IO_ERROR;
    if (timeout_ms == 0)
        return GXFP_IO_TIMEOUT;
    if (backend->level_ops.wait_high != NULL)
        return backend->level_ops.wait_high(backend->level_ops.ctx, timeout_ms);
    if (backend->level_ops.get_value == NULL)
        return GXFP_IO_ERROR;

    now = backend->level_ops.monotonic_now_ns(backend->level_ops.ctx);
    if (now < 0)
        return GXFP_IO_ERROR;

    /* unsigned timeout_ms * 1e6 always fits in int64_t. */
    delta = (int64_t)timeout_ms * NS_PER_MS;

    if (delta > INT64_MAX - now)
        deadline = INT64_MAX;
    else
        deadline = now + delta;

    for (;;) {
        int level;
        int64_t remaining_ns;
        unsigned sleep_ms;
        enum gxfp_io_result io;

        if (cancelled(backend))
            return GXFP_IO_CANCELLED;

        level = backend->level_ops.get_value(backend->level_ops.ctx);
        if (level < 0)
            return GXFP_IO_ERROR;
        if (level > 0)
            return GXFP_IO_OK;

        now = backend->level_ops.monotonic_now_ns(backend->level_ops.ctx);
        if (now < 0)
            return GXFP_IO_ERROR;
        if (now >= deadline)
            return GXFP_IO_TIMEOUT;

        remaining_ns = deadline - now;
        sleep_ms = ceil_ns_to_ms(remaining_ns);
        if (sleep_ms > GXFP_IRQ_POLL_SLICE_MS)
            sleep_ms = GXFP_IRQ_POLL_SLICE_MS;
        if (sleep_ms == 0)
            return GXFP_IO_TIMEOUT;

        io = backend->sleep_ms_fn(backend->sleep_ctx, sleep_ms);
        if (io != GXFP_IO_OK)
            return io;
    }
}

static enum gxfp_io_result rx_read_exact(void *ctx,
                                          uint8_t *buf,
                                          size_t len)
{
    struct gxfp_linux_active_backend *backend = ctx;

    if (backend == NULL)
        return GXFP_IO_ERROR;
    if (cancelled(backend))
        return GXFP_IO_CANCELLED;
    {
        int rc = gxfp_spi_read_exact(backend->spi, buf, len);
        trace_transfer(backend, GXFP_LINUX_TRANSFER_READ, len, rc);
        if (rc < 0)
            return GXFP_IO_ERROR;
    }
    return GXFP_IO_OK;
}

static uint64_t rx_monotonic_ms(void *ctx)
{
    struct gxfp_linux_active_backend *backend = ctx;
    int64_t now;

    if (backend == NULL)
        return 0;
    now = backend->level_ops.monotonic_now_ns(backend->level_ops.ctx);
    if (now < 0)
        return 0;
    return (uint64_t)now / (uint64_t)NS_PER_MS;
}

static int rx_is_cancelled(void *ctx)
{
    struct gxfp_linux_active_backend *backend = ctx;

    if (backend == NULL)
        return 1;
    return cancelled(backend);
}

static enum gxfp_io_result active_wait_ack(void *ctx,
                                            uint8_t cmd0,
                                            uint8_t cmd1,
                                            unsigned timeout_ms)
{
    struct gxfp_linux_active_backend *backend = ctx;
    return gxfp_evk_rx_wait_ack(&backend->rx, cmd0, cmd1, timeout_ms);
}

static enum gxfp_io_result active_wait_response(void *ctx,
                                                 uint8_t event_index,
                                                 unsigned timeout_ms)
{
    struct gxfp_linux_active_backend *backend = ctx;
    return gxfp_evk_rx_wait_response(&backend->rx, event_index, timeout_ms);
}

bool gxfp_linux_active_backend_init(struct gxfp_linux_active_backend *backend,
                                    struct gxfp_spi *spi,
                                    const struct gxfp_linux_level_ops *level_ops,
                                    gxfp_linux_sleep_ms_fn sleep_ms_fn,
                                    void *sleep_ctx)
{
    struct gxfp_evk_rx_io rx_io;

    if (backend == NULL || spi == NULL || spi->fd < 0 || spi->ops == NULL ||
        spi->ops->ioctl_fn == NULL ||
        spi->max_speed_hz != GXFP_SPI_MAX_SPEED_HZ ||
        level_ops == NULL ||
        (level_ops->get_value == NULL && level_ops->wait_high == NULL) ||
        level_ops->monotonic_now_ns == NULL ||
        level_ops->is_cancelled == NULL || sleep_ms_fn == NULL)
        return false;

    memset(backend, 0, sizeof(*backend));
    backend->spi = spi;
    backend->level_ops = *level_ops;
    backend->sleep_ms_fn = sleep_ms_fn;
    backend->sleep_ctx = sleep_ctx;

    memset(&rx_io, 0, sizeof(rx_io));
    rx_io.ctx = backend;
    rx_io.get_irq_level = rx_get_irq_level;
    rx_io.wait_irq_high = rx_wait_irq_high;
    rx_io.read_exact = rx_read_exact;
    rx_io.monotonic_ms = rx_monotonic_ms;
    rx_io.is_cancelled = rx_is_cancelled;
    rx_io.event_driven_wait = level_ops->wait_high != NULL;

    return gxfp_evk_rx_adapter_init(&backend->rx, &rx_io);
}

void gxfp_linux_active_backend_set_trace(
    struct gxfp_linux_active_backend *backend,
    gxfp_linux_transfer_trace_fn trace_fn,
    void *trace_ctx)
{
    if (backend == NULL)
        return;
    backend->trace_fn = trace_fn;
    backend->trace_ctx = trace_ctx;
}

bool gxfp_linux_active_backend_attempt(struct gxfp_linux_active_backend *backend,
                                       struct gxfp_attempt_backend *attempt)
{
    if (backend == NULL || attempt == NULL)
        return false;

    memset(attempt, 0, sizeof(*attempt));
    attempt->ctx = backend;
    attempt->send_nop = active_send_nop;
    attempt->sleep_ms = active_sleep_ms;
    attempt->send_a4 = active_send_a4;
    attempt->wait_ack = active_wait_ack;
    attempt->wait_response = active_wait_response;
    return true;
}

enum gxfp_io_result
gxfp_linux_active_backend_send_driver_install(
    struct gxfp_linux_active_backend *backend)
{
    struct gxfp_wire_packet packet;

    if (backend == NULL || !gxfp_build_driver_state_install(&packet))
        return GXFP_IO_ERROR;
    return send_packet(backend, &packet);
}

const uint8_t *gxfp_linux_active_backend_response(
    const struct gxfp_linux_active_backend *backend,
    size_t *response_len)
{
    if (backend == NULL)
        return NULL;
    return gxfp_evk_rx_response(&backend->rx, response_len);
}
