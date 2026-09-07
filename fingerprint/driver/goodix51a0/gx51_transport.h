#pragma once
#include <stddef.h>
#include <stdint.h>

#define GX51_MAX_FRAME 65535u
#define GX51_RESET_LINE 264u
#define GX51_EXPECTED_HWIRQ 48u

struct gx51_outer {
    uint8_t type;
    uint8_t len_lo;
    uint8_t len_hi;
    uint8_t checksum;
};

int gx51_make_outer(uint8_t type, size_t len, struct gx51_outer *out);
uint8_t gx51_body_checksum(const uint8_t *data, size_t len);
int gx51_write_frame_fd(int spi_fd, uint8_t type,
                        const uint8_t *body, size_t len);
int gx51_read_frame_fd(int spi_fd, int irq_fd, uint8_t *type,
                       uint8_t *body, size_t capacity, size_t *body_len);
int gx51_reset_gpio264(void);
