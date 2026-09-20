#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"
grep -Fq 'int top[5] = { 0, 0, 0, 0, 0 };' "$d"
grep -Fq 'gallery scores: %d@%u %d@%u %d@%u %d@%u %d@%u (views=%u)' "$d"
grep -Fq '#define GX_MATCH_THRESHOLD            7' "$d"
grep -Fq 'GXFP_MATCH_DIAGNOSTICS' "$d"
echo 'test_gallery_diagnostic_source_safety: OK'
