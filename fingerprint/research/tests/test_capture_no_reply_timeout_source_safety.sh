#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_DRAIN_NO_REPLY_TIMEOUT_MS 1000' "$d"
grep -Fq 'GX_DRAIN_NO_REPLY_TIMEOUT_MS / GX_DRAIN_IRQ_POLL_MS' "$d"
grep -Fq 'if (!got && misses >= no_reply_miss_limit)' "$d"
echo 'test_capture_no_reply_timeout_source_safety: OK'
