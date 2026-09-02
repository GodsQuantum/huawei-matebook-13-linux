#include "gpiod_reset.h"

#include <gpiod.h>
#include <stdbool.h>
#include <stdlib.h>

struct gxfp_gpiod_reset {
    struct gpiod_chip *chip;
    struct gpiod_line_request *request;
    unsigned int offset;
};

void gxfp_gpiod_reset_close(struct gxfp_gpiod_reset *reset)
{
    if (reset == NULL)
        return;
    if (reset->request != NULL)
        gpiod_line_request_release(reset->request);
    if (reset->chip != NULL)
        gpiod_chip_close(reset->chip);
    free(reset);
}

int gxfp_gpiod_reset_open_as_is(struct gxfp_gpiod_reset **out,
                                const char *chip_path,
                                unsigned int offset)
{
    struct gxfp_gpiod_reset *reset = NULL;
    struct gpiod_line_info *info = NULL;
    struct gpiod_line_settings *settings = NULL;
    struct gpiod_line_config *line_cfg = NULL;
    struct gpiod_request_config *request_cfg = NULL;
    int rc = -1;

    if (out == NULL || chip_path == NULL || *chip_path == '\0')
        return -1;
    *out = NULL;

    reset = calloc(1, sizeof(*reset));
    if (reset == NULL)
        goto out;
    reset->offset = offset;

    reset->chip = gpiod_chip_open(chip_path);
    if (reset->chip == NULL)
        goto out;

    info = gpiod_chip_get_line_info(reset->chip, offset);
    if (info == NULL)
        goto out;

    /* Fail closed: this experiment relies on firmware having configured
     * GPIO264 as a free, active-high output already. */
    if (gpiod_line_info_is_used(info) ||
        gpiod_line_info_get_direction(info) != GPIOD_LINE_DIRECTION_OUTPUT ||
        gpiod_line_info_is_active_low(info) ||
        gpiod_line_info_get_edge_detection(info) != GPIOD_LINE_EDGE_NONE)
        goto out;

    settings = gpiod_line_settings_new();
    if (settings == NULL)
        goto out;
    if (gpiod_line_settings_set_direction(settings,
                                          GPIOD_LINE_DIRECTION_AS_IS) < 0)
        goto out;
    if (gpiod_line_settings_set_bias(settings, GPIOD_LINE_BIAS_AS_IS) < 0)
        goto out;
    gpiod_line_settings_set_active_low(settings, false);

    line_cfg = gpiod_line_config_new();
    if (line_cfg == NULL)
        goto out;
    if (gpiod_line_config_add_line_settings(line_cfg, &offset, 1, settings) < 0)
        goto out;

    request_cfg = gpiod_request_config_new();
    if (request_cfg == NULL)
        goto out;
    gpiod_request_config_set_consumer(request_cfg, "gxfp-research-reset");

    reset->request = gpiod_chip_request_lines(reset->chip,
                                              request_cfg,
                                              line_cfg);
    if (reset->request == NULL)
        goto out;

    *out = reset;
    reset = NULL;
    rc = 0;

out:
    gpiod_request_config_free(request_cfg);
    gpiod_line_config_free(line_cfg);
    gpiod_line_settings_free(settings);
    gpiod_line_info_free(info);
    gxfp_gpiod_reset_close(reset);
    return rc;
}

int gxfp_gpiod_reset_set_level(struct gxfp_gpiod_reset *reset, int level)
{
    enum gpiod_line_value value;

    if (reset == NULL || reset->request == NULL || (level != 0 && level != 1))
        return -1;

    value = level ? GPIOD_LINE_VALUE_ACTIVE : GPIOD_LINE_VALUE_INACTIVE;
    return gpiod_line_request_set_value(reset->request, reset->offset, value);
}

int gxfp_gpiod_reset_get_level(struct gxfp_gpiod_reset *reset)
{
    enum gpiod_line_value value;

    if (reset == NULL || reset->request == NULL)
        return -1;

    value = gpiod_line_request_get_value(reset->request, reset->offset);
    if (value == GPIOD_LINE_VALUE_ACTIVE)
        return 1;
    if (value == GPIOD_LINE_VALUE_INACTIVE)
        return 0;
    return -1;
}
