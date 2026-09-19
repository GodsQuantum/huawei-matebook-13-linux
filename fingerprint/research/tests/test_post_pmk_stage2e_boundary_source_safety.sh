#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'gx_read_fw_version_stage2e' "$driver"
grep -Fq 'GXFP51A0 Stage2E A8 ACK accepted' "$driver"
grep -Fq 'GXFP51A0 Stage2E A8 response accepted' "$driver"
grep -Fq 'gx_read_fw_version_stage2e (self, fw, sizeof fw)' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_read_fw_version_stage2e (")
b=s.index("gx_target_soft_reset (", a)
f=s[a:b]
assert "GX_AMORCE" not in f
assert "gx_write_frame (self, GOODIX_PKT_PLAIN, a8, sizeof a8)" in f
assert "g_usleep (8000 * self->timing_scale / 100)" in f
PY2
echo 'test_post_pmk_stage2e_boundary_source_safety: OK'
