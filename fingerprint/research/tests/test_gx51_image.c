#include "../../driver/goodix51a0/gx51_image.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void pack4(uint16_t p0, uint16_t p1, uint16_t p2, uint16_t p3, uint8_t b[6])
{
    b[0] = (uint8_t)(((p1 & 0x0fu) << 4) | ((p0 >> 8) & 0x0fu));
    b[1] = (uint8_t)p0;
    b[2] = (uint8_t)p2;
    b[3] = (uint8_t)(p1 >> 4);
    b[4] = (uint8_t)(p3 >> 4);
    b[5] = (uint8_t)(((p3 & 0x0fu) << 4) | ((p2 >> 8) & 0x0fu));
}

int main(void)
{
    uint8_t plain[GXFP_IMAGE_PLAINTEXT_LEN] = {0};
    uint16_t out[GXFP_IMAGE_OUTPUT_PIXELS] = {0};
    uint16_t wire[GXFP_IMAGE_WIRE_PIXELS] = {0};
    size_t o = GXFP_IMAGE_HEADER_LEN;

    for (size_t y = 0; y < GXFP_IMAGE_HEIGHT; y++)
        for (size_t x = 0; x < GXFP_IMAGE_WIRE_WIDTH; x++)
            wire[y * GXFP_IMAGE_WIRE_WIDTH + x] =
                x < GXFP_IMAGE_ACTIVE_WIDTH
                    ? (uint16_t)((y * 64u + x) & 0x0fffu)
                    : 0x0aaau;

    for (size_t i = 0; i < GXFP_IMAGE_WIRE_PIXELS; i += 4, o += 6)
        pack4(wire[i], wire[i + 1], wire[i + 2], wire[i + 3], plain + o);

    assert(o == GXFP_IMAGE_PLAINTEXT_LEN - GXFP_IMAGE_TRAILER_LEN);
    assert(gxfp_decode_image_plaintext(plain, sizeof plain, out));
    /* The wire crop is 64 columns x 80 rows. Transpose it to the
     * libfprint/Windows-facing 80x64 orientation. */
    for (size_t y = 0; y < GXFP_IMAGE_OUTPUT_HEIGHT; y++)
        for (size_t x = 0; x < GXFP_IMAGE_OUTPUT_WIDTH; x++)
            assert(out[y * GXFP_IMAGE_OUTPUT_WIDTH + x] ==
                   wire[x * GXFP_IMAGE_WIRE_WIDTH + y]);

    assert(!gxfp_decode_image_plaintext(plain, sizeof plain - 1u, out));
    assert(!gxfp_decode_image_plaintext(NULL, sizeof plain, out));
    assert(!gxfp_decode_image_plaintext(plain, sizeof plain, NULL));
    puts("test_gx51_image: OK");
    return 0;
}
