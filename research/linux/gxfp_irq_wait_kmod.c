
// SPDX-License-Identifier: GPL-2.0-only
#include "gxfp_irq_wait_ioctl.h"

#include <linux/acpi.h>
#include <linux/atomic.h>
#include <linux/fs.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/irq.h>
#include <linux/jiffies.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <linux/wait.h>
#include <acpi/acpi_bus.h>

#define GXFP_HID "GXFP51A0"
#define GXFP_UID "1"
#define GXFP_EXPECTED_HWIRQ 48UL
#define GXFP_MAX_WAIT_MS 2000U

struct gxfp_irq_wait_state {
    int irq;
    unsigned long hwirq;
    unsigned int trigger_type;
    wait_queue_head_t waitq;
    atomic_t sequence;
    atomic_t armed;
    atomic_t opened;
    struct mutex wait_lock;
};

static struct gxfp_irq_wait_state g_state;

static irqreturn_t gxfp_irq_wait_handler(int irq, void *dev_id)
{
    struct gxfp_irq_wait_state *state = dev_id;

    if (irq != state->irq)
        return IRQ_NONE;

    if (atomic_cmpxchg(&state->armed, 1, 0) != 1)
        return IRQ_NONE;

    disable_irq_nosync(state->irq);
    atomic_inc(&state->sequence);
    wake_up_interruptible(&state->waitq);
    return IRQ_HANDLED;
}

static int gxfp_irq_wait_open(struct inode *inode, struct file *file)
{
    (void)inode;
    (void)file;

    if (atomic_cmpxchg(&g_state.opened, 0, 1) != 0)
        return -EBUSY;
    return 0;
}

static int gxfp_irq_wait_release(struct inode *inode, struct file *file)
{
    (void)inode;
    (void)file;

    if (atomic_xchg(&g_state.armed, 0) == 1)
        disable_irq(g_state.irq);
    atomic_set(&g_state.opened, 0);
    return 0;
}

static long gxfp_irq_wait_ioctl(struct file *file,
                                unsigned int cmd,
                                unsigned long arg)
{
    void __user *user = (void __user *)arg;

    (void)file;

    if (cmd == GXFP_IRQ_WAIT_GET_INFO) {
        struct gxfp_irq_wait_info info = {
            .linux_irq = (u32)g_state.irq,
            .trigger_type = g_state.trigger_type,
            .hwirq = (u64)g_state.hwirq,
        };

        return copy_to_user(user, &info, sizeof(info)) ? -EFAULT : 0;
    }

    if (cmd == GXFP_IRQ_WAIT_WAIT) {
        struct gxfp_irq_wait_request req;
        unsigned int before;
        long waited;
        int rc = 0;

        if (copy_from_user(&req, user, sizeof(req)))
            return -EFAULT;
        if (req.timeout_ms == 0 || req.timeout_ms > GXFP_MAX_WAIT_MS)
            return -EINVAL;

        if (mutex_lock_interruptible(&g_state.wait_lock))
            return -ERESTARTSYS;

        before = (unsigned int)atomic_read(&g_state.sequence);
        atomic_set(&g_state.armed, 1);
        enable_irq(g_state.irq);

        waited = wait_event_interruptible_timeout(
            g_state.waitq,
            (unsigned int)atomic_read(&g_state.sequence) != before,
            msecs_to_jiffies(req.timeout_ms));

        if (waited <= 0) {
            if (atomic_xchg(&g_state.armed, 0) == 1)
                disable_irq(g_state.irq);
            rc = waited == 0 ? -ETIMEDOUT : (int)waited;
            goto out_unlock;
        }

        req.sequence = (u32)atomic_read(&g_state.sequence);
        if (copy_to_user(user, &req, sizeof(req)))
            rc = -EFAULT;

out_unlock:
        mutex_unlock(&g_state.wait_lock);
        return rc;
    }

    return -ENOTTY;
}

static const struct file_operations gxfp_irq_wait_fops = {
    .owner = THIS_MODULE,
    .open = gxfp_irq_wait_open,
    .release = gxfp_irq_wait_release,
    .unlocked_ioctl = gxfp_irq_wait_ioctl,
#ifdef CONFIG_COMPAT
    .compat_ioctl = gxfp_irq_wait_ioctl,
#endif
};

static struct miscdevice gxfp_irq_wait_misc = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = "gxfp_irq_wait",
    .fops = &gxfp_irq_wait_fops,
    .mode = 0600,
};

static int __init gxfp_irq_wait_init(void)
{
    struct acpi_device *adev;
    struct irq_data *data;
    int irq;
    int rc;

    memset(&g_state, 0, sizeof(g_state));
    g_state.irq = -1;
    init_waitqueue_head(&g_state.waitq);
    mutex_init(&g_state.wait_lock);
    atomic_set(&g_state.sequence, 0);
    atomic_set(&g_state.armed, 0);
    atomic_set(&g_state.opened, 0);

    adev = acpi_dev_get_first_match_dev(GXFP_HID, GXFP_UID, -1);
    if (!adev)
        return -ENODEV;

    irq = acpi_dev_gpio_irq_get(adev, 0);
    acpi_dev_put(adev);
    if (irq < 0)
        return irq;

    data = irq_get_irq_data(irq);
    if (!data)
        return -ENODEV;

    g_state.irq = irq;
    g_state.hwirq = (unsigned long)data->hwirq;
    g_state.trigger_type = irqd_get_trigger_type(data);

    if (g_state.hwirq != GXFP_EXPECTED_HWIRQ ||
        g_state.trigger_type != IRQ_TYPE_LEVEL_HIGH) {
        pr_err("gxfp_irq_wait: ACPI IRQ contract mismatch hwirq=%lu trigger=0x%x\n",
               g_state.hwirq, g_state.trigger_type);
        return -EINVAL;
    }

    rc = request_irq(g_state.irq,
                     gxfp_irq_wait_handler,
                     IRQF_NO_AUTOEN,
                     "gxfp-irq-wait",
                     &g_state);
    if (rc)
        return rc;

    rc = misc_register(&gxfp_irq_wait_misc);
    if (rc) {
        free_irq(g_state.irq, &g_state);
        return rc;
    }

    pr_info("gxfp_irq_wait: ready irq=%d hwirq=%lu trigger=0x%x\n",
            g_state.irq, g_state.hwirq, g_state.trigger_type);
    return 0;
}

static void __exit gxfp_irq_wait_exit(void)
{
    misc_deregister(&gxfp_irq_wait_misc);
    if (g_state.irq >= 0) {
        if (atomic_xchg(&g_state.armed, 0) == 1)
            disable_irq(g_state.irq);
        free_irq(g_state.irq, &g_state);
    }
    pr_info("gxfp_irq_wait: unloaded\n");
}

module_init(gxfp_irq_wait_init);
module_exit(gxfp_irq_wait_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("GXFP51A0 Linux research");
MODULE_DESCRIPTION("Reviewed ACPI level-high IRQ wait bridge for GXFP51A0 probe research");
