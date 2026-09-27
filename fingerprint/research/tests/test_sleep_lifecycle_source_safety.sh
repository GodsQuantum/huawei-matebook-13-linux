#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
target="$root/driver/goodix51a0/gx51_target.c"
header="$root/driver/goodix51a0/gx51_target.h"

# rel57's experimental Windows SLEEP-on-close path was never exercised during
# the reported S3 failure and is removed from rel58 to keep the validated rel50
# sensor lifecycle. No hidden power-mode state may survive this rollback.
! grep -Fq 'GOODIX_CMD_SLEEP' "$driver"
! grep -Fq 'gx_sensor_sleep' "$driver"
! grep -Fq 'sensor_sleeping' "$driver"
! grep -Fq 'Windows sleep transition' "$driver"
! grep -Fq 'gxfp_build_sleep' "$target"
! grep -Fq 'gxfp_build_sleep' "$header"

# Normal close still retains only the already validated warm TLS/background/FDT
# context, and the next open must actively validate it.
close_block="$(sed -n '/gx_dev_close (FpDevice \*dev)/,/^}/p' "$driver")"
grep -Fq 'stashed native warm context across fp_device close' <<<"$close_block"
grep -Fq 'next open must validate FDT + GET_IMAGE/TLS' <<<"$close_block"

echo 'test_sleep_lifecycle_source_safety: OK (experimental sensor sleep path absent)'
