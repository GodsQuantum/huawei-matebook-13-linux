#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../probe_harness.h"

enum event_kind {
    EV_RESET_HIGH,
    EV_RESET_LOW,
    EV_RESET_SLEEP,
    EV_PRE_NOP,
    EV_PRE_INSTALL,
    EV_PRE_SLEEP,
    EV_EVK_NOP,
    EV_EVK_SLEEP,
    EV_EVK_A4,
    EV_EVK_WAIT_ACK,
    EV_EVK_WAIT_RESPONSE,
};

struct event {
    enum event_kind kind;
    unsigned value;
};

struct fake {
    struct event events[64];
    size_t count;
    enum gxfp_io_result reset_set_results[8];
    size_t reset_set_pos;
    enum gxfp_io_result reset_sleep_results[8];
    size_t reset_sleep_pos;
    enum gxfp_io_result pre_nop_result;
    enum gxfp_io_result pre_install_results[2];
    size_t pre_install_pos;
    enum gxfp_io_result pre_sleep_result;
    enum gxfp_io_result evk_ack_results[2];
    size_t evk_ack_pos;
    enum gxfp_io_result evk_response_result;
};

static void record(struct fake *f, enum event_kind kind, unsigned value)
{
    assert(f->count < sizeof(f->events) / sizeof(f->events[0]));
    f->events[f->count++] = (struct event){ .kind = kind, .value = value };
}

static enum gxfp_io_result reset_set(void *ctx, int level)
{
    struct fake *f = ctx;
    enum gxfp_io_result r = GXFP_IO_OK;
    record(f, level ? EV_RESET_HIGH : EV_RESET_LOW, 0);
    if (f->reset_set_pos < sizeof(f->reset_set_results) / sizeof(f->reset_set_results[0]))
        r = f->reset_set_results[f->reset_set_pos];
    f->reset_set_pos++;
    return r;
}

static enum gxfp_io_result reset_sleep(void *ctx, unsigned ms)
{
    struct fake *f = ctx;
    enum gxfp_io_result r = GXFP_IO_OK;
    record(f, EV_RESET_SLEEP, ms);
    if (f->reset_sleep_pos < sizeof(f->reset_sleep_results) / sizeof(f->reset_sleep_results[0]))
        r = f->reset_sleep_results[f->reset_sleep_pos];
    f->reset_sleep_pos++;
    return r;
}

static enum gxfp_io_result pre_nop(void *ctx)
{
    struct fake *f = ctx;
    record(f, EV_PRE_NOP, 0);
    return f->pre_nop_result;
}

static enum gxfp_io_result pre_install(void *ctx)
{
    struct fake *f = ctx;
    enum gxfp_io_result r = GXFP_IO_OK;
    record(f, EV_PRE_INSTALL, 0);
    if (f->pre_install_pos < 2)
        r = f->pre_install_results[f->pre_install_pos];
    f->pre_install_pos++;
    return r;
}

static enum gxfp_io_result pre_sleep(void *ctx, unsigned ms)
{
    struct fake *f = ctx;
    record(f, EV_PRE_SLEEP, ms);
    return f->pre_sleep_result;
}

static enum gxfp_io_result evk_nop(void *ctx)
{
    struct fake *f = ctx;
    record(f, EV_EVK_NOP, 0);
    return GXFP_IO_OK;
}

static enum gxfp_io_result evk_sleep(void *ctx, unsigned ms)
{
    struct fake *f = ctx;
    record(f, EV_EVK_SLEEP, ms);
    return GXFP_IO_OK;
}

static enum gxfp_io_result evk_a4(void *ctx, const uint8_t payload[2])
{
    struct fake *f = ctx;
    assert(payload[0] == 0x00 && payload[1] == 0x00);
    record(f, EV_EVK_A4, ((unsigned)payload[0] << 8) | payload[1]);
    return GXFP_IO_OK;
}

static enum gxfp_io_result evk_wait_ack(void *ctx,
                                         uint8_t cmd0,
                                         uint8_t cmd1,
                                         unsigned timeout_ms)
{
    struct fake *f = ctx;
    enum gxfp_io_result r = GXFP_IO_TIMEOUT;
    assert(cmd0 == 0x0a && cmd1 == 0x04 && timeout_ms == 1000);
    record(f, EV_EVK_WAIT_ACK, timeout_ms);
    if (f->evk_ack_pos < 2)
        r = f->evk_ack_results[f->evk_ack_pos];
    f->evk_ack_pos++;
    return r;
}

static enum gxfp_io_result evk_wait_response(void *ctx,
                                              uint8_t event_index,
                                              unsigned timeout_ms)
{
    struct fake *f = ctx;
    assert(event_index == 9 && timeout_ms == 1000);
    record(f, EV_EVK_WAIT_RESPONSE, timeout_ms);
    return f->evk_response_result;
}

static void make_ops(struct fake *f,
                     struct gxfp_probe_reset_ops *reset,
                     struct gxfp_probe_preamble_ops *pre,
                     struct gxfp_attempt_backend *attempt)
{
    *reset = (struct gxfp_probe_reset_ops){
        .ctx = f,
        .set_level = reset_set,
        .sleep_ms = reset_sleep,
    };
    *pre = (struct gxfp_probe_preamble_ops){
        .ctx = f,
        .send_nop = pre_nop,
        .send_driver_install = pre_install,
        .sleep_ms = pre_sleep,
    };
    *attempt = (struct gxfp_attempt_backend){
        .ctx = f,
        .send_nop = evk_nop,
        .sleep_ms = evk_sleep,
        .send_a4 = evk_a4,
        .wait_ack = evk_wait_ack,
        .wait_response = evk_wait_response,
    };
}

static void assert_reset_at(const struct fake *f, size_t i)
{
    assert(f->events[i + 0].kind == EV_RESET_HIGH);
    assert(f->events[i + 1].kind == EV_RESET_SLEEP && f->events[i + 1].value == 10);
    assert(f->events[i + 2].kind == EV_RESET_LOW);
    assert(f->events[i + 3].kind == EV_RESET_SLEEP && f->events[i + 3].value == 100);
}

static void test_success_preserves_fixed_preamble_and_always_cleans_up(void)
{
    struct fake f = {
        .pre_nop_result = GXFP_IO_OK,
        .pre_install_results = {GXFP_IO_OK, GXFP_IO_OK},
        .pre_sleep_result = GXFP_IO_OK,
        .evk_ack_results = {GXFP_IO_OK},
        .evk_response_result = GXFP_IO_OK,
    };
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;
    struct gxfp_probe_report report;
    const uint8_t payload[2] = {0, 0};

    make_ops(&f, &reset, &pre, &attempt);
    assert(gxfp_probe_run(&reset, &pre, &attempt, payload, &report) == GXFP_PROBE_OK);
    assert(report.primary_result == GXFP_PROBE_OK);
    assert(report.evk_result == GXFP_ATTEMPT_OK);
    assert(report.cleanup_result == GXFP_IO_OK);

    assert_reset_at(&f, 0);
    assert(f.events[4].kind == EV_PRE_NOP);
    assert(f.events[5].kind == EV_PRE_SLEEP && f.events[5].value == 5);
    assert(f.events[6].kind == EV_PRE_INSTALL);
    assert(f.events[7].kind == EV_PRE_SLEEP && f.events[7].value == 100);
    assert(f.events[8].kind == EV_PRE_INSTALL);
    assert(f.events[9].kind == EV_PRE_SLEEP && f.events[9].value == 100);
    assert(f.events[10].kind == EV_EVK_NOP);
    assert(f.events[11].kind == EV_EVK_SLEEP && f.events[11].value == 5);
    assert(f.events[12].kind == EV_EVK_A4);
    assert(f.events[13].kind == EV_EVK_WAIT_ACK);
    assert(f.events[14].kind == EV_EVK_WAIT_RESPONSE);
    assert_reset_at(&f, 15);
    assert(f.count == 19);
}

static void test_ack_timeout_retransmits_a4_once_then_cleanup(void)
{
    struct fake f = {
        .pre_nop_result = GXFP_IO_OK,
        .pre_install_results = {GXFP_IO_OK, GXFP_IO_OK},
        .pre_sleep_result = GXFP_IO_OK,
        .evk_ack_results = {GXFP_IO_TIMEOUT, GXFP_IO_TIMEOUT},
        .evk_response_result = GXFP_IO_OK,
    };
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;
    struct gxfp_probe_report report;
    const uint8_t payload[2] = {0, 0};
    size_t i;
    unsigned a4_count = 0;

    make_ops(&f, &reset, &pre, &attempt);
    assert(gxfp_probe_run(&reset, &pre, &attempt, payload, &report) == GXFP_PROBE_ACK_TIMEOUT);
    assert(report.evk_result == GXFP_ATTEMPT_ACK_TIMEOUT);
    assert(report.cleanup_result == GXFP_IO_OK);
    for (i = 0; i < f.count; i++)
        if (f.events[i].kind == EV_EVK_A4)
            a4_count++;
    assert(a4_count == 2);
    assert_reset_at(&f, f.count - 4);
}

static void test_preamble_failure_never_enters_evk_but_cleanup_runs(void)
{
    struct fake f = {
        .pre_nop_result = GXFP_IO_OK,
        .pre_install_results = {GXFP_IO_ERROR, GXFP_IO_OK},
        .pre_sleep_result = GXFP_IO_OK,
    };
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;
    struct gxfp_probe_report report;
    const uint8_t payload[2] = {0, 0};
    size_t i;

    make_ops(&f, &reset, &pre, &attempt);
    assert(gxfp_probe_run(&reset, &pre, &attempt, payload, &report) == GXFP_PROBE_PREAMBLE_ERROR);
    for (i = 0; i < f.count; i++)
        assert(f.events[i].kind != EV_EVK_A4);
    assert_reset_at(&f, f.count - 4);
}

static void test_cancelled_evk_still_runs_cleanup(void)
{
    struct fake f = {
        .pre_nop_result = GXFP_IO_OK,
        .pre_install_results = {GXFP_IO_OK, GXFP_IO_OK},
        .pre_sleep_result = GXFP_IO_OK,
        .evk_ack_results = {GXFP_IO_CANCELLED},
    };
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;
    struct gxfp_probe_report report;
    const uint8_t payload[2] = {0, 0};

    make_ops(&f, &reset, &pre, &attempt);
    assert(gxfp_probe_run(&reset, &pre, &attempt, payload, &report) == GXFP_PROBE_CANCELLED);
    assert(report.evk_result == GXFP_ATTEMPT_CANCELLED);
    assert_reset_at(&f, f.count - 4);
}

static void test_cleanup_failure_is_distinct_and_preserves_primary_result(void)
{
    struct fake f = {
        .pre_nop_result = GXFP_IO_OK,
        .pre_install_results = {GXFP_IO_OK, GXFP_IO_OK},
        .pre_sleep_result = GXFP_IO_OK,
        .evk_ack_results = {GXFP_IO_OK},
        .evk_response_result = GXFP_IO_OK,
    };
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;
    struct gxfp_probe_report report;
    const uint8_t payload[2] = {0, 0};

    /* First reset uses set calls 0,1; cleanup HIGH is set call 2. */
    f.reset_set_results[2] = GXFP_IO_ERROR;
    make_ops(&f, &reset, &pre, &attempt);
    assert(gxfp_probe_run(&reset, &pre, &attempt, payload, &report) == GXFP_PROBE_CLEANUP_ERROR);
    assert(report.primary_result == GXFP_PROBE_OK);
    assert(report.cleanup_result == GXFP_IO_ERROR);
}


static void test_public_restore_sequence_is_high10_low100(void)
{
    struct fake f = {0};
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;

    make_ops(&f, &reset, &pre, &attempt);
    assert(gxfp_probe_restore_reset(&reset) == GXFP_IO_OK);
    assert(f.count == 4);
    assert_reset_at(&f, 0);
}

int main(void)
{
    test_public_restore_sequence_is_high10_low100();
    test_success_preserves_fixed_preamble_and_always_cleans_up();
    test_ack_timeout_retransmits_a4_once_then_cleanup();
    test_preamble_failure_never_enters_evk_but_cleanup_runs();
    test_cancelled_evk_still_runs_cleanup();
    test_cleanup_failure_is_distinct_and_preserves_primary_result();
    puts("test_probe_harness: OK");
    return 0;
}
