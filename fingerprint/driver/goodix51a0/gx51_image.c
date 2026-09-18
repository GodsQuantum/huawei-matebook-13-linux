#include "gx51_image.h"

static void decode4(const uint8_t b[6], uint16_t p[4])
{
    p[0] = (uint16_t)(((b[0] & 0x0fu) << 8) | b[1]);
    p[1] = (uint16_t)((b[3] << 4) | (b[0] >> 4));
    p[2] = (uint16_t)(((b[5] & 0x0fu) << 8) | b[2]);
    p[3] = (uint16_t)((b[4] << 4) | (b[5] >> 4));
}

bool gxfp_decode_image_plaintext(const uint8_t *plaintext, size_t plaintext_len,
                                 uint16_t out[GXFP_IMAGE_OUTPUT_PIXELS])
{
    uint16_t wire[GXFP_IMAGE_WIRE_PIXELS];
    const uint8_t *packed;
    size_t i, o = 0;

    if (plaintext == NULL || out == NULL ||
        plaintext_len != GXFP_IMAGE_PLAINTEXT_LEN)
        return false;

    packed = plaintext + GXFP_IMAGE_HEADER_LEN;
    for (i = 0; i < GXFP_IMAGE_PACKED_LEN; i += 6u) {
        uint16_t p[4];
        decode4(packed + i, p);
        wire[o++] = p[0];
        wire[o++] = p[1];
        wire[o++] = p[2];
        wire[o++] = p[3];
    }
    if (o != GXFP_IMAGE_WIRE_PIXELS)
        return false;

    for (size_t y = 0; y < GXFP_IMAGE_OUTPUT_HEIGHT; y++)
        for (size_t x = 0; x < GXFP_IMAGE_OUTPUT_WIDTH; x++)
            out[y * GXFP_IMAGE_OUTPUT_WIDTH + x] =
                wire[x * GXFP_IMAGE_WIRE_WIDTH + y];

    return true;
}
