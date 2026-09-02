#define _GNU_SOURCE
#include "linux_spi.h"

#include <fcntl.h>
#include <limits.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int system_open(const char *path, int flags)
{
    return open(path, flags);
}

static int system_close(int fd)
{
    return close(fd);
}

static int system_ioctl(int fd, unsigned long request, void *arg)
{
    return ioctl(fd, request, arg);
}

static const struct gxfp_spi_ops system_ops = {
    .open_fn = system_open,
    .close_fn = system_close,
    .ioctl_fn = system_ioctl,
};

const struct gxfp_spi_ops *gxfp_spi_system_ops(void)
{
    return &system_ops;
}

static void invalidate(struct gxfp_spi *spi)
{
    spi->fd = -1;
    spi->max_speed_hz = 0;
    spi->transfer_count = 0;
    spi->ops = NULL;
}

int gxfp_spi_open_configure(struct gxfp_spi *spi,
                            const char *path,
                            const struct gxfp_spi_ops *ops)
{
    uint8_t mode = GXFP_SPI_MODE;
    uint8_t bits = GXFP_SPI_BITS_PER_WORD;
    uint32_t speed = GXFP_SPI_MAX_SPEED_HZ;
    uint8_t mode_read = 0xff;
    uint8_t bits_read = 0;
    uint32_t speed_read = 0;
    int fd;

    if (!spi || !path || !*path)
        return -1;
    if (!ops)
        ops = &system_ops;
    if (!ops->open_fn || !ops->close_fn || !ops->ioctl_fn)
        return -1;

    invalidate(spi);
    fd = ops->open_fn(path, O_RDWR | O_CLOEXEC);
    if (fd < 0)
        return -1;

    if (ops->ioctl_fn(fd, SPI_IOC_WR_MODE, &mode) < 0 ||
        ops->ioctl_fn(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
        ops->ioctl_fn(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0 ||
        ops->ioctl_fn(fd, SPI_IOC_RD_MODE, &mode_read) < 0 ||
        ops->ioctl_fn(fd, SPI_IOC_RD_BITS_PER_WORD, &bits_read) < 0 ||
        ops->ioctl_fn(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed_read) < 0 ||
        mode_read != mode || bits_read != bits || speed_read != speed) {
        ops->close_fn(fd);
        invalidate(spi);
        return -1;
    }

    spi->fd = fd;
    spi->max_speed_hz = speed_read;
    spi->transfer_count = 0;
    spi->ops = ops;
    return 0;
}

void gxfp_spi_close(struct gxfp_spi *spi)
{
    const struct gxfp_spi_ops *ops;
    int fd;

    if (!spi || spi->fd < 0)
        return;
    ops = spi->ops;
    fd = spi->fd;
    invalidate(spi);
    if (ops && ops->close_fn)
        ops->close_fn(fd);
}

static int transfer_exact(struct gxfp_spi *spi,
                          const uint8_t *tx,
                          uint8_t *rx,
                          size_t len)
{
    struct spi_ioc_transfer xfer;
    int rc;

    if (!spi || spi->fd < 0 || !spi->ops || !spi->ops->ioctl_fn ||
        len == 0 || len > UINT32_MAX || (!tx && !rx))
        return -1;

    memset(&xfer, 0, sizeof(xfer));
    xfer.tx_buf = (uintptr_t)tx;
    xfer.rx_buf = (uintptr_t)rx;
    xfer.len = (uint32_t)len;
    xfer.speed_hz = spi->max_speed_hz;
    xfer.bits_per_word = GXFP_SPI_BITS_PER_WORD;

    rc = spi->ops->ioctl_fn(spi->fd, SPI_IOC_MESSAGE(1), &xfer);
    if (rc < 0 || (size_t)rc != len)
        return -1;

    spi->transfer_count++;
    return 0;
}

int gxfp_spi_write_exact(struct gxfp_spi *spi,
                         const uint8_t *data,
                         size_t len)
{
    if (!data)
        return -1;
    return transfer_exact(spi, data, NULL, len);
}

int gxfp_spi_read_exact(struct gxfp_spi *spi,
                        uint8_t *data,
                        size_t len)
{
    if (!data)
        return -1;
    return transfer_exact(spi, NULL, data, len);
}
