#ifndef GXFP_GPIOD_IRQ_H
#define GXFP_GPIOD_IRQ_H

struct gxfp_gpiod_irq;

int gxfp_gpiod_irq_open(struct gxfp_gpiod_irq **out,
                        const char *chip_path,
                        unsigned int offset);
int gxfp_gpiod_irq_get_value(struct gxfp_gpiod_irq *irq);
void gxfp_gpiod_irq_close(struct gxfp_gpiod_irq *irq);

#endif
