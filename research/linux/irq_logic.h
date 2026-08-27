#ifndef GXFP_IRQ_LOGIC_H
#define GXFP_IRQ_LOGIC_H

#include <stdint.h>

enum gxfp_irq_result {
    GXFP_IRQ_OK = 0,
    GXFP_IRQ_TIMEOUT,
    GXFP_IRQ_CANCELLED,
    GXFP_IRQ_IO_ERROR,
    GXFP_IRQ_INVALID,
};

struct gxfp_irq_ops {
    void *ctx;
    int (*get_value)(void *ctx);
    int (*wait_rising)(void *ctx, int64_t timeout_ns);
    int (*consume_event)(void *ctx);
    int64_t (*monotonic_now_ns)(void *ctx);
    int (*is_cancelled)(void *ctx);
};

enum gxfp_irq_result
gxfp_irq_wait_high(const struct gxfp_irq_ops *ops,
                   int64_t deadline_ns);

#endif
