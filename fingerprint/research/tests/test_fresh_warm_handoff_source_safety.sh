#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/driver/goodix51a0/goodix51a0.c"

# rel39: never skip readiness validation merely because the previous Claim
# closed recently. Closing host SPI/IRQ fds is a lifecycle boundary for the
# transport; retained TLS/background/FDT may be reused only after gx_warm_validate.
! grep -Fq 'warm_handoff_ready' "$src"
! grep -Fq 'GX_WARM_HANDOFF_TTL_US' "$src"
! grep -Fq 'gx_warm_consume_fresh_handoff' "$src"
! grep -Fq 'skipping redundant background GET_IMAGE' "$src"

open_block="$(sed -n '/gx_dev_open (FpDevice \*dev)/,/^}/p' "$src")"
grep -Fq 'if (gx_warm_available (self))' <<<"$open_block"
grep -Fq 'if (gx_warm_validate (self))' <<<"$open_block"
grep -Fq 'warm context failed full readiness validation; falling back to cold preparation' <<<"$open_block"

close_block="$(sed -n '/gx_dev_close (FpDevice \*dev)/,/^}/p' "$src")"
grep -Fq 'next open must validate FDT + GET_IMAGE/TLS' <<<"$close_block"

echo 'test_fresh_warm_handoff_source_safety: OK (blind handoff disabled)'
