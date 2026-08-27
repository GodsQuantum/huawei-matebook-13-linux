#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "../probe_harness.h"

enum event_kind {
    EV_RESET_HIGH,
    EV_RESET_LOW,
    EV_RESET_SLEEP,
    EV_PRE_NOP,
    EV_PRE_SLEEP,
    EV_PRE_INSTALL,
    EV_PRE_WAIT_ACK,
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
    struct event events[96];
    size_t count;
    enum gxfp_io_result reset_set_results[16];
    size_t reset_set_pos;
    enum gxfp_io_result reset_sleep_results[16];
    size_t reset_sleep_pos;
    enum gxfp_io_result pre_nop_result;
    enum gxfp_io_result pre_sleep_result;
    enum gxfp_io_result pre_install_results[4];
    size_t pre_install_pos;
    enum gxfp_io_result driver_ack_results[4];
    size_t driver_ack_pos;
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

static enum gxfp_io_result pre_sleep(void *ctx, unsigned ms)
{
    struct fake *f = ctx;
    record(f, EV_PRE_SLEEP, ms);
    return f->pre_sleep_result;
}

static enum gxfp_io_result pre_install(void *ctx)
{
    struct fake *f = ctx;
    enum gxfp_io_result r = GXFP_IO_OK;

    record(f, EV_PRE_INSTALL, 0);
    if (f->pre_install_pos < 4)
        r = f->pre_install_results[f->pre_install_pos];
    f->pre_install_pos++;
    return r;
}

static enum gxfp_io_result pre_wait_ack(void *ctx,
                                        uint8_t cmd0,
                                        uint8_t cmd1,
                                        unsigned timeout_ms)
{
    struct fake *f = ctx;
    enum gxfp_io_result r = GXFP_IO_TIMEOUT;

    assert(cmd0 == 0x09 && cmd1 == 0x03 && timeout_ms == 1000);
    record(f, EV_PRE_WAIT_ACK, timeout_ms);
    if (f->driver_ack_pos < 4)
        r = f->driver_ack_results[f->driver_ack_pos];
    f->driver_ack_pos++;
    return r;
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
    record(f, EV_EVK_A4, 0);
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
        .wait_ack = pre_wait_ack,
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

static unsigned count_event(const struct fake *f, enum event_kind kind)
{
    size_t i;
    unsigned n = 0;
    for (i = 0; i < f->count; i++)
        if (f->events[i].kind == kind)
            n++;
    return n;
}

static struct fake success_fake(void)
{
    struct fake f = {
        .pre_nop_result = GXFP_IO_OK,
        .pre_sleep_result = GXFP_IO_OK,
        .driver_ack_results = {GXFP_IO_OK},
        .evk_ack_results = {GXFP_IO_OK},
        .evk_response_result = GXFP_IO_OK,
    };
    return f;
}

static enum gxfp_probe_result run(struct fake *f, struct gxfp_probe_report *report)
{
    struct gxfp_probe_reset_ops reset;
    struct gxfp_probe_preamble_ops pre;
    struct gxfp_attempt_backend attempt;
    const uint8_t payload[2] = {0, 0};

    make_ops(f, &reset, &pre, &attempt);
    return gxfp_probe_run(&reset, &pre, &attempt, payload, report);
}

static void test_driverstate_first_install_ack_skips_intermediate_reset(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    assert(run(&f, &report) == GXFP_PROBE_OK);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_OK);
    assert(!report.driver_state_reset_performed);
    assert(report.evk_result == GXFP_ATTEMPT_OK);
    assert(report.cleanup_result == GXFP_IO_OK);
    assert(count_event(&f, EV_PRE_INSTALL) == 1);
    assert(count_event(&f, EV_PRE_WAIT_ACK) == 1);
    assert(count_event(&f, EV_RESET_HIGH) == 2); /* initial + cleanup */
    assert_reset_at(&f, 0);
    assert_reset_at(&f, f.count - 4);
}

static void test_driverstate_internal_retransmit_succeeds_on_second_send(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    f.driver_ack_results[0] = GXFP_IO_TIMEOUT;
    f.driver_ack_results[1] = GXFP_IO_OK;
    assert(run(&f, &report) == GXFP_PROBE_OK);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_OK);
    assert(!report.driver_state_reset_performed);
    assert(count_event(&f, EV_PRE_INSTALL) == 2);
    assert(count_event(&f, EV_PRE_WAIT_ACK) == 2);
}

static void test_driverstate_second_wrapper_can_succeed_without_reset(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    f.driver_ack_results[0] = GXFP_IO_TIMEOUT;
    f.driver_ack_results[1] = GXFP_IO_TIMEOUT;
    f.driver_ack_results[2] = GXFP_IO_OK;
    assert(run(&f, &report) == GXFP_PROBE_OK);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_OK);
    assert(!report.driver_state_reset_performed);
    assert(count_event(&f, EV_PRE_INSTALL) == 3);
    assert(count_event(&f, EV_PRE_WAIT_ACK) == 3);
}

static void test_four_driverstate_ack_timeouts_trigger_one_intermediate_reset_then_evk(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;
    size_t i;
    size_t evk_nop_pos = 0;

    for (i = 0; i < 4; i++)
        f.driver_ack_results[i] = GXFP_IO_TIMEOUT;

    assert(run(&f, &report) == GXFP_PROBE_OK);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_ACK_TIMEOUT);
    assert(report.driver_state_reset_performed);
    assert(count_event(&f, EV_PRE_INSTALL) == 4);
    assert(count_event(&f, EV_PRE_WAIT_ACK) == 4);
    assert(count_event(&f, EV_RESET_HIGH) == 3); /* initial + DS fallback + cleanup */

    for (i = 0; i < f.count; i++)
        if (f.events[i].kind == EV_EVK_NOP) {
            evk_nop_pos = i;
            break;
        }
    assert(evk_nop_pos >= 4);
    assert_reset_at(&f, evk_nop_pos - 4);
}

static void test_driverstate_reset_failure_stops_before_evk_and_final_cleanup_still_runs(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;
    size_t i;

    for (i = 0; i < 4; i++)
        f.driver_ack_results[i] = GXFP_IO_TIMEOUT;
    /* Initial reset consumes set positions 0,1. DriverState fallback HIGH is #2. */
    f.reset_set_results[2] = GXFP_IO_ERROR;

    assert(run(&f, &report) == GXFP_PROBE_DRIVERSTATE_RESET_ERROR);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_ACK_TIMEOUT);
    assert(report.driver_state_reset_performed);
    assert(count_event(&f, EV_EVK_A4) == 0);
    assert_reset_at(&f, f.count - 4);
}

static void test_driverstate_cancel_stops_more_install_and_cleans_up(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    f.driver_ack_results[0] = GXFP_IO_CANCELLED;
    assert(run(&f, &report) == GXFP_PROBE_CANCELLED);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_CANCELLED);
    assert(count_event(&f, EV_PRE_INSTALL) == 1);
    assert(count_event(&f, EV_EVK_A4) == 0);
    assert_reset_at(&f, f.count - 4);
}

static void test_driverstate_install_write_error_stops_before_ack_and_cleans_up(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    f.pre_install_results[0] = GXFP_IO_ERROR;
    assert(run(&f, &report) == GXFP_PROBE_IO_ERROR);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_IO_ERROR);
    assert(count_event(&f, EV_PRE_INSTALL) == 1);
    assert(count_event(&f, EV_PRE_WAIT_ACK) == 0);
    assert(count_event(&f, EV_EVK_A4) == 0);
    assert_reset_at(&f, f.count - 4);
}

static void test_driverstate_io_error_stops_more_install_and_cleans_up(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    f.driver_ack_results[0] = GXFP_IO_ERROR;
    assert(run(&f, &report) == GXFP_PROBE_IO_ERROR);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_IO_ERROR);
    assert(count_event(&f, EV_PRE_INSTALL) == 1);
    assert(count_event(&f, EV_EVK_A4) == 0);
    assert_reset_at(&f, f.count - 4);
}

static void test_evk_ack_timeout_still_retransmits_a4_once_and_cleans_up(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    f.evk_ack_results[0] = GXFP_IO_TIMEOUT;
    f.evk_ack_results[1] = GXFP_IO_TIMEOUT;
    assert(run(&f, &report) == GXFP_PROBE_ACK_TIMEOUT);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_OK);
    assert(report.evk_result == GXFP_ATTEMPT_ACK_TIMEOUT);
    assert(count_event(&f, EV_EVK_A4) == 2);
    assert_reset_at(&f, f.count - 4);
}

static void test_cleanup_failure_is_distinct_and_preserves_primary(void)
{
    struct fake f = success_fake();
    struct gxfp_probe_report report;

    /* Initial reset set calls 0,1; cleanup HIGH is set call 2 when DS succeeds. */
    f.reset_set_results[2] = GXFP_IO_ERROR;
    assert(run(&f, &report) == GXFP_PROBE_CLEANUP_ERROR);
    assert(report.primary_result == GXFP_PROBE_OK);
    assert(report.driver_state_result == GXFP_DRIVER_STATE_OK);
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
    test_driverstate_first_install_ack_skips_intermediate_reset();
    test_driverstate_internal_retransmit_succeeds_on_second_send();
    test_driverstate_second_wrapper_can_succeed_without_reset();
    test_four_driverstate_ack_timeouts_trigger_one_intermediate_reset_then_evk();
    test_driverstate_reset_failure_stops_before_evk_and_final_cleanup_still_runs();
    test_driverstate_cancel_stops_more_install_and_cleans_up();
    test_driverstate_install_write_error_stops_before_ack_and_cleans_up();
    test_driverstate_io_error_stops_more_install_and_cleans_up();
    test_evk_ack_timeout_still_retransmits_a4_once_and_cleans_up();
    test_cleanup_failure_is_distinct_and_preserves_primary();
    puts("test_probe_harness: OK");
    return 0;
}
