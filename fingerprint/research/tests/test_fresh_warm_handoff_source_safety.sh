#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq 'warm_handoff_ready' "$src"
grep -Fq '#define GX_WARM_HANDOFF_TTL_US (10 * G_USEC_PER_SEC)' "$src"
grep -Fq 'gx_warm_consume_fresh_handoff' "$src"
grep -Fq 'self->warm_handoff_ready = FALSE;' "$src"
grep -Fq 'self->warm_handoff_ready = !self->capture_recovery_pending;' "$src"
grep -Fq 'skipping redundant background GET_IMAGE' "$src"

open_block="$(sed -n '/gx_dev_open (FpDevice \*dev)/,/^}/p' "$src")"
grep -Fq 'if (gx_warm_consume_fresh_handoff (self))' <<<"$open_block"
grep -Fq 'if (gx_warm_validate (self))' <<<"$open_block"

handoff_line="$(grep -n 'if (gx_warm_consume_fresh_handoff (self))' "$src" | head -1 | cut -d: -f1)"
validate_line="$(grep -n 'if (gx_warm_validate (self))' "$src" | tail -1 | cut -d: -f1)"
[[ "$handoff_line" -lt "$validate_line" ]]

echo 'test_fresh_warm_handoff_source_safety: OK'
