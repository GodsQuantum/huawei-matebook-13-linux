#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/driver/goodix51a0/goodix51a0.c"

# Never skip readiness validation merely because the previous Claim closed recently.
! grep -Fq 'warm_handoff_ready' "$src"
! grep -Fq 'GX_WARM_HANDOFF_TTL_US' "$src"
! grep -Fq 'gx_warm_consume_fresh_handoff' "$src"
! grep -Fq 'skipping redundant background GET_IMAGE' "$src"

open_block="$(sed -n '/gx_dev_open (FpDevice \*dev)/,/^}/p' "$src")"
grep -Fq 'if (gx_warm_available (self))' <<<"$open_block"
grep -Fq 'self->sensor_sleeping && !gx_wakeup_mcu (self)' <<<"$open_block"
grep -Fq 'gx_warm_validate (self)' <<<"$open_block"
grep -Fq 'warm context failed full readiness validation; falling back to cold preparation' <<<"$open_block"

close_block="$(sed -n '/gx_dev_close (FpDevice \*dev)/,/^}/p' "$src")"
grep -Fq 'gx_sensor_sleep (self)' <<<"$close_block"
grep -Fq 'stashed warm context with MCU in Windows deactivate sleep' <<<"$close_block"

echo 'test_fresh_warm_handoff_source_safety: OK (sleep/wake handoff still validated)'
