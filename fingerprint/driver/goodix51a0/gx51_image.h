#ifndef GX51_IMAGE_H
#define GX51_IMAGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GXFP_IMAGE_ACTIVE_WIDTH 64u
#define GXFP_IMAGE_HEIGHT 80u
#define GXFP_IMAGE_WIRE_WIDTH 88u
#define GXFP_IMAGE_OUTPUT_WIDTH 80u
#define GXFP_IMAGE_OUTPUT_HEIGHT 64u
#define GXFP_IMAGE_OUTPUT_PIXELS (GXFP_IMAGE_OUTPUT_WIDTH * GXFP_IMAGE_OUTPUT_HEIGHT)
#define GXFP_IMAGE_WIRE_PIXELS (GXFP_IMAGE_WIRE_WIDTH * GXFP_IMAGE_HEIGHT)
#define GXFP_IMAGE_HEADER_LEN 8u
#define GXFP_IMAGE_TRAILER_LEN 5u
#define GXFP_IMAGE_PACKED_LEN 10560u
#define GXFP_IMAGE_PLAINTEXT_LEN     (GXFP_IMAGE_HEADER_LEN + GXFP_IMAGE_PACKED_LEN + GXFP_IMAGE_TRAILER_LEN)

bool gxfp_decode_image_plaintext(const uint8_t *plaintext, size_t plaintext_len,
                                 uint16_t out[GXFP_IMAGE_OUTPUT_PIXELS]);

#endif
