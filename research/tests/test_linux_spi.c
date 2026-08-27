#include "linux/linux_spi.h"

#include <assert.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct fake_spi_state {
    int open_calls;
    int close_calls;
    int ioctl_calls;
    int message_calls;
    int fd;
    uint8_t mode;
    uint8_t bits;
    uint32_t speed;
    int force_bad_readback;
    size_t last_transfer_len;
    uintptr_t last_tx;
    uintptr_t last_rx;
};

static struct fake_spi_state *g_state;

static int fake_open(const char *path, int flags)
{
    (void)flags;
    assert(strcmp(path, "/dev/spidev9.7") == 0);
    g_state->open_calls++;
    return g_state->fd;
}

static int fake_close(int fd)
{
    assert(fd == g_state->fd);
    g_state->close_calls++;
    return 0;
}

static int fake_ioctl(int fd, unsigned long request, void *arg)
{
    assert(fd == g_state->fd);
    g_state->ioctl_calls++;

    if (request == SPI_IOC_WR_MODE) {
        g_state->mode = *(uint8_t *)arg;
        return 0;
    }
    if (request == SPI_IOC_RD_MODE) {
        *(uint8_t *)arg = g_state->force_bad_readback ? 1u : g_state->mode;
        return 0;
    }
    if (request == SPI_IOC_WR_BITS_PER_WORD) {
        g_state->bits = *(uint8_t *)arg;
        return 0;
    }
    if (request == SPI_IOC_RD_BITS_PER_WORD) {
        *(uint8_t *)arg = g_state->bits;
        return 0;
    }
    if (request == SPI_IOC_WR_MAX_SPEED_HZ) {
        g_state->speed = *(uint32_t *)arg;
        return 0;
    }
    if (request == SPI_IOC_RD_MAX_SPEED_HZ) {
        *(uint32_t *)arg = g_state->speed;
        return 0;
    }
    if (request == SPI_IOC_MESSAGE(1)) {
        struct spi_ioc_transfer *xfer = arg;
        g_state->message_calls++;
        g_state->last_transfer_len = xfer->len;
        g_state->last_tx = (uintptr_t)xfer->tx_buf;
        g_state->last_rx = (uintptr_t)xfer->rx_buf;
        assert(xfer->speed_hz == GXFP_SPI_MAX_SPEED_HZ);
        assert(xfer->bits_per_word == GXFP_SPI_BITS_PER_WORD);
        return (int)xfer->len;
    }

    assert(!"unexpected ioctl");
    return -1;
}

static const struct gxfp_spi_ops fake_ops = {
    .open_fn = fake_open,
    .close_fn = fake_close,
    .ioctl_fn = fake_ioctl,
};

static void reset_state(struct fake_spi_state *state)
{
    memset(state, 0, sizeof(*state));
    state->fd = 42;
    g_state = state;
}

static void test_open_is_configuration_only(void)
{
    struct fake_spi_state state;
    struct gxfp_spi spi;
    reset_state(&state);

    assert(gxfp_spi_open_configure(&spi, "/dev/spidev9.7", &fake_ops) == 0);
    assert(state.open_calls == 1);
    assert(state.message_calls == 0);
    assert(state.mode == GXFP_SPI_MODE);
    assert(state.bits == GXFP_SPI_BITS_PER_WORD);
    assert(state.speed == GXFP_SPI_MAX_SPEED_HZ);
    assert(spi.transfer_count == 0);
    assert(spi.fd == 42);

    gxfp_spi_close(&spi);
    assert(state.close_calls == 1);
}

static void test_bad_readback_closes(void)
{
    struct fake_spi_state state;
    struct gxfp_spi spi;
    reset_state(&state);
    state.force_bad_readback = 1;

    assert(gxfp_spi_open_configure(&spi, "/dev/spidev9.7", &fake_ops) != 0);
    assert(state.message_calls == 0);
    assert(state.close_calls == 1);
    assert(spi.fd == -1);
}

static void test_write_exact_is_one_transfer(void)
{
    struct fake_spi_state state;
    struct gxfp_spi spi;
    const uint8_t data[4] = {1, 2, 3, 4};
    reset_state(&state);

    assert(gxfp_spi_open_configure(&spi, "/dev/spidev9.7", &fake_ops) == 0);
    assert(gxfp_spi_write_exact(&spi, data, sizeof(data)) == 0);
    assert(state.message_calls == 1);
    assert(state.last_transfer_len == sizeof(data));
    assert(state.last_tx == (uintptr_t)data);
    assert(state.last_rx == 0);
    assert(spi.transfer_count == 1);
    gxfp_spi_close(&spi);
}

static void test_read_exact_is_one_transfer(void)
{
    struct fake_spi_state state;
    struct gxfp_spi spi;
    uint8_t data[7] = {0};
    reset_state(&state);

    assert(gxfp_spi_open_configure(&spi, "/dev/spidev9.7", &fake_ops) == 0);
    assert(gxfp_spi_read_exact(&spi, data, sizeof(data)) == 0);
    assert(state.message_calls == 1);
    assert(state.last_transfer_len == sizeof(data));
    assert(state.last_tx == 0);
    assert(state.last_rx == (uintptr_t)data);
    assert(spi.transfer_count == 1);
    gxfp_spi_close(&spi);
}

int main(void)
{
    test_open_is_configuration_only();
    test_bad_readback_closes();
    test_write_exact_is_one_transfer();
    test_read_exact_is_one_transfer();
    puts("test_linux_spi: OK");
    return 0;
}
