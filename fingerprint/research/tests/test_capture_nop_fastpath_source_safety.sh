#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq 'if (body[0] == 0x00u)' "$driver"
grep -Fq 'drain cmd=00: no ACK expected; skip silence wait' "$driver"
grep -Fq 'g_usleep (GX_SEQ_GAP_US);' "$driver"
echo 'test_capture_nop_fastpath_source_safety: OK'
