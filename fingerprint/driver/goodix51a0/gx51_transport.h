/* SPDX-License-Identifier: LGPL-2.1-or-later */
#pragma once
#include <stddef.h>
#include <stdint.h>

#define GX51_MAX_FRAME 65535u
#define GX51_RESET_LINE 264u
#define GX51_EXPECTED_HWIRQ 48u
#define GX51_SPI_READ_CHUNK_MAX 4096u

struct gx51_outer {
    uint8_t type;
    uint8_t len_lo;
    uint8_t len_hi;
    uint8_t checksum;
};

int gx51_make_outer(uint8_t type, size_t len, struct gx51_outer *out);
uint8_t gx51_body_checksum(const uint8_t *data, size_t len);
size_t gx51_read_chunk_size(size_t remaining);
int gx51_write_frame_fd(int spi_fd, uint8_t type,
                        const uint8_t *body, size_t len);
int gx51_open_irq_gpio48(void);
int gx51_wait_irq_gpio48(int line_fd, unsigned int timeout_ms);
int gx51_wait_irq_gpio48_low(int line_fd, unsigned int timeout_ms);
int gx51_read_frame_fd(int spi_fd, int irq_gpio_fd, uint8_t *type,
                       uint8_t *body, size_t capacity, size_t *body_len);
int gx51_reset_gpio264(void);
