/* SPDX-License-Identifier: LGPL-2.1-or-later */
#define _GNU_SOURCE
#include "gx51_transport.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <linux/ioctl.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int gx51_sleep_us(long usec)
{
    struct timespec ts = {
        .tv_sec = usec / 1000000L,
        .tv_nsec = (usec % 1000000L) * 1000L,
    };
    while (nanosleep(&ts, &ts) < 0) {
        if (errno != EINTR)
            return -1;
    }
    return 0;
}

int gx51_make_outer(uint8_t type, size_t len, struct gx51_outer *out)
{
    if (!out || len == 0 || len > GX51_MAX_FRAME)
        return -1;

    out->type = type;
    out->len_lo = (uint8_t)(len & 0xff);
    out->len_hi = (uint8_t)((len >> 8) & 0xff);
    out->checksum = (uint8_t)(out->type + out->len_lo + out->len_hi);
    return 0;
}

uint8_t gx51_body_checksum(const uint8_t *data, size_t len)
{
    uint8_t sum = 0;
    size_t i;

    for (i = 0; i < len; i++)
        sum = (uint8_t)(sum + data[i]);

    return (uint8_t)(0xAAu - sum);
}

size_t gx51_read_chunk_size(size_t remaining)
{
    return remaining > GX51_SPI_READ_CHUNK_MAX
               ? GX51_SPI_READ_CHUNK_MAX
               : remaining;
}

int gx51_write_frame_fd(int spi_fd, uint8_t type,
                        const uint8_t *body, size_t len)
{
    struct gx51_outer hdr;
    struct spi_ioc_transfer x = {0};

    if (spi_fd < 0 || !body || gx51_make_outer(type, len, &hdr) < 0)
        return -1;

    x.tx_buf = (uintptr_t)&hdr;
    x.len = sizeof hdr;
    if (ioctl(spi_fd, SPI_IOC_MESSAGE(1), &x) < 1)
        return -1;

    /* Windows GXFP51A0 mode 5: separate synchronous writes, ~2 ms gap. */
    if (gx51_sleep_us(2000) < 0)
        return -1;

    memset(&x, 0, sizeof x);
    x.tx_buf = (uintptr_t)body;
    x.len = (uint32_t)len;
    return ioctl(spi_fd, SPI_IOC_MESSAGE(1), &x) < 1 ? -1 : 0;
}

int gx51_read_frame_fd(int spi_fd, int irq_gpio_fd, uint8_t *type,
                       uint8_t *body, size_t capacity, size_t *body_len)
{
    struct gx51_outer hdr;
    struct spi_ioc_transfer x = {0};
    size_t len;

    if (spi_fd < 0 || irq_gpio_fd < 0 || !type || !body || !body_len)
        return -1;

    if (gx51_wait_irq_gpio48(irq_gpio_fd, 1200) < 0)
        return -1;

    memset(&hdr, 0, sizeof hdr);
    x.rx_buf = (uintptr_t)&hdr;
    x.len = sizeof hdr;
    if (ioctl(spi_fd, SPI_IOC_MESSAGE(1), &x) < 1)
        return -1;

    /* Interpret all-FF before header checksum: this is the target's proven
     * silent/high-Z-or-all-ones observation class. */
    if (hdr.type == 0xff && hdr.len_lo == 0xff &&
        hdr.len_hi == 0xff && hdr.checksum == 0xff)
        return -2;

    if ((uint8_t)(hdr.type + hdr.len_lo + hdr.len_hi) != hdr.checksum)
        return -3;

    len = (size_t)hdr.len_lo | ((size_t)hdr.len_hi << 8);
    if (len == 0 || len > capacity)
        return -4;

    for (size_t off = 0; off < len; ) {
        size_t chunk = gx51_read_chunk_size(len - off);

        memset(&x, 0, sizeof x);
        x.rx_buf = (uintptr_t)(body + off);
        x.len = (uint32_t)chunk;
        if (ioctl(spi_fd, SPI_IOC_MESSAGE(1), &x) < 1)
            return -1;
        off += chunk;
    }

    *type = hdr.type;
    *body_len = len;
    return 0;
}

static int gx51_open_int34bb(void)
{
    int n;

    for (n = 0; n < 16; n++) {
        char path[32];
        struct gpiochip_info info = {0};
        int fd;

        if (snprintf(path, sizeof path, "/dev/gpiochip%d", n) < 0)
            continue;

        fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd < 0)
            continue;

        if (ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &info) == 0 &&
            strncmp(info.label, "INT34BB", 7) == 0 &&
            info.lines > GX51_RESET_LINE)
            return fd;

        close(fd);
    }

    return -1;
}

int gx51_open_irq_gpio48(void)
{
    struct gpio_v2_line_request req = {0};
    int chip = gx51_open_int34bb();

    if (chip < 0)
        return -1;

    req.num_lines = 1;
    req.offsets[0] = GX51_EXPECTED_HWIRQ;
    req.config.flags = GPIO_V2_LINE_FLAG_INPUT;
    strncpy(req.consumer, "goodix51a0-irq", sizeof(req.consumer) - 1);

    if (ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &req) < 0 || req.fd < 0) {
        close(chip);
        return -1;
    }

    close(chip);
    return req.fd;
}

static int
gx51_wait_irq_gpio48_level(int line_fd, unsigned int timeout_ms, int want_high)
{
    struct gpio_v2_line_values val = {
        .bits = 0,
        .mask = 1,
    };
    unsigned int elapsed_ms;

    if (line_fd < 0 || timeout_ms == 0)
        return -1;

    for (elapsed_ms = 0; elapsed_ms < timeout_ms; elapsed_ms++) {
        val.bits = 0;
        val.mask = 1;
        if (ioctl(line_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &val) < 0)
            return -1;
        if (!!(val.bits & 1) == !!want_high)
            return 0;
        if (gx51_sleep_us(1000) < 0)
            return -1;
    }

    errno = ETIMEDOUT;
    return -1;
}

int gx51_wait_irq_gpio48(int line_fd, unsigned int timeout_ms)
{
    /* Match the proven Stage2E userspace path: sample GPIO48 every 1 ms and
     * only clock the SPI response after the level-high IRQ is observable. */
    return gx51_wait_irq_gpio48_level(line_fd, timeout_ms, 1);
}

int gx51_wait_irq_gpio48_low(int line_fd, unsigned int timeout_ms)
{
    /* A level-high IRQ can remain asserted briefly after a response body has
     * been drained.  Do not launch the next target command until the MCU has
     * visibly returned the line LOW. */
    return gx51_wait_irq_gpio48_level(line_fd, timeout_ms, 0);
}

int gx51_reset_gpio264(void)
{
    struct gpio_v2_line_request req = {0};
    struct gpio_v2_line_values val = {0};
    int chip = gx51_open_int34bb();

    if (chip < 0)
        return -1;

    req.num_lines = 1;
    req.offsets[0] = GX51_RESET_LINE;
    req.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
    strncpy(req.consumer, "goodix51a0", sizeof(req.consumer) - 1);

    if (ioctl(chip, GPIO_V2_GET_LINE_IOCTL, &req) < 0 || req.fd < 0) {
        close(chip);
        return -1;
    }

    val.mask = 1;
    val.bits = 1; /* HIGH: active reset */
    if (ioctl(req.fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &val) < 0)
        goto fail;
    if (gx51_sleep_us(300000) < 0)
        goto fail;

    val.bits = 0; /* LOW: MCU runs */
    if (ioctl(req.fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &val) < 0)
        goto fail;
    if (gx51_sleep_us(600000) < 0)
        goto fail;

    /* Final state deliberately remains LOW. */
    close(req.fd);
    close(chip);
    return 0;

fail:
    /* Fail closed for the experiment, but fail LOW electrically: once the line
     * has been acquired, every error path explicitly releases active-HIGH reset
     * before closing the GPIO request. */
    val.mask = 1;
    val.bits = 0;
    (void)ioctl(req.fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &val);
    close(req.fd);
    close(chip);
    return -1;
}
