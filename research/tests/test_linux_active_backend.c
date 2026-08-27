#include <assert.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../linux/active_backend.h"

struct transfer_record {
    int is_write;
    size_t len;
    uint8_t data[16];
};

struct fake_ctx {
    struct transfer_record xfers[32];
    size_t xfer_count;
    const uint8_t *reads[8];
    size_t read_lens[8];
    size_t read_pos;
    unsigned sleeps[512];
    size_t sleep_count;
    int irq_level;
    int cancelled;
    size_t cancel_on_sleep_call;
    int64_t raise_irq_at_ns;
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
    assert(g_fake->xfer_count < 32);
    r = &g_fake->xfers[g_fake->xfer_count++];
    memset(r, 0, sizeof(*r));
    r->len = x->len;

    if (x->tx_buf != 0) {
        const uint8_t *src = (const uint8_t *)(uintptr_t)x->tx_buf;
        assert(x->rx_buf == 0);
        assert(x->len <= sizeof(r->data));
        r->is_write = 1;
        memcpy(r->data, src, x->len);
    } else {
        uint8_t *dst = (uint8_t *)(uintptr_t)x->rx_buf;
        assert(dst != NULL);
        assert(g_fake->read_pos < 8);
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

static int fake_irq_get(void *ctx)
{
    return ((struct fake_ctx *)ctx)->irq_level;
}

static int64_t fake_now_ns(void *ctx)
{
    return ((struct fake_ctx *)ctx)->now_ns;
}

static int fake_cancelled(void *ctx)
{
    return ((struct fake_ctx *)ctx)->cancelled;
}

static enum gxfp_io_result fake_sleep(void *ctx, unsigned ms)
{
    struct fake_ctx *f = ctx;
    assert(f->sleep_count < sizeof(f->sleeps) / sizeof(f->sleeps[0]));
    f->sleeps[f->sleep_count++] = ms;
    f->now_ns += (int64_t)ms * 1000000LL;
    if (f->raise_irq_at_ns > 0 && f->now_ns >= f->raise_irq_at_ns)
        f->irq_level = 1;
    if (f->cancel_on_sleep_call != 0 &&
        f->sleep_count == f->cancel_on_sleep_call)
        f->cancelled = 1;
    return GXFP_IO_OK;
}

static struct gxfp_linux_level_ops level_ops(struct fake_ctx *f)
{
    return (struct gxfp_linux_level_ops){
        .ctx = f,
        .get_value = fake_irq_get,
        .monotonic_now_ns = fake_now_ns,
        .is_cancelled = fake_cancelled,
    };
}

static void assert_write(const struct transfer_record *r,
                         const uint8_t *expected,
                         size_t expected_len)
{
    assert(r->is_write == 1);
    assert(r->len == expected_len);
    assert(memcmp(r->data, expected, expected_len) == 0);
}

static void test_full_attempt_uses_separate_windows_transactions(void)
{
    static const uint8_t ack_header[] = {0xa0, 0x06, 0x00, 0xa6};
    static const uint8_t ack_body[] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    static const uint8_t rsp_header[] = {0xa0, 0x07, 0x00, 0xa7};
    static const uint8_t rsp_body[] = {0xa8, 0x04, 0x00, 0x11, 0x22, 0x33, 0x98};
    static const uint8_t nop_outer[] = {0xa0, 0x08, 0x00, 0xa8};
    static const uint8_t nop_inner[] = {0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa5};
    static const uint8_t a4_outer[] = {0xa0, 0x06, 0x00, 0xa6};
    static const uint8_t a4_inner[] = {0xa8, 0x03, 0x00, 0x00, 0x00, 0xff};
    const struct gxfp_spi_ops spi_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {
        .reads = {ack_header, ack_body, rsp_header, rsp_body},
        .read_lens = {sizeof(ack_header), sizeof(ack_body), sizeof(rsp_header), sizeof(rsp_body)},
        .irq_level = 1,
    };
    struct gxfp_spi spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &spi_ops,
    };
    struct gxfp_linux_level_ops irq = level_ops(&f);
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;
    const uint8_t a4_payload[2] = {0x00, 0x00};
    const uint8_t *response;
    size_t response_len = 0;

    g_fake = &f;
    assert(gxfp_linux_active_backend_init(&active, &spi, &irq,
                                          fake_sleep, &f));
    assert(gxfp_linux_active_backend_attempt(&active, &attempt));
    assert(gxfp_get_evk_attempt(&attempt, a4_payload) == GXFP_ATTEMPT_OK);

    assert(f.sleep_count == 3);
    assert(f.sleeps[0] == 2);
    assert(f.sleeps[1] == 5);
    assert(f.sleeps[2] == 2);

    assert(f.xfer_count == 8);
    assert_write(&f.xfers[0], nop_outer, sizeof(nop_outer));
    assert_write(&f.xfers[1], nop_inner, sizeof(nop_inner));
    assert_write(&f.xfers[2], a4_outer, sizeof(a4_outer));
    assert_write(&f.xfers[3], a4_inner, sizeof(a4_inner));
    assert(f.xfers[4].is_write == 0 && f.xfers[4].len == 4);
    assert(f.xfers[5].is_write == 0 && f.xfers[5].len == 6);
    assert(f.xfers[6].is_write == 0 && f.xfers[6].len == 4);
    assert(f.xfers[7].is_write == 0 && f.xfers[7].len == 7);

    response = gxfp_linux_active_backend_response(&active, &response_len);
    assert(response != NULL);
    assert(response_len == 3);
    assert(memcmp(response, (const uint8_t[]){0x11, 0x22, 0x33}, 3) == 0);
}

static void test_low_irq_polling_is_bounded_and_never_reads_before_high(void)
{
    const struct gxfp_spi_ops spi_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {.irq_level = 0};
    struct gxfp_spi spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &spi_ops,
    };
    struct gxfp_linux_level_ops irq = level_ops(&f);
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;

    g_fake = &f;
    assert(gxfp_linux_active_backend_init(&active, &spi, &irq,
                                          fake_sleep, &f));
    assert(gxfp_linux_active_backend_attempt(&active, &attempt));
    assert(attempt.wait_ack(attempt.ctx, 0x0a, 0x04, 12) == GXFP_IO_TIMEOUT);
    assert(f.xfer_count == 0);
    assert(f.sleep_count == 3);
    assert(f.sleeps[0] == 5);
    assert(f.sleeps[1] == 5);
    assert(f.sleeps[2] == 2);
}

static void test_init_rejects_incomplete_or_wrong_speed_spi(void)
{
    const struct gxfp_spi_ops incomplete_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = NULL,
    };
    const struct gxfp_spi_ops complete_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {0};
    struct gxfp_linux_level_ops irq = level_ops(&f);
    struct gxfp_spi incomplete_spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &incomplete_ops,
    };
    struct gxfp_spi wrong_speed_spi = {
        .fd = 7,
        .max_speed_hz = 1000000u,
        .ops = &complete_ops,
    };
    struct gxfp_linux_active_backend active;

    assert(!gxfp_linux_active_backend_init(&active, &incomplete_spi, &irq,
                                           fake_sleep, &f));
    assert(!gxfp_linux_active_backend_init(&active, &wrong_speed_spi, &irq,
                                           fake_sleep, &f));
}

static void test_ack_timeout_retransmits_same_a4_once_then_succeeds(void)
{
    static const uint8_t ack_header[] = {0xa0, 0x06, 0x00, 0xa6};
    static const uint8_t ack_body[] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    static const uint8_t rsp_header[] = {0xa0, 0x07, 0x00, 0xa7};
    static const uint8_t rsp_body[] = {0xa8, 0x04, 0x00, 0x44, 0x55, 0x66, 0xff};
    static const uint8_t a4_outer[] = {0xa0, 0x06, 0x00, 0xa6};
    static const uint8_t a4_inner[] = {0xa8, 0x03, 0x00, 0x00, 0x00, 0xff};
    const struct gxfp_spi_ops spi_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {
        .reads = {ack_header, ack_body, rsp_header, rsp_body},
        .read_lens = {sizeof(ack_header), sizeof(ack_body), sizeof(rsp_header), sizeof(rsp_body)},
        .irq_level = 0,
        .raise_irq_at_ns = 1010000000LL,
    };
    struct gxfp_spi spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &spi_ops,
    };
    struct gxfp_linux_level_ops irq = level_ops(&f);
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;
    const uint8_t payload[2] = {0, 0};

    g_fake = &f;
    assert(gxfp_linux_active_backend_init(&active, &spi, &irq,
                                          fake_sleep, &f));
    assert(gxfp_linux_active_backend_attempt(&active, &attempt));
    assert(gxfp_get_evk_attempt(&attempt, payload) == GXFP_ATTEMPT_OK);

    assert(f.xfer_count == 10);
    assert_write(&f.xfers[2], a4_outer, sizeof(a4_outer));
    assert_write(&f.xfers[3], a4_inner, sizeof(a4_inner));
    assert_write(&f.xfers[4], a4_outer, sizeof(a4_outer));
    assert_write(&f.xfers[5], a4_inner, sizeof(a4_inner));
}

static void test_cancel_between_outer_and_inner_stops_before_second_write(void)
{
    const struct gxfp_spi_ops spi_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {
        .irq_level = 1,
        .cancel_on_sleep_call = 1,
    };
    struct gxfp_spi spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &spi_ops,
    };
    struct gxfp_linux_level_ops irq = level_ops(&f);
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;

    g_fake = &f;
    assert(gxfp_linux_active_backend_init(&active, &spi, &irq,
                                          fake_sleep, &f));
    assert(gxfp_linux_active_backend_attempt(&active, &attempt));
    assert(attempt.send_nop(attempt.ctx) == GXFP_IO_CANCELLED);
    assert(f.xfer_count == 1);
    assert(f.xfers[0].is_write == 1);
    assert(f.xfers[0].len == 4);
}

static void test_ff_header_is_terminal_and_never_reads_a_body(void)
{
    static const uint8_t ff_header[] = {0xff, 0xff, 0xff, 0xff};
    const struct gxfp_spi_ops spi_ops = {
        .open_fn = dummy_open,
        .close_fn = dummy_close,
        .ioctl_fn = fake_ioctl,
    };
    struct fake_ctx f = {
        .reads = {ff_header},
        .read_lens = {sizeof(ff_header)},
        .irq_level = 1,
    };
    struct gxfp_spi spi = {
        .fd = 7,
        .max_speed_hz = GXFP_SPI_MAX_SPEED_HZ,
        .ops = &spi_ops,
    };
    struct gxfp_linux_level_ops irq = level_ops(&f);
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;
    const uint8_t payload[2] = {0, 0};

    g_fake = &f;
    assert(gxfp_linux_active_backend_init(&active, &spi, &irq,
                                          fake_sleep, &f));
    assert(gxfp_linux_active_backend_attempt(&active, &attempt));
    assert(gxfp_get_evk_attempt(&attempt, payload) == GXFP_ATTEMPT_IO_ERROR);
    assert(f.read_pos == 1);
    assert(f.xfer_count == 5);
    assert(active.rx.terminal);
    assert(active.rx.stop_reason == GXFP_EVK_RX_STOP_FF_HEADER);
}

int main(void)
{
    test_full_attempt_uses_separate_windows_transactions();
    test_low_irq_polling_is_bounded_and_never_reads_before_high();
    test_init_rejects_incomplete_or_wrong_speed_spi();
    test_ack_timeout_retransmits_same_a4_once_then_succeeds();
    test_cancel_between_outer_and_inner_stops_before_second_write();
    test_ff_header_is_terminal_and_never_reads_a_body();
    puts("test_linux_active_backend: OK");
    return 0;
}
