#!/bin/bash
set -euo pipefail

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
preflight="$research_dir/linux/pio_preflight.sh"
wrapper="$research_dir/linux/pio_live_probe_supervisor.sh"

grep -Fq "PIO_PREFLIGHT=PASS" "$preflight"
grep -Fq "PXA2XX_PIO_FALLBACK=CONFIRMED" "$preflight"
grep -Fq "IDMA64_MODULE=ABSENT" "$preflight"

grep -Fq "PIO_CONFIRM_TOKEN='GXFP51A0_REVIEWED_PIO_20260902'" "$wrapper"
grep -Fq "COMMON_INIT_CONFIRM_TOKEN='GXFP51A0_REVIEWED_COMMON_INIT_20260902'" "$wrapper"

active_command_re='(^|[;&|][[:space:]]*)[[:space:]]*(sudo[[:space:]]+)?(modprobe|rmmod|insmod|devmem|setpci|gpioset)([[:space:]]|$)'

safe_sample='case "$cmdline" in *" modprobe.blacklist=idma64 "*) ;; esac'
unsafe_sample_1='modprobe idma64'
unsafe_sample_2='sudo rmmod idma64'
unsafe_sample_3='true && insmod bad.ko'

if printf '%s\n' "$safe_sample" | grep -Eq "$active_command_re"; then
    echo 'safety-test regression: modprobe.blacklist was misclassified as a command' >&2
    exit 1
fi

for sample in "$unsafe_sample_1" "$unsafe_sample_2" "$unsafe_sample_3"; do
    if ! printf '%s\n' "$sample" | grep -Eq "$active_command_re"; then
        echo "safety-test regression: active command not detected: $sample" >&2
        exit 1
    fi
done

if grep -En "$active_command_re" "$preflight" "$wrapper"; then
    echo 'safety violation: PIO gate executes a module/hardware command' >&2
    exit 1
fi

if grep -En \
'(^|[;&|][[:space:]]*)[[:space:]]*(sudo[[:space:]]+)?tee[[:space:]].*(/sys/|driver_override|/bind|/unbind|power/control)' \
"$preflight" "$wrapper"
then
    echo 'safety violation: PIO gate writes controller state through tee' >&2
    exit 1
fi

if grep -En \
'(>|>>)[[:space:]]*[^#]*(/sys/|driver_override|/bind|/unbind|power/control)' \
"$preflight" "$wrapper"
then
    echo 'safety violation: PIO gate writes controller state through redirection' >&2
    exit 1
fi

if grep -En \
'(^|[^A-Za-z0-9_])(ioremap|ioremap_wc|iowrite|writeb|writew|writel|writeq)([^A-Za-z0-9_]|$)' \
"$preflight" "$wrapper"
then
    echo 'safety violation: low-level write primitive found in PIO gate' >&2
    exit 1
fi

if grep -Ei \
'(UPFW|bootloader programming|firmware upload|firmware flash|firmware erase)' \
"$preflight" "$wrapper"
then
    echo 'safety violation: firmware-management flow found in PIO gate' >&2
    exit 1
fi

echo 'test_pio_source_safety: OK'
