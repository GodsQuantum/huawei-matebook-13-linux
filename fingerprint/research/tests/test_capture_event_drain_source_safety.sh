#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"
grep -Fq 'case 0x32u: expected_plain_replies = 1' "$d"
grep -Fq 'case 0x36u: expected_plain_replies = 2' "$d"
grep -Fq 'case 0x50u: expected_plain_replies = 2' "$d"
grep -Fq 'case 0x80u: expected_plain_replies = 1' "$d"
grep -Fq 'case 0x82u: expected_plain_replies = 2' "$d"
grep -Fq 'case 0xaeu: expected_plain_replies = 2' "$d"
grep -Fq 'expected %d replies received; finish' "$d"
echo 'test_capture_event_drain_source_safety: OK'
