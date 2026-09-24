#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
block="$(sed -n '/^gx_warm_validate (/,/^}/p' "$driver")"
grep -Fq 'before_mean < GOODIX_FDT_ABS' <<<"$block"
grep -Fq 'WARM_REBASE deferred: finger already present' <<<"$block"
grep -Fq 'gx_capture_frame (self, fresh_bg, TRUE)' <<<"$block"
grep -Fq 'WARM_REBASE discarded: finger landed during' <<<"$block"
grep -Fq 'memcpy (self->bg_frame, fresh_bg' <<<"$block"
grep -Fq 'memcpy (self->fdt_base, after, sizeof self->fdt_base)' <<<"$block"
grep -Fq 'self->fdt_abs = after_mean - GOODIX_FDT_ABS_MARGIN' <<<"$block"
echo 'test_warm_rebase_source_safety: OK'
