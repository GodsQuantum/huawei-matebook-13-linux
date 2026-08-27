#include "gpiod_irq.h"
#include "linux_spi.h"
#include "spidev_discovery.h"

#include <stdio.h>

#define GXFP_SPI_SYSFS "/sys/bus/spi/devices/spi-GXFP51A0:00"
#define GXFP_DEV_ROOT "/dev"
#define GXFP_GPIO_CHIP "/dev/gpiochip0"
#define GXFP_IRQ_OFFSET 48u

int main(void)
{
    char spi_path[256];
    struct gxfp_spi spi;
    struct gxfp_gpiod_irq *irq = NULL;
    enum gxfp_discovery_result discovery;
    int irq_level;
    int rc = 1;

    discovery = gxfp_find_spidev_node(GXFP_SPI_SYSFS,
                                      GXFP_DEV_ROOT,
                                      spi_path,
                                      sizeof(spi_path));
    if (discovery != GXFP_DISCOVERY_OK) {
        fprintf(stderr, "spidev discovery failed: %d\n", discovery);
        return 1;
    }

    if (gxfp_spi_open_configure(&spi, spi_path, NULL) != 0) {
        fprintf(stderr, "SPI open/configure failed\n");
        return 1;
    }

    if (gxfp_gpiod_irq_open(&irq, GXFP_GPIO_CHIP, GXFP_IRQ_OFFSET) != 0) {
        fprintf(stderr, "GPIO48 input request failed\n");
        goto out_spi;
    }

    irq_level = gxfp_gpiod_irq_get_value(irq);
    if (irq_level < 0) {
        fprintf(stderr, "GPIO48 read failed\n");
        goto out_irq;
    }

    printf("SPI_NODE=%s\n", spi_path);
    printf("SPI_MODE=%u\n", GXFP_SPI_MODE);
    printf("SPI_BITS=%u\n", GXFP_SPI_BITS_PER_WORD);
    printf("SPI_MAX_SPEED_HZ=%u\n", spi.max_speed_hz);
    printf("SPI_TRANSFER_COUNT=%u\n", spi.transfer_count);
    printf("IRQ_OFFSET=%u\n", GXFP_IRQ_OFFSET);
    printf("IRQ_LEVEL=%d\n", irq_level);
    printf("GPIO264_REQUESTED=NO\n");

    if (spi.transfer_count != 0) {
        fprintf(stderr, "safety violation: passive preflight transferred SPI data\n");
        goto out_irq;
    }

    printf("PASSIVE_PREFLIGHT=SUCCESS\n");
    rc = 0;

out_irq:
    gxfp_gpiod_irq_close(irq);
out_spi:
    gxfp_spi_close(&spi);
    return rc;
}
