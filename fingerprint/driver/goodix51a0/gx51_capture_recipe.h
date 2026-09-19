/* SPDX-License-Identifier: LGPL-2.1-or-later */
#ifndef GX51_CAPTURE_RECIPE_H
#define GX51_CAPTURE_RECIPE_H

#include "gx51_target.h"

#define GXFP_CAPTURE_RECIPE_MAX 11u

struct gxfp_capture_recipe {
    struct gxfp_target_packet steps[GXFP_CAPTURE_RECIPE_MAX];
    size_t count;
};

bool gxfp_build_background_capture_recipe(
    const struct gxfp_target_calibration *cal,
    struct gxfp_capture_recipe *recipe);
bool gxfp_build_finger_capture_recipe(struct gxfp_capture_recipe *recipe);
bool gxfp_build_fdt_probe(struct gxfp_target_packet *packet);
bool gxfp_build_capture_cleanup_recipe(struct gxfp_capture_recipe *recipe);

#endif
