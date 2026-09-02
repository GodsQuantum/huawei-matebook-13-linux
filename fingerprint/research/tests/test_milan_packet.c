#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../milan_packet.h"

#define ASSERT_TRUE(x) do { \
    if (!(x)) { \
        fprintf(stderr, "%s:%d: assertion failed: %s\n", __FILE__, __LINE__, #x); \
        exit(1); \
    } \
} while (0)

static void assert_bytes(const uint8_t *actual,
                         const uint8_t *expected,
                         size_t len)
{
    if (memcmp(actual, expected, len) != 0) {
        size_t i;
        fprintf(stderr, "byte mismatch:\nactual:   ");
        for (i = 0; i < len; i++) fprintf(stderr, "%02x ", actual[i]);
        fprintf(stderr, "\nexpected: ");
        for (i = 0; i < len; i++) fprintf(stderr, "%02x ", expected[i]);
        fputc('\n', stderr);
        exit(1);
    }
}

static void test_nop_vector(void)
{
    static const uint8_t outer[] = { 0xa0, 0x08, 0x00, 0xa8 };
    static const uint8_t inner[] = { 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa5 };
    struct gxfp_wire_packet packet;

    ASSERT_TRUE(gxfp_build_nop(&packet));
    ASSERT_TRUE(packet.inner_len == sizeof(inner));
    assert_bytes(packet.outer, outer, sizeof(outer));
    assert_bytes(packet.inner, inner, sizeof(inner));
}


static void test_driver_state_install_vector(void)
{
    static const uint8_t outer[] = { 0xa0, 0x06, 0x00, 0xa6 };
    static const uint8_t inner[] = { 0x96, 0x03, 0x00, 0x01, 0x00, 0x10 };
    struct gxfp_wire_packet packet;

    ASSERT_TRUE(gxfp_build_driver_state_install(&packet));
    ASSERT_TRUE(packet.inner_len == sizeof(inner));
    assert_bytes(packet.outer, outer, sizeof(outer));
    assert_bytes(packet.inner, inner, sizeof(inner));
}

static void test_a4_zero_fixture_vector(void)
{
    static const uint8_t payload[] = { 0x00, 0x00 };
    static const uint8_t outer[] = { 0xa0, 0x06, 0x00, 0xa6 };
    static const uint8_t inner[] = { 0xa8, 0x03, 0x00, 0x00, 0x00, 0xff };
    struct gxfp_wire_packet packet;

    ASSERT_TRUE(gxfp_build_a4(payload, &packet));
    ASSERT_TRUE(packet.inner_len == sizeof(inner));
    assert_bytes(packet.outer, outer, sizeof(outer));
    assert_bytes(packet.inner, inner, sizeof(inner));
}

static void test_a4_payload_changes_only_payload_and_checksum(void)
{
    static const uint8_t payload[] = { 0x12, 0x34 };
    static const uint8_t outer[] = { 0xa0, 0x06, 0x00, 0xa6 };
    static const uint8_t inner[] = { 0xa8, 0x03, 0x00, 0x12, 0x34, 0xb9 };
    struct gxfp_wire_packet packet;

    ASSERT_TRUE(gxfp_build_a4(payload, &packet));
    assert_bytes(packet.outer, outer, sizeof(outer));
    assert_bytes(packet.inner, inner, sizeof(inner));
}

static void test_a4_requires_explicit_payload(void)
{
    struct gxfp_wire_packet packet;
    ASSERT_TRUE(!gxfp_build_a4(NULL, &packet));
}

int main(void)
{
    test_nop_vector();
    test_driver_state_install_vector();
    test_a4_zero_fixture_vector();
    test_a4_payload_changes_only_payload_and_checksum();
    test_a4_requires_explicit_payload();
    puts("test_milan_packet: OK");
    return 0;
}
