#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
defs="$root/driver/goodix51a0/goodix51a0.h"
target="$root/driver/goodix51a0/gx51_target.c"
header="$root/driver/goodix51a0/gx51_target.h"
fpatch="$root/integration/fprintd-1.94.5-goodix51a0-s3/0001-goodix51a0-open-before-suspend.patch"

# rel72 deliberately moves Windows 0x60 sleep out of normal Close. Normal warm
# operation remains rel61/rel59/rel60; only the actual suspend callback parks the MCU.
grep -Fq '#define GOODIX_CMD_SLEEP       0x60' "$defs"
grep -Fq 'gxfp_build_sleep' "$target"
grep -Fq 'gxfp_build_sleep' "$header"
grep -Fq 'gx_sensor_sleep' "$driver"
grep -Fq 'GXFP51A0 S3_PARK' "$driver"

# The driver must not sleep on ordinary fp_device_close.
close_block="$(sed -n '/^gx_dev_close (FpDevice \*dev)/,/^static void$/p' "$driver")"
! grep -Fq 'gx_sensor_sleep' <<<"$close_block"

# The actual sleep park belongs to the suspend callback and forces a cold Claim/Open next time.
suspend_block="$(sed -n '/^gx_dev_suspend (FpDevice \*dev)/,/^static void$/p' "$driver")"
grep -Fq 'gx_sensor_sleep' <<<"$suspend_block"
grep -Fq 'fpi_device_suspend_complete' <<<"$suspend_block"
grep -Fq 'FP_DEVICE_ERROR_NOT_SUPPORTED' <<<"$suspend_block"
grep -Fq 'gx_transport_close' <<<"$suspend_block"

# fprintd rel72 makes the idle/closed case reachable by opening this exact driver before suspend.
test -s "$fpatch"
grep -Fq 'fp_device_get_driver' "$fpatch"
grep -Fq 'goodix51a0' "$fpatch"
grep -Fq 'fp_device_is_open' "$fpatch"
grep -Fq 'fp_device_open' "$fpatch"
grep -Fq 'fp_device_close' "$fpatch"
grep -Fq 'opened_for_sleep' "$fpatch"

# The obsolete stop/start sleep.target service must be gone.
! test -e "$root/integration/systemd/gxfp51a0-fprintd-suspend.service"

echo 'test_sleep_lifecycle_source_safety: OK (rel72 driver park + fprintd pre-open boundary)'
