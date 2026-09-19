/* SPDX-License-Identifier: LGPL-2.1-or-later */
#include "gx51_capture_recipe.h"

#include <string.h>

static const uint8_t FDT_BOOT[12] = {
    0xb2,0xb2,0xc2,0xc2,0xa7,0xa7,0xb6,0xb6,0xa6,0xa6,0xb6,0xb6
};
static const uint8_t FDT_BACKGROUND[12] = {
    0x80,0xb0,0x80,0xc0,0x80,0xa4,0x80,0xb4,0x80,0xa3,0x80,0xb4
};
static const uint8_t FDT_FINGER_MODE[12] = {
    0x80,0xb1,0x80,0xc1,0x80,0xa6,0x80,0xb6,0x80,0xa5,0x80,0xb6
};
static const uint8_t FDT_CAPTURE_DOWN[12] = {
    0x80,0xb2,0x80,0xc2,0x80,0xa7,0x80,0xb6,0x80,0xa6,0x80,0xb6
};
static const uint8_t FDT_UP[12] = {
    0x80,0x90,0x80,0x9a,0x80,0x7b,0x80,0x95,0x80,0x8c,0x80,0xa3
};
static const uint8_t FDT_POST_DOWN[12] = {
    0x80,0xa7,0x80,0xb9,0x80,0xa3,0x80,0xb5,0x80,0xa4,0x80,0xb6
};

static bool push(struct gxfp_capture_recipe *r,
                 bool ok, const struct gxfp_target_packet *p)
{
    if (!ok || r == NULL || p == NULL || r->count >= GXFP_CAPTURE_RECIPE_MAX)
        return false;
    r->steps[r->count++] = *p;
    return true;
}
bool gxfp_build_background_capture_recipe(
    const struct gxfp_target_calibration *cal,
    struct gxfp_capture_recipe *r)
{
    struct gxfp_target_packet p;

    if (cal == NULL || r == NULL)
        return false;
    memset(r, 0, sizeof(*r));

    return push(r, gxfp_build_nop(&p), &p) &&
           push(r, gxfp_build_query_mcu_state(0x55u, &p), &p) &&
           push(r, gxfp_build_fdt_command(0x0du, FDT_BOOT, &p), &p) &&
           push(r, gxfp_build_nav(&p), &p) &&
           push(r, gxfp_build_fdt_command(0x0du, FDT_BACKGROUND, &p), &p) &&
           push(r, gxfp_build_reg_read(0x0082u, 2u, &p), &p) &&
           push(r, gxfp_build_reg_write(0x0220u, cal->dac_main, &p), &p) &&
           push(r, gxfp_build_reg_write(0x0236u, cal->dac1, &p), &p) &&
           push(r, gxfp_build_reg_write(0x0238u, cal->dac2, &p), &p) &&
           push(r, gxfp_build_reg_write(0x023au, cal->dac3, &p), &p) &&
           push(r, gxfp_build_get_image(&p), &p);
}

bool gxfp_build_fdt_probe(struct gxfp_target_packet *packet)
{
    return packet != NULL &&
           gxfp_build_fdt_command(0x0du, FDT_FINGER_MODE, packet);
}

bool gxfp_build_finger_capture_recipe(struct gxfp_capture_recipe *r)
{
    struct gxfp_target_packet p;

    if (r == NULL)
        return false;
    memset(r, 0, sizeof(*r));

    return push(r, gxfp_build_fdt_command(0x0du, FDT_FINGER_MODE, &p), &p) &&
           push(r, gxfp_build_fdt_command(0x0cu, FDT_FINGER_MODE, &p), &p) &&
           push(r, gxfp_build_nop(&p), &p) &&
           push(r, gxfp_build_query_mcu_state(0x55u, &p), &p) &&
           push(r, gxfp_build_fdt_command(0x0cu, FDT_CAPTURE_DOWN, &p), &p) &&
           push(r, gxfp_build_get_image(&p), &p);
}
bool gxfp_build_capture_cleanup_recipe(struct gxfp_capture_recipe *r)
{
    struct gxfp_target_packet p;

    if (r == NULL)
        return false;
    memset(r, 0, sizeof(*r));

    return push(r, gxfp_build_fdt_command(0x0eu, FDT_UP, &p), &p) &&
           push(r, gxfp_build_get_image(&p), &p) &&
           push(r, gxfp_build_nav(&p), &p) &&
           push(r, gxfp_build_fdt_command(0x0cu, FDT_POST_DOWN, &p), &p);
}
