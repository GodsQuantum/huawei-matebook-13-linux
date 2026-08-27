#ifndef GXFP_LINUX_SPI_H
#define GXFP_LINUX_SPI_H

#include <stddef.h>
#include <stdint.h>

#define GXFP_SPI_MODE 0u
#define GXFP_SPI_BITS_PER_WORD 8u
#define GXFP_SPI_MAX_SPEED_HZ 10000000u

struct gxfp_spi_ops {
    int (*open_fn)(const char *path, int flags);
    int (*close_fn)(int fd);
    int (*ioctl_fn)(int fd, unsigned long request, void *arg);
};

struct gxfp_spi {
    int fd;
    uint32_t max_speed_hz;
    unsigned transfer_count;
    const struct gxfp_spi_ops *ops;
};

const struct gxfp_spi_ops *gxfp_spi_system_ops(void);

int gxfp_spi_open_configure(struct gxfp_spi *spi,
                            const char *path,
                            const struct gxfp_spi_ops *ops);
void gxfp_spi_close(struct gxfp_spi *spi);
int gxfp_spi_write_exact(struct gxfp_spi *spi,
                         const uint8_t *data,
                         size_t len);
int gxfp_spi_read_exact(struct gxfp_spi *spi,
                        uint8_t *data,
                        size_t len);

#endif
