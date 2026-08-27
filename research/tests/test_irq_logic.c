#include "linux/irq_logic.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct fake_irq {
    int values[8];
    int value_count;
    int value_index;
    int waits[8];
    int wait_count;
    int wait_index;
    int consume_calls;
    int64_t now_values[8];
    int now_count;
    int now_index;
    int cancelled;
};

static int fake_get_value(void *ctx)
{
    struct fake_irq *f = ctx;
    assert(f->value_index < f->value_count);
    return f->values[f->value_index++];
}

static int fake_wait_rising(void *ctx, int64_t timeout_ns)
{
    struct fake_irq *f = ctx;
    assert(timeout_ns > 0);
    assert(f->wait_index < f->wait_count);
    return f->waits[f->wait_index++];
}

static int fake_consume(void *ctx)
{
    struct fake_irq *f = ctx;
    f->consume_calls++;
    return 0;
}

static int64_t fake_now(void *ctx)
{
    struct fake_irq *f = ctx;
    assert(f->now_index < f->now_count);
    return f->now_values[f->now_index++];
}

static int fake_cancelled(void *ctx)
{
    return ((struct fake_irq *)ctx)->cancelled;
}

static struct gxfp_irq_ops ops_for(struct fake_irq *f)
{
    struct gxfp_irq_ops ops = {
        .ctx = f,
        .get_value = fake_get_value,
        .wait_rising = fake_wait_rising,
        .consume_event = fake_consume,
        .monotonic_now_ns = fake_now,
        .is_cancelled = fake_cancelled,
    };
    return ops;
}

static void test_already_high(void)
{
    struct fake_irq f = {.values = {1}, .value_count = 1};
    struct gxfp_irq_ops ops = ops_for(&f);
    assert(gxfp_irq_wait_high(&ops, 1000) == GXFP_IRQ_OK);
    assert(f.wait_index == 0);
    assert(f.consume_calls == 0);
}

static void test_low_then_rising_high(void)
{
    struct fake_irq f = {
        .values = {0, 1}, .value_count = 2,
        .waits = {1}, .wait_count = 1,
        .now_values = {100}, .now_count = 1,
    };
    struct gxfp_irq_ops ops = ops_for(&f);
    assert(gxfp_irq_wait_high(&ops, 1000) == GXFP_IRQ_OK);
    assert(f.consume_calls == 1);
}

static void test_spurious_event_loops(void)
{
    struct fake_irq f = {
        .values = {0, 0, 1}, .value_count = 3,
        .waits = {1, 1}, .wait_count = 2,
        .now_values = {100, 200}, .now_count = 2,
    };
    struct gxfp_irq_ops ops = ops_for(&f);
    assert(gxfp_irq_wait_high(&ops, 1000) == GXFP_IRQ_OK);
    assert(f.consume_calls == 2);
}

static void test_timeout(void)
{
    struct fake_irq f = {
        .values = {0}, .value_count = 1,
        .waits = {0}, .wait_count = 1,
        .now_values = {100}, .now_count = 1,
    };
    struct gxfp_irq_ops ops = ops_for(&f);
    assert(gxfp_irq_wait_high(&ops, 1000) == GXFP_IRQ_TIMEOUT);
    assert(f.consume_calls == 0);
}

static void test_cancelled(void)
{
    struct fake_irq f;
    memset(&f, 0, sizeof(f));
    f.cancelled = 1;
    struct gxfp_irq_ops ops = ops_for(&f);
    assert(gxfp_irq_wait_high(&ops, 1000) == GXFP_IRQ_CANCELLED);
    assert(f.value_index == 0);
}

static void test_wait_error(void)
{
    struct fake_irq f = {
        .values = {0}, .value_count = 1,
        .waits = {-1}, .wait_count = 1,
        .now_values = {100}, .now_count = 1,
    };
    struct gxfp_irq_ops ops = ops_for(&f);
    assert(gxfp_irq_wait_high(&ops, 1000) == GXFP_IRQ_IO_ERROR);
}

int main(void)
{
    test_already_high();
    test_low_then_rising_high();
    test_spurious_event_loops();
    test_timeout();
    test_cancelled();
    test_wait_error();
    puts("test_irq_logic: OK");
    return 0;
}
