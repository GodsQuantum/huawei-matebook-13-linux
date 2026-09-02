#include "gpiod_irq.h"

#include <gpiod.h>
#include <stdlib.h>

struct gxfp_gpiod_irq {
    struct gpiod_chip *chip;
    struct gpiod_line_request *request;
    unsigned int offset;
};

void gxfp_gpiod_irq_close(struct gxfp_gpiod_irq *irq)
{
    if (!irq)
        return;
    if (irq->request)
        gpiod_line_request_release(irq->request);
    if (irq->chip)
        gpiod_chip_close(irq->chip);
    free(irq);
}

int gxfp_gpiod_irq_open(struct gxfp_gpiod_irq **out,
                        const char *chip_path,
                        unsigned int offset)
{
    struct gxfp_gpiod_irq *irq = NULL;
    struct gpiod_line_settings *settings = NULL;
    struct gpiod_line_config *line_cfg = NULL;
    struct gpiod_request_config *request_cfg = NULL;
    int rc = -1;

    if (!out || !chip_path || !*chip_path)
        return -1;
    *out = NULL;

    irq = calloc(1, sizeof(*irq));
    if (!irq)
        goto out;
    irq->offset = offset;

    irq->chip = gpiod_chip_open(chip_path);
    if (!irq->chip)
        goto out;

    settings = gpiod_line_settings_new();
    if (!settings)
        goto out;
    if (gpiod_line_settings_set_direction(settings,
                                          GPIOD_LINE_DIRECTION_INPUT) < 0)
        goto out;
    if (gpiod_line_settings_set_bias(settings, GPIOD_LINE_BIAS_AS_IS) < 0)
        goto out;
    gpiod_line_settings_set_active_low(settings, false);

    line_cfg = gpiod_line_config_new();
    if (!line_cfg)
        goto out;
    if (gpiod_line_config_add_line_settings(line_cfg, &offset, 1, settings) < 0)
        goto out;

    request_cfg = gpiod_request_config_new();
    if (!request_cfg)
        goto out;
    gpiod_request_config_set_consumer(request_cfg, "gxfp-research-passive");

    irq->request = gpiod_chip_request_lines(irq->chip, request_cfg, line_cfg);
    if (!irq->request)
        goto out;

    *out = irq;
    irq = NULL;
    rc = 0;

out:
    gpiod_request_config_free(request_cfg);
    gpiod_line_config_free(line_cfg);
    gpiod_line_settings_free(settings);
    gxfp_gpiod_irq_close(irq);
    return rc;
}

int gxfp_gpiod_irq_get_value(struct gxfp_gpiod_irq *irq)
{
    enum gpiod_line_value value;

    if (!irq || !irq->request)
        return -1;
    value = gpiod_line_request_get_value(irq->request, irq->offset);
    if (value == GPIOD_LINE_VALUE_ACTIVE)
        return 1;
    if (value == GPIOD_LINE_VALUE_INACTIVE)
        return 0;
    return -1;
}
