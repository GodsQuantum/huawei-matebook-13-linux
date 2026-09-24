#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_FDT_PROBE_ATTEMPTS 3' "$driver"
grep -Fq '#define GX_FDT_IRQ_TIMEOUT_MS 100' "$driver"
grep -Fq 'FDT probe retry: stage=%s attempt=%d/%d' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_fdt_probe_ex (")
b=s.index("gx_fdt_mean", a)
f=s[a:b]
assert "GX_FDT_PROBE_ATTEMPTS" in f
assert "for (attempt = 1; attempt <= GX_FDT_PROBE_ATTEMPTS; attempt++)" in f
assert "gx51_wait_irq_gpio48 (self->irq_fd, GX_FDT_IRQ_TIMEOUT_MS)" in f
assert "gxfp_parse_ack" in f
assert "gxfp_parse_fdt_response" in f
assert "out_touchflag" in f
assert "*out_touchflag = touchflag" in f
assert "stage = \"ack\"" in f
assert "stage = \"response\"" in f
assert "return 0;" in f
PY2
echo 'test_fdt_probe_retry_source_safety: OK'
