
#ifndef GXFP_KERNEL_IRQ_RUNTIME_H
#define GXFP_KERNEL_IRQ_RUNTIME_H

#include "active_backend.h"
#include "gxfp_irq_wait_ioctl.h"

#include <stdbool.h>

struct gxfp_kernel_irq_runtime;
typedef int (*gxfp_kernel_irq_cancel_fn)(void *ctx);

struct gxfp_kernel_irq_runtime {
    int fd;
    struct gxfp_irq_wait_info info;
    gxfp_kernel_irq_cancel_fn cancel_fn;
    void *cancel_ctx;
    unsigned wait_count;
    unsigned event_count;
};

bool gxfp_kernel_irq_runtime_open(struct gxfp_kernel_irq_runtime *runtime,
                                  const char *path,
                                  gxfp_kernel_irq_cancel_fn cancel_fn,
                                  void *cancel_ctx);
void gxfp_kernel_irq_runtime_close(struct gxfp_kernel_irq_runtime *runtime);

void gxfp_kernel_irq_runtime_get_level_ops(
    struct gxfp_kernel_irq_runtime *runtime,
    struct gxfp_linux_level_ops *ops);

enum gxfp_io_result gxfp_kernel_irq_runtime_sleep_ms(void *ctx,
                                                     unsigned ms);

#endif
