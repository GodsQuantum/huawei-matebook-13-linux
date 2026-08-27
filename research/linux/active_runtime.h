#ifndef GXFP_LINUX_ACTIVE_RUNTIME_H
#define GXFP_LINUX_ACTIVE_RUNTIME_H

#include "active_backend.h"
#include "gpiod_irq.h"

#include <stdbool.h>

struct gxfp_linux_active_runtime;
typedef int (*gxfp_linux_cancel_fn)(void *ctx);

struct gxfp_linux_active_runtime {
    struct gxfp_gpiod_irq *irq;
    gxfp_linux_cancel_fn cancel_fn;
    void *cancel_ctx;
};

bool gxfp_linux_active_runtime_init(struct gxfp_linux_active_runtime *runtime,
                                    struct gxfp_gpiod_irq *irq,
                                    gxfp_linux_cancel_fn cancel_fn,
                                    void *cancel_ctx);

void gxfp_linux_active_runtime_get_level_ops(
    struct gxfp_linux_active_runtime *runtime,
    struct gxfp_linux_level_ops *ops);

enum gxfp_io_result gxfp_linux_active_runtime_sleep_ms(void *ctx,
                                                        unsigned ms);

#endif
