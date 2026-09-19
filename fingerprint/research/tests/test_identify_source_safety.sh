#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()

assert "gx_score_probe_against_print" in s
assert "fpi_device_get_identify_data (dev, &gallery)" in s
assert "fpi_device_identify_report (dev," in s
assert "fpi_device_identify_complete (dev" in s
assert "gx_dev_identify (FpDevice *dev)" in s
assert "dev_class->identify = gx_dev_identify;" in s

a=s.index("else if (t->verifying)")
b=s.index("else\n        {", a)
auth=s[a:b]
assert "t->identifying" in auth
assert "GX_MATCH_THRESHOLD" in auth
assert "gx_score_probe_against_print" in auth
assert "fpi_device_identify_report" in auth
assert "fpi_device_verify_report" in auth

a=s.index("gx_dev_identify (")
b=s.index("/* ------------------------------------------------------------------ */", a)
identify=s[a:b]
assert "t->verifying = TRUE" in identify
assert "t->identifying = TRUE" in identify
assert "gx_identify_done" in identify
PY2

echo 'test_identify_source_safety: OK'
