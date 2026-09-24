#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

grep -q 'GXFP_FDT_ZONE_COUNT' "$driver"
header="$(dirname "$driver")/goodix51a0.h"
grep -Eq '^#define GOODIX_CMD_FDT_DOWN +0x32$' "$header"
grep -Eq '^#define GOODIX_CMD_FDT_UP +0x34$' "$header"
grep -Eq '^#define GOODIX_CMD_FDT_MODE +0x36$' "$header"
grep -q 'gxfp_build_fdt_probe' "$driver"
grep -q 'gxfp_parse_fdt_response' "$driver"
grep -Fq '#define GX_FDT_TOUCH_MIN_ZONES 5' "$driver"
grep -Fq 'gx_fdt_touch_count' "$driver"
grep -Fq 'gx_fdt_touch_is_finger' "$driver"
grep -Fq 'touchflag & 0x3fu' "$driver"
grep -Fq 'gx_fdt_touch_is_finger (touchflag) ||' "$driver"
grep -Fq '!gx_fdt_touch_is_finger (touchflag)' "$driver"
grep -Fq 'return d / (int) GXFP_FDT_ZONE_COUNT;' "$driver"
if grep -q '0x36,0x23' "$driver"; then
  echo 'safety violation: legacy 34-byte FDT command remains in runtime' >&2
  exit 1
fi
echo 'test_fdt_runtime_source_safety: OK'
