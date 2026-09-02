
#include <assert.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../linux/active_backend.h"

struct transfer_record {
    int is_write;
    size_t len;
};

struct fake_ctx {
    struct transfer_record xfers[8];
    size_t xfer_count;
    const uint8_t *reads[4];
    size_t read_lens[4];
    size_t read_pos;
    unsigned waits;
    unsigned last_timeout_ms;
    unsigned sleeps;
    int64_t now_ns;
};

static struct fake_ctx *g_fake;

static int fake_ioctl(int fd, unsigned long request, void *arg)
{
    struct spi_ioc_transfer *x = arg;
    struct transfer_record *r;
    (void)fd;

    assert(request == SPI_IOC_MESSAGE(1));
    assert(g_fake != NULL);
    assert(g_fake->xfer_count < 8);

    r = &g_fake->xfers[g_fake->xfer_count++];
    r->len = x->len;
    r->is_write = x->tx_buf != 0;

    if (x->rx_buf != 0) {
        uint8_t *dst = (uint8_t *)(uintptr_t)x->rx_buf;

        assert(x->tx_buf == 0);
        assert(g_fake->read_pos < 4);
        assert(g_fake->read_lens[g_fake->read_pos] == x->len);
        memcpy(dst, g_fake->reads[g_fake->read_pos], x->len);
        g_fake->read_pos++;
    }
    return (int)x->len;
}

static int dummy_open(const char *path, int flags)
{
    (void)path;
    (void)flags;
    return -1;
}

static int dummy_close(int fd)
{
    (void)fd;
    return 0;
}

static enum gxfp_io_result fake_wait_high(void *ctx, unsigned timeout_ms)
{
    struct fake_ctx *f = ctx;

    f->waits++;
    f->last_timeout_ms = timeout_ms;
    return GXFP_IO_OK;
}

static int64_t fake_now_ns(void *ctx)
{
    return ((struct fake_ctx *)ctx)->now_ns;
}

static int fake_cancelled(void *ctx)
{
    (void)ctx;
    return 0;
}

static enum gxfp_io_result fake_sleep(void *ctx, unsigned ms)
{
    struct fake_ctx *f = ctx;

    f->sleeps++;
    f->now_ns += (int64_t)ms * 1000000LL;
    return GXFP_IO_OK;
}

int main(void)
{
    static const uint8_t ack_header[] = {0xa0, 0x06, 0x00, 0xa6};
    static const uint8_t ack_body[] = {0xb0, 0x03, 0x00, 0x96, 0x00, 0x61};
    const struct gxfp_spi_ops spi_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {
        .reads = {ack_header, ack_body},
        .read_lens = {sizeof(ack_header), sizeof(ack_body)},
    };
    struct gxfp_spi spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &spi_ops,
    };
    struct gxfp_linux_level_ops irq = {
        .ctx = &f,
        .get_value = NULL,
        .wait_high = fake_wait_high,
        .monotonic_now_ns = fake_now_ns,
        .is_cancelled = fake_cancelled,
    };
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;

    g_fake = &f;

    assert(gxfp_linux_active_backend_init(&active, &spi, &irq,
                                          fake_sleep, &f));
    assert(gxfp_linux_active_backend_attempt(&active, &attempt));
    assert(attempt.wait_ack(attempt.ctx, 9, 3, 100) == GXFP_IO_OK);

    assert(f.waits == 1);
    assert(f.last_timeout_ms == 100);
    assert(f.sleeps == 0);
    assert(f.xfer_count == 2);
    assert(f.xfers[0].is_write == 0 && f.xfers[0].len == 4);
    assert(f.xfers[1].is_write == 0 && f.xfers[1].len == 6);

    puts("test_event_driven_backend: OK");
    return 0;
}
