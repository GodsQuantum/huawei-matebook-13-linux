#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"
grep -Fq '(body[0] == 0x20u || body[0] == 0xaeu) ? 12 : 25' "$d"
grep -Fq 'if (!got && misses >= no_reply_miss_limit)' "$d"
echo 'test_capture_no_reply_timeout_source_safety: OK'
