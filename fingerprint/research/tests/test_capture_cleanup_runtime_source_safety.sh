#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

grep -q '^gx_take_tls_frame ' "$driver"
grep -q '^gx_send_capture_cleanup ' "$driver"
cleanup="$(sed -n '/^gx_send_capture_cleanup (/,/^}/p' "$driver")"
grep -q 'gxfp_build_capture_cleanup_recipe' <<<"$cleanup"
grep -q 'gx_tls_decrypt_record' <<<"$cleanup"
grep -Fq 'if (!background && !gx_send_capture_cleanup (self))' "$driver"
echo 'test_capture_cleanup_runtime_source_safety: OK'
