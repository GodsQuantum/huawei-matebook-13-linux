#include "milan_rx_drain.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct scripted_read {
    uint8_t data[80];
    size_t len;
};

struct fake_io {
    int irq_level;
    enum gxfp_io_result wait_result;
    unsigned last_wait_timeout;
    unsigned wait_calls;
    uint64_t now_ms;
    int cancelled;
    struct scripted_read reads[16];
    size_t read_count;
    size_t read_pos;
    size_t irq_low_after_read_pos;
    enum gxfp_io_result forced_read_result;
    unsigned read_calls;
};

static int fake_get_irq_level(void *ctx)
{
    return ((struct fake_io *)ctx)->irq_level;
}

static enum gxfp_io_result fake_wait_irq_high(void *ctx, unsigned timeout_ms)
{
    struct fake_io *f = ctx;
    f->wait_calls++;
    f->last_wait_timeout = timeout_ms;
    if (f->wait_result == GXFP_IO_OK)
        f->irq_level = 1;
    else if (f->wait_result == GXFP_IO_TIMEOUT)
        f->now_ms += timeout_ms;
    return f->wait_result;
}

static enum gxfp_io_result fake_read_exact(void *ctx, uint8_t *buf, size_t len)
{
    struct fake_io *f = ctx;
    const struct scripted_read *r;

    f->read_calls++;
    if (f->forced_read_result != GXFP_IO_OK)
        return f->forced_read_result;
    if (f->read_pos >= f->read_count)
        return GXFP_IO_ERROR;
    r = &f->reads[f->read_pos++];
    if (r->len != len)
        return GXFP_IO_ERROR;
    memcpy(buf, r->data, len);
    if (f->irq_low_after_read_pos != 0 &&
        f->read_pos == f->irq_low_after_read_pos)
        f->irq_level = 0;
    return GXFP_IO_OK;
}

static uint64_t fake_now_ms(void *ctx)
{
    return ((struct fake_io *)ctx)->now_ms;
}

static int fake_is_cancelled(void *ctx)
{
    return ((struct fake_io *)ctx)->cancelled;
}

static struct gxfp_evk_rx_adapter make_adapter(struct fake_io *f)
{
    struct gxfp_evk_rx_adapter adapter;
    const struct gxfp_evk_rx_io io = {
        .ctx = f,
        .get_irq_level = fake_get_irq_level,
        .wait_irq_high = fake_wait_irq_high,
        .read_exact = fake_read_exact,
        .monotonic_ms = fake_now_ms,
        .is_cancelled = fake_is_cancelled,
    };

    assert(gxfp_evk_rx_adapter_init(&adapter, &io));
    return adapter;
}

static void add_read(struct fake_io *f, const uint8_t *data, size_t len)
{
    struct scripted_read *r = &f->reads[f->read_count++];
    assert(len <= sizeof(r->data));
    memcpy(r->data, data, len);
    r->len = len;
}

static void add_frame(struct fake_io *f,
                      const uint8_t header[4],
                      const uint8_t *body,
                      size_t body_len)
{
    add_read(f, header, 4);
    add_read(f, body, body_len);
}

static void test_ack_then_response_can_share_one_irq_high_window(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t ack_header[4] = {0xa0, 0x06, 0x00, 0xa6};
    const uint8_t ack_body[6] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    const uint8_t rsp_header[4] = {0xa0, 0x07, 0x00, 0xa7};
    const uint8_t rsp_body[7] = {0xa8, 0x04, 0x00, 0x11, 0x22, 0x33, 0x98};
    size_t response_len = 0;
    const uint8_t *response;

    add_frame(&f, ack_header, ack_body, sizeof(ack_body));
    add_frame(&f, rsp_header, rsp_body, sizeof(rsp_body));
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_OK);
    assert(f.wait_calls == 0);
    assert(f.read_pos == 2);
    assert(adapter.ack_seen);

    assert(gxfp_evk_rx_wait_response(&adapter, 9, 1000) == GXFP_IO_OK);
    assert(f.wait_calls == 0);
    assert(f.read_pos == 4);
    response = gxfp_evk_rx_response(&adapter, &response_len);
    assert(response != NULL);
    assert(response_len == 3);
    assert(memcmp(response, (const uint8_t[]){0x11, 0x22, 0x33}, 3) == 0);
}

static void test_response_before_ack_is_cached_without_extra_read(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t rsp_header[4] = {0xa0, 0x07, 0x00, 0xa7};
    const uint8_t rsp_body[7] = {0xa8, 0x04, 0x00, 0x44, 0x55, 0x66, 0xff};
    const uint8_t ack_header[4] = {0xa0, 0x06, 0x00, 0xa6};
    const uint8_t ack_body[6] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    size_t before_response_wait;

    add_frame(&f, rsp_header, rsp_body, sizeof(rsp_body));
    add_frame(&f, ack_header, ack_body, sizeof(ack_body));
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_OK);
    assert(adapter.response_seen);
    assert(adapter.ack_seen);
    before_response_wait = f.read_pos;

    assert(gxfp_evk_rx_wait_response(&adapter, 9, 1000) == GXFP_IO_OK);
    assert(f.read_pos == before_response_wait);
}

static void test_ff_header_is_terminal_and_forbids_any_second_read(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t ff[4] = {0xff, 0xff, 0xff, 0xff};
    size_t reads_after_first;

    add_read(&f, ff, sizeof(ff));
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_ERROR);
    assert(adapter.terminal);
    assert(adapter.stop_reason == GXFP_EVK_RX_STOP_FF_HEADER);
    reads_after_first = f.read_pos;
    assert(reads_after_first == 1);

    assert(gxfp_evk_rx_wait_response(&adapter, 9, 1000) == GXFP_IO_ERROR);
    assert(f.read_pos == reads_after_first);
}

static void test_low_irq_wait_timeout_performs_no_spi_read(void)
{
    struct fake_io f = { .irq_level = 0, .wait_result = GXFP_IO_TIMEOUT };
    struct gxfp_evk_rx_adapter adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_TIMEOUT);
    assert(f.wait_calls == 1);
    assert(f.last_wait_timeout == 1000);
    assert(f.read_pos == 0);
}


static void test_zero_timeout_never_starts_a_read(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 0) == GXFP_IO_TIMEOUT);
    assert(f.read_calls == 0);
    assert(!adapter.terminal);
}

static void test_oversize_outer_body_stops_before_body_read(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t header[4] = {0xa0, 0x45, 0x00, 0xe5}; /* 69-byte body */

    add_read(&f, header, sizeof(header));
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_ERROR);
    assert(adapter.terminal);
    assert(adapter.stop_reason == GXFP_EVK_RX_STOP_OVERSIZE);
    assert(f.read_pos == 1);
}



static void test_each_ack_wait_starts_a_fresh_send_generation(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t ack_header[4] = {0xa0, 0x06, 0x00, 0xa6};
    const uint8_t ack_body[6] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    size_t reads_after_first;

    add_frame(&f, ack_header, ack_body, sizeof(ack_body));
    add_frame(&f, ack_header, ack_body, sizeof(ack_body));
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_OK);
    reads_after_first = f.read_pos;
    assert(reads_after_first == 2);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_OK);
    assert(f.read_pos == 4);
}

static void test_new_ack_wait_discards_response_cached_before_previous_timeout(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_TIMEOUT };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t old_rsp_header[4] = {0xa0, 0x07, 0x00, 0xa7};
    const uint8_t old_rsp_body[7] = {0xa8, 0x04, 0x00, 0x01, 0x02, 0x03, 0xf8};
    const uint8_t ack_header[4] = {0xa0, 0x06, 0x00, 0xa6};
    const uint8_t ack_body[6] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    const uint8_t new_rsp_header[4] = {0xa0, 0x07, 0x00, 0xa7};
    const uint8_t new_rsp_body[7] = {0xa8, 0x04, 0x00, 0x10, 0x20, 0x30, 0x9e};
    size_t response_len;
    const uint8_t *response;

    add_frame(&f, old_rsp_header, old_rsp_body, sizeof(old_rsp_body));
    add_frame(&f, ack_header, ack_body, sizeof(ack_body));
    add_frame(&f, new_rsp_header, new_rsp_body, sizeof(new_rsp_body));
    f.irq_low_after_read_pos = 2; /* after old response frame */
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_TIMEOUT);
    assert(adapter.response_seen);

    f.irq_low_after_read_pos = 0;
    f.irq_level = 1;
    f.wait_result = GXFP_IO_OK;

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_OK);
    assert(!adapter.response_seen);
    assert(gxfp_evk_rx_wait_response(&adapter, 9, 1000) == GXFP_IO_OK);
    response = gxfp_evk_rx_response(&adapter, &response_len);
    assert(response != NULL);
    assert(response_len == 3);
    assert(memcmp(response, (const uint8_t[]){0x10, 0x20, 0x30}, 3) == 0);
}

static void test_header_read_error_is_terminal_and_not_retried(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter = make_adapter(&f);
    size_t reads_after_first;

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_ERROR);
    assert(adapter.terminal);
    assert(adapter.stop_reason == GXFP_EVK_RX_STOP_IO_ERROR);
    reads_after_first = f.read_pos;

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_ERROR);
    assert(f.read_pos == reads_after_first);
}


static void test_cancelled_exact_read_latches_terminal_before_future_io(void)
{
    struct fake_io f = {
        .irq_level = 1,
        .wait_result = GXFP_IO_OK,
        .forced_read_result = GXFP_IO_CANCELLED,
    };
    struct gxfp_evk_rx_adapter adapter = make_adapter(&f);
    unsigned calls_after_cancel;

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_CANCELLED);
    assert(adapter.terminal);
    assert(adapter.stop_reason == GXFP_EVK_RX_STOP_IO_ERROR);
    calls_after_cancel = f.read_calls;

    f.forced_read_result = GXFP_IO_OK;
    assert(gxfp_evk_rx_wait_response(&adapter, 9, 1000) == GXFP_IO_ERROR);
    assert(f.read_calls == calls_after_cancel);
}

static void test_cancellation_happens_before_any_read(void)
{
    struct fake_io f = {
        .irq_level = 1,
        .wait_result = GXFP_IO_OK,
        .cancelled = 1,
    };
    struct gxfp_evk_rx_adapter adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x0a, 0x04, 1000) == GXFP_IO_CANCELLED);
    assert(f.read_pos == 0);
}


struct attempt_fake {
    struct fake_io io;
    struct gxfp_evk_rx_adapter rx;
    unsigned nop_sends;
    unsigned sleeps;
    unsigned a4_sends;
};

static enum gxfp_io_result attempt_send_nop(void *ctx)
{
    struct attempt_fake *f = ctx;
    f->nop_sends++;
    return GXFP_IO_OK;
}

static enum gxfp_io_result attempt_sleep_ms(void *ctx, unsigned ms)
{
    struct attempt_fake *f = ctx;
    assert(ms == 5);
    f->sleeps++;
    return GXFP_IO_OK;
}

static enum gxfp_io_result attempt_send_a4(void *ctx, const uint8_t payload[2])
{
    struct attempt_fake *f = ctx;
    assert(payload[0] == 0x00);
    assert(payload[1] == 0x00);
    f->a4_sends++;
    if (f->a4_sends == 2) {
        f->io.irq_level = 1;
        f->io.wait_result = GXFP_IO_OK;
    }
    return GXFP_IO_OK;
}

static enum gxfp_io_result attempt_wait_ack(void *ctx,
                                             uint8_t cmd0,
                                             uint8_t cmd1,
                                             unsigned timeout_ms)
{
    return gxfp_evk_rx_wait_ack(&((struct attempt_fake *)ctx)->rx,
                                cmd0,
                                cmd1,
                                timeout_ms);
}

static enum gxfp_io_result attempt_wait_response(void *ctx,
                                                  uint8_t event_index,
                                                  unsigned timeout_ms)
{
    return gxfp_evk_rx_wait_response(&((struct attempt_fake *)ctx)->rx,
                                     event_index,
                                     timeout_ms);
}

static void init_attempt_fake(struct attempt_fake *f)
{
    const struct gxfp_evk_rx_io io = {
        .ctx = &f->io,
        .get_irq_level = fake_get_irq_level,
        .wait_irq_high = fake_wait_irq_high,
        .read_exact = fake_read_exact,
        .monotonic_ms = fake_now_ms,
        .is_cancelled = fake_is_cancelled,
    };

    assert(gxfp_evk_rx_adapter_init(&f->rx, &io));
}

static void test_full_attempt_retransmits_once_then_uses_separate_response_phase(void)
{
    struct attempt_fake f;
    struct gxfp_attempt_backend backend;
    const uint8_t payload[2] = {0x00, 0x00};
    const uint8_t ack_header[4] = {0xa0, 0x06, 0x00, 0xa6};
    const uint8_t ack_body[6] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    const uint8_t rsp_header[4] = {0xa0, 0x07, 0x00, 0xa7};
    const uint8_t rsp_body[7] = {0xa8, 0x04, 0x00, 0xde, 0xad, 0xbe, 0xb5};

    memset(&f, 0, sizeof(f));
    f.io.irq_level = 0;
    f.io.wait_result = GXFP_IO_TIMEOUT;
    add_frame(&f.io, ack_header, ack_body, sizeof(ack_body));
    add_frame(&f.io, rsp_header, rsp_body, sizeof(rsp_body));
    init_attempt_fake(&f);

    backend = (struct gxfp_attempt_backend){
        .ctx = &f,
        .send_nop = attempt_send_nop,
        .sleep_ms = attempt_sleep_ms,
        .send_a4 = attempt_send_a4,
        .wait_ack = attempt_wait_ack,
        .wait_response = attempt_wait_response,
    };

    assert(gxfp_get_evk_attempt(&backend, payload) == GXFP_ATTEMPT_OK);
    assert(f.nop_sends == 1);
    assert(f.sleeps == 1);
    assert(f.a4_sends == 2);
    assert(f.io.wait_calls == 1);
    assert(f.io.last_wait_timeout == 1000);
    assert(f.rx.ack_seen);
    assert(f.rx.response_seen);
}

static void test_generic_ack_wait_ignores_unrelated_ack_and_matches_driverstate(void)
{
    struct fake_io f = { .irq_level = 1, .wait_result = GXFP_IO_OK };
    struct gxfp_evk_rx_adapter adapter;
    const uint8_t header[4] = {0xa0, 0x06, 0x00, 0xa6};
    const uint8_t a4_ack[6] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    const uint8_t driver_ack[6] = {0xb0, 0x03, 0x00, 0x96, 0x00, 0x61};

    add_frame(&f, header, a4_ack, sizeof(a4_ack));
    add_frame(&f, header, driver_ack, sizeof(driver_ack));
    adapter = make_adapter(&f);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x09, 0x03, 1000) == GXFP_IO_OK);
    assert(f.read_pos == 4);
    assert(adapter.ack_seen);
    assert(adapter.ack_status == 0);

    assert(gxfp_evk_rx_wait_ack(&adapter, 0x10, 0x00, 1000) == GXFP_IO_ERROR);
    assert(gxfp_evk_rx_wait_ack(&adapter, 0x00, 0x08, 1000) == GXFP_IO_ERROR);
}

int main(void)
{
    test_ack_then_response_can_share_one_irq_high_window();
    test_generic_ack_wait_ignores_unrelated_ack_and_matches_driverstate();
    test_response_before_ack_is_cached_without_extra_read();
    test_ff_header_is_terminal_and_forbids_any_second_read();
    test_low_irq_wait_timeout_performs_no_spi_read();
    test_zero_timeout_never_starts_a_read();
    test_oversize_outer_body_stops_before_body_read();
    test_each_ack_wait_starts_a_fresh_send_generation();
    test_new_ack_wait_discards_response_cached_before_previous_timeout();
    test_header_read_error_is_terminal_and_not_retried();
    test_cancelled_exact_read_latches_terminal_before_future_io();
    test_cancellation_happens_before_any_read();
    test_full_attempt_retransmits_once_then_uses_separate_response_phase();
    puts("test_milan_rx_drain: OK");
    return 0;
}
