#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../milan_attempt.h"

enum event_kind {
    EV_SEND_NOP,
    EV_SLEEP,
    EV_SEND_A4,
    EV_WAIT_ACK,
    EV_WAIT_RESPONSE,
};

struct event {
    enum event_kind kind;
    unsigned a;
    unsigned b;
    uint8_t payload[2];
};

struct fake {
    struct event events[32];
    size_t event_count;

    enum gxfp_io_result ack_results[2];
    size_t ack_count;
    size_t ack_pos;
    enum gxfp_io_result response_result;
};

static void record(struct fake *f, struct event e)
{
    if (f->event_count >= sizeof(f->events) / sizeof(f->events[0])) {
        fprintf(stderr, "event overflow\n");
        abort();
    }
    f->events[f->event_count++] = e;
}

static enum gxfp_io_result fake_send_nop(void *ctx)
{
    struct fake *f = ctx;
    record(f, (struct event){ .kind = EV_SEND_NOP });
    return GXFP_IO_OK;
}

static enum gxfp_io_result fake_sleep_ms(void *ctx, unsigned ms)
{
    struct fake *f = ctx;
    record(f, (struct event){ .kind = EV_SLEEP, .a = ms });
    return GXFP_IO_OK;
}

static enum gxfp_io_result fake_send_a4(void *ctx, const uint8_t payload[2])
{
    struct fake *f = ctx;
    struct event e = { .kind = EV_SEND_A4 };
    e.payload[0] = payload[0];
    e.payload[1] = payload[1];
    record(f, e);
    return GXFP_IO_OK;
}

static enum gxfp_io_result fake_wait_ack(void *ctx,
                                         uint8_t cmd0,
                                         uint8_t cmd1,
                                         unsigned timeout_ms)
{
    struct fake *f = ctx;
    record(f, (struct event){
        .kind = EV_WAIT_ACK,
        .a = ((unsigned)cmd0 << 8) | cmd1,
        .b = timeout_ms,
    });
    if (f->ack_pos >= f->ack_count)
        return GXFP_IO_TIMEOUT;
    return f->ack_results[f->ack_pos++];
}

static enum gxfp_io_result fake_wait_response(void *ctx,
                                              uint8_t event_index,
                                              unsigned timeout_ms)
{
    struct fake *f = ctx;
    record(f, (struct event){
        .kind = EV_WAIT_RESPONSE,
        .a = event_index,
        .b = timeout_ms,
    });
    return f->response_result;
}

static struct gxfp_attempt_backend backend(struct fake *f)
{
    return (struct gxfp_attempt_backend){
        .ctx = f,
        .send_nop = fake_send_nop,
        .sleep_ms = fake_sleep_ms,
        .send_a4 = fake_send_a4,
        .wait_ack = fake_wait_ack,
        .wait_response = fake_wait_response,
    };
}

#define ASSERT_TRUE(x) do { \
    if (!(x)) { \
        fprintf(stderr, "%s:%d: assertion failed: %s\n", __FILE__, __LINE__, #x); \
        exit(1); \
    } \
} while (0)

#define ASSERT_EQ(actual, expected) do { \
    long long _a = (long long)(actual); \
    long long _e = (long long)(expected); \
    if (_a != _e) { \
        fprintf(stderr, "%s:%d: got %lld, expected %lld: %s\n", \
                __FILE__, __LINE__, _a, _e, #actual); \
        exit(1); \
    } \
} while (0)

static void test_success_first_ack(void)
{
    struct fake f = {
        .ack_results = { GXFP_IO_OK },
        .ack_count = 1,
        .response_result = GXFP_IO_OK,
    };
    const uint8_t payload[2] = { 0x12, 0x34 };
    struct gxfp_attempt_backend b = backend(&f);

    ASSERT_EQ(gxfp_get_evk_attempt(&b, payload), GXFP_ATTEMPT_OK);
    ASSERT_EQ(f.event_count, 5);
    ASSERT_EQ(f.events[0].kind, EV_SEND_NOP);
    ASSERT_EQ(f.events[1].kind, EV_SLEEP);
    ASSERT_EQ(f.events[1].a, 5);
    ASSERT_EQ(f.events[2].kind, EV_SEND_A4);
    ASSERT_EQ(f.events[2].payload[0], 0x12);
    ASSERT_EQ(f.events[2].payload[1], 0x34);
    ASSERT_EQ(f.events[3].kind, EV_WAIT_ACK);
    ASSERT_EQ(f.events[3].a, 0x0a04);
    ASSERT_EQ(f.events[3].b, 1000);
    ASSERT_EQ(f.events[4].kind, EV_WAIT_RESPONSE);
    ASSERT_EQ(f.events[4].a, 9);
    ASSERT_EQ(f.events[4].b, 1000);
}

static void test_ack_timeout_retransmits_once(void)
{
    struct fake f = {
        .ack_results = { GXFP_IO_TIMEOUT, GXFP_IO_OK },
        .ack_count = 2,
        .response_result = GXFP_IO_OK,
    };
    const uint8_t payload[2] = { 0x55, 0xaa };
    struct gxfp_attempt_backend b = backend(&f);

    ASSERT_EQ(gxfp_get_evk_attempt(&b, payload), GXFP_ATTEMPT_OK);
    ASSERT_EQ(f.event_count, 7);
    ASSERT_EQ(f.events[2].kind, EV_SEND_A4);
    ASSERT_EQ(f.events[3].kind, EV_WAIT_ACK);
    ASSERT_EQ(f.events[4].kind, EV_SEND_A4);
    ASSERT_EQ(f.events[4].payload[0], 0x55);
    ASSERT_EQ(f.events[4].payload[1], 0xaa);
    ASSERT_EQ(f.events[5].kind, EV_WAIT_ACK);
    ASSERT_EQ(f.events[6].kind, EV_WAIT_RESPONSE);
}

static void test_second_ack_timeout_stops_without_response(void)
{
    struct fake f = {
        .ack_results = { GXFP_IO_TIMEOUT, GXFP_IO_TIMEOUT },
        .ack_count = 2,
        .response_result = GXFP_IO_OK,
    };
    const uint8_t payload[2] = { 0x00, 0x00 };
    struct gxfp_attempt_backend b = backend(&f);

    ASSERT_EQ(gxfp_get_evk_attempt(&b, payload), GXFP_ATTEMPT_ACK_TIMEOUT);
    ASSERT_EQ(f.event_count, 6);
    ASSERT_EQ(f.events[5].kind, EV_WAIT_ACK);
}

static void test_response_timeout_is_distinct(void)
{
    struct fake f = {
        .ack_results = { GXFP_IO_OK },
        .ack_count = 1,
        .response_result = GXFP_IO_TIMEOUT,
    };
    const uint8_t payload[2] = { 0x00, 0x00 };
    struct gxfp_attempt_backend b = backend(&f);

    ASSERT_EQ(gxfp_get_evk_attempt(&b, payload), GXFP_ATTEMPT_RESPONSE_TIMEOUT);
    ASSERT_EQ(f.event_count, 5);
    ASSERT_EQ(f.events[4].kind, EV_WAIT_RESPONSE);
}

static void test_cancel_stops_immediately(void)
{
    struct fake f = {
        .ack_results = { GXFP_IO_CANCELLED },
        .ack_count = 1,
        .response_result = GXFP_IO_OK,
    };
    const uint8_t payload[2] = { 0x00, 0x00 };
    struct gxfp_attempt_backend b = backend(&f);

    ASSERT_EQ(gxfp_get_evk_attempt(&b, payload), GXFP_ATTEMPT_CANCELLED);
    ASSERT_EQ(f.event_count, 4);
    ASSERT_EQ(f.events[3].kind, EV_WAIT_ACK);
}

static void test_payload_is_mandatory(void)
{
    struct fake f = { 0 };
    struct gxfp_attempt_backend b = backend(&f);

    ASSERT_EQ(gxfp_get_evk_attempt(&b, NULL), GXFP_ATTEMPT_INVALID);
    ASSERT_EQ(f.event_count, 0);
}

int main(void)
{
    test_success_first_ack();
    test_ack_timeout_retransmits_once();
    test_second_ack_timeout_stops_without_response();
    test_response_timeout_is_distinct();
    test_cancel_stops_immediately();
    test_payload_is_mandatory();
    puts("test_milan_attempt: OK");
    return 0;
}
