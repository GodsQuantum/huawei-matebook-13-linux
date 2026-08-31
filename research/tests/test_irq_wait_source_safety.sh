#!/bin/sh
set -eu

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kmod="$research_dir/linux/gxfp_irq_wait_kmod.c"
runtime="$research_dir/linux/kernel_irq_runtime.c"
probe="$research_dir/linux/probe_runtime.c"
supervisor="$research_dir/linux/live_probe_supervisor.sh"

grep -q 'acpi_dev_gpio_irq_get(adev, 0)' "$kmod"
grep -q 'GXFP_EXPECTED_HWIRQ 48UL' "$kmod"
grep -q 'IRQ_TYPE_LEVEL_HIGH' "$kmod"
grep -q 'IRQF_NO_AUTOEN' "$kmod"
grep -q 'disable_irq_nosync' "$kmod"
grep -q 'wait_event_interruptible_timeout' "$kmod"
grep -q 'GXFP_MAX_WAIT_MS 2000U' "$kmod"
grep -q '"/dev/gxfp_irq_wait"' "$probe"
grep -q 'IRQ_SOURCE=KERNEL_ACPI_GPIOINT' "$probe"
grep -q "CONFIRM_TOKEN='GXFP51A0_REVIEWED_PROBE_4'" "$supervisor"

if grep -Eq 'IRQF_TRIGGER_(RISING|FALLING|HIGH|LOW)|irq_set_irq_type' "$kmod"; then
    echo 'safety violation: module overrides firmware IRQ trigger configuration' >&2
    exit 1
fi

if grep -Eqi 'spi_(sync|write|read|transfer|register)|gpiod_|gpio_(request|set)|acpi_evaluate|pm_runtime|dev_pm|ioremap|memremap|outb|UPFW|erase_firmware|update_firmware|bootloader' "$kmod"; then
    echo 'safety violation: unrelated hardware primitive in IRQ bridge' >&2
    exit 1
fi

if grep -Eq '(^|[^0-9])156([^0-9]|$)' "$kmod" "$runtime" "$probe"; then
    echo 'safety violation: dynamic Linux IRQ number hardcoded' >&2
    exit 1
fi

if grep -q 'gxfp_gpiod_irq' "$probe"; then
    echo 'safety violation: Probe4 still polls GPIO48 through libgpiod' >&2
    exit 1
fi

echo 'test_irq_wait_source_safety: OK'
