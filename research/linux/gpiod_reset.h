#ifndef GXFP_GPIOD_RESET_H
#define GXFP_GPIOD_RESET_H

struct gxfp_gpiod_reset;

/*
 * Request an already-configured output line without changing direction,
 * bias, drive mode, active-low mapping, or edge configuration.
 */
int gxfp_gpiod_reset_open_as_is(struct gxfp_gpiod_reset **out,
                                const char *chip_path,
                                unsigned int offset);
int gxfp_gpiod_reset_set_level(struct gxfp_gpiod_reset *reset, int level);
int gxfp_gpiod_reset_get_level(struct gxfp_gpiod_reset *reset);
void gxfp_gpiod_reset_close(struct gxfp_gpiod_reset *reset);

#endif
