
#ifndef GXFP_IRQ_WAIT_IOCTL_H
#define GXFP_IRQ_WAIT_IOCTL_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define GXFP_IRQ_WAIT_IOC_MAGIC 0xF5

struct gxfp_irq_wait_info {
    __u32 linux_irq;
    __u32 trigger_type;
    __u64 hwirq;
};

struct gxfp_irq_wait_request {
    __u32 timeout_ms;
    __u32 sequence;
};

#define GXFP_IRQ_WAIT_GET_INFO \
    _IOR(GXFP_IRQ_WAIT_IOC_MAGIC, 0x01, struct gxfp_irq_wait_info)
#define GXFP_IRQ_WAIT_WAIT \
    _IOWR(GXFP_IRQ_WAIT_IOC_MAGIC, 0x02, struct gxfp_irq_wait_request)

#endif
