#include "milan_rx.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void test_outer_header_accepts_valid_a_frame(void)
{
    const uint8_t header[4] = {0xa0, 0x06, 0x00, 0xa6};
    size_t body_len = 0;

    assert(gxfp_milan_rx_outer_body_len(header, &body_len));
    assert(body_len == 6);
}

static void test_ff_header_is_explicit_no_data_sentinel(void)
{
    const uint8_t header[4] = {0xff, 0xff, 0xff, 0xff};

    assert(gxfp_milan_rx_is_ff_header(header));
}

static void test_outer_header_rejects_bad_checksum(void)
{
    const uint8_t header[4] = {0xa0, 0x06, 0x00, 0xa7};
    size_t body_len = 123;

    assert(!gxfp_milan_rx_outer_body_len(header, &body_len));
}

static void test_a4_ack_is_b0_message_targeting_a8(void)
{
    const uint8_t body[] = {0xb0, 0x03, 0x00, 0xa8, 0x00, 0x4f};
    struct gxfp_milan_evk_frame frame;

    assert(gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
    assert(frame.kind == GXFP_MILAN_EVK_ACK);
    assert(frame.cmd0 == 0x0b);
    assert(frame.cmd1 == 0x00);
    assert(frame.payload_len == 2);
    assert(frame.payload[0] == 0xa8);
    assert(frame.payload[1] == 0x00);
    assert(frame.ack_status == 0x00);
}

static void test_a4_response_is_a4_and_preserves_payload(void)
{
    const uint8_t body[] = {0xa8, 0x04, 0x00, 0x11, 0x22, 0x33, 0x98};
    struct gxfp_milan_evk_frame frame;

    assert(gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
    assert(frame.kind == GXFP_MILAN_EVK_RESPONSE);
    assert(frame.cmd0 == 0x0a);
    assert(frame.cmd1 == 0x04);
    assert(frame.payload_len == 3);
    assert(memcmp(frame.payload, (const uint8_t[]){0x11, 0x22, 0x33}, 3) == 0);
}

static void test_b0_for_another_command_is_not_a4_ack(void)
{
    const uint8_t body[] = {0xb0, 0x03, 0x00, 0x90, 0x00, 0x67};
    struct gxfp_milan_evk_frame frame;

    assert(gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
    assert(frame.kind == GXFP_MILAN_EVK_OTHER);
}

static void test_inner_length_must_match_exact_body_length(void)
{
    const uint8_t body[] = {0xa8, 0x04, 0x00, 0x11, 0x22, 0x33, 0x98, 0x00};
    struct gxfp_milan_evk_frame frame;

    assert(!gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
}

static void test_inner_checksum_must_validate(void)
{
    const uint8_t body[] = {0xa8, 0x04, 0x00, 0x11, 0x22, 0x33, 0x99};
    struct gxfp_milan_evk_frame frame;

    assert(!gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
}

static void test_fragment_flag_is_rejected_by_minimal_parser(void)
{
    /* bit0 is the Windows fragmentation/continuation state bit; unsupported here. */
    const uint8_t body[] = {0xa9, 0x04, 0x00, 0x11, 0x22, 0x33, 0x97};
    struct gxfp_milan_evk_frame frame;

    assert(!gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
}

static void test_a4_response_over_64_bytes_is_rejected(void)
{
    uint8_t body[3 + 66];
    struct gxfp_milan_evk_frame frame;
    size_t i;
    unsigned sum = 0;

    body[0] = 0xa8;
    body[1] = 66; /* 65 payload bytes + checksum */
    body[2] = 0;
    for (i = 0; i < 65; i++)
        body[3 + i] = (uint8_t)i;

    for (i = 0; i < sizeof(body) - 1; i++)
        sum += body[i];
    body[sizeof(body) - 1] = (uint8_t)(0xaa - sum);

    assert(!gxfp_milan_rx_classify_evk(body, sizeof(body), &frame));
}

int main(void)
{
    test_outer_header_accepts_valid_a_frame();
    test_ff_header_is_explicit_no_data_sentinel();
    test_outer_header_rejects_bad_checksum();
    test_a4_ack_is_b0_message_targeting_a8();
    test_a4_response_is_a4_and_preserves_payload();
    test_b0_for_another_command_is_not_a4_ack();
    test_inner_length_must_match_exact_body_length();
    test_inner_checksum_must_validate();
    test_fragment_flag_is_rejected_by_minimal_parser();
    test_a4_response_over_64_bytes_is_rejected();

    puts("test_milan_rx: OK");
    return 0;
}
