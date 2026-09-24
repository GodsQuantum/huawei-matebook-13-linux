#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

grep -q '^gx_take_tls_frame ' "$driver"
grep -q '^gx_send_capture_cleanup ' "$driver"
cleanup="$(sed -n '/^gx_send_capture_cleanup (/,/^}/p' "$driver")"
grep -q 'gxfp_build_capture_cleanup_recipe' <<<"$cleanup"
grep -q 'gx_tls_decrypt_record' <<<"$cleanup"

# Ordinary finger captures keep the historical one-frame + cleanup contract.
wrapper="$(sed -n '/^gx_capture_frame (/,/^}/p' "$driver")"
grep -Fq 'gx_capture_frame_ex (self, px, background, TRUE)' <<<"$wrapper"

# Same-press Verify/Identify deliberately defers cleanup, but must perform it exactly
# once before returning the best probe to libfprint.
same_press="$(sed -n '/^gx_capture_auth_same_press (/,/^}/p' "$driver")"
grep -Fq 'gx_capture_frame_ex (self, px, FALSE, FALSE)' <<<"$same_press"
grep -Fq 'gx_send_capture_cleanup (self)' <<<"$same_press"
grep -Fq 'gx_capture_pacing_success (self)' <<<"$same_press"

echo 'test_capture_cleanup_runtime_source_safety: OK'
