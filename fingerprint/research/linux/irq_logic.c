#include "irq_logic.h"

enum gxfp_irq_result
gxfp_irq_wait_high(const struct gxfp_irq_ops *ops,
                   int64_t deadline_ns)
{
    int value;

    if (!ops || !ops->get_value || !ops->wait_rising ||
        !ops->consume_event || !ops->monotonic_now_ns ||
        !ops->is_cancelled || deadline_ns < 0)
        return GXFP_IRQ_INVALID;

    for (;;) {
        int64_t now;
        int64_t remaining;
        int wait_result;

        if (ops->is_cancelled(ops->ctx))
            return GXFP_IRQ_CANCELLED;

        value = ops->get_value(ops->ctx);
        if (value < 0)
            return GXFP_IRQ_IO_ERROR;
        if (value > 0)
            return GXFP_IRQ_OK;

        now = ops->monotonic_now_ns(ops->ctx);
        if (now < 0)
            return GXFP_IRQ_IO_ERROR;
        if (now >= deadline_ns)
            return GXFP_IRQ_TIMEOUT;

        remaining = deadline_ns - now;
        wait_result = ops->wait_rising(ops->ctx, remaining);
        if (wait_result < 0)
            return GXFP_IRQ_IO_ERROR;
        if (wait_result == 0)
            return GXFP_IRQ_TIMEOUT;

        if (ops->consume_event(ops->ctx) < 0)
            return GXFP_IRQ_IO_ERROR;
    }
}
