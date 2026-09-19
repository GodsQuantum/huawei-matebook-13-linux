#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'gx_dump_capture (self, px);' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_capture_frame (")
b=s.index("gx_cmp_dbl", a)
f=s[a:b]
assert "gx_dump_capture (self, px);" in f
assert "gx_send_capture_cleanup (self)" in f
assert f.index("gx_dump_capture (self, px);") < f.index("gx_send_capture_cleanup (self)")
a=s.index("gx_capture_features (")
b=s.index("gx_views_to_variant", a)
f2=s[a:b]
assert "gx_dump_capture (self, px);" not in f2
PY2
echo 'test_capture_dump_before_cleanup_source_safety: OK'
