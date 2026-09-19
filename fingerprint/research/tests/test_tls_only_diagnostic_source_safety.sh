#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'GXFP_DIAGNOSTIC_TLS_ONLY' "$driver"
grep -Fq 'TLS-only diagnostic complete' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_session_thread (")
b=s.index("gx_capture_thread (", a)
f=s[a:b]
assert "gx_tls_session" in f
assert "gx_session_start" in f
PY2
echo 'test_tls_only_diagnostic_source_safety: OK'
