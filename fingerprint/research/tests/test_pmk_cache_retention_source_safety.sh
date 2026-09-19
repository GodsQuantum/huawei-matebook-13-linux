#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'gx_factory_acquire_staging_pmk (FpiDeviceGoodix51A0 *self, gboolean allow_cache)' "$driver"
grep -Fq 'if (allow_cache && gx_pmk_cache_load (self))' "$driver"
grep -Fq 'gx_upload_config_and_reqtls (FpiDeviceGoodix51A0 *self, gboolean allow_cache)' "$driver"
grep -Fq 'cached PMK retained after failed session' "$driver"
grep -Fq 'trying fresh staging without deleting validated cache' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_tls_session (")
b=s.index("gx_session_start (", a)
f=s[a:b]
assert "gx_pmk_cache_invalidate" not in f
assert "gx_upload_config_and_reqtls (self, TRUE)" in f
assert "gx_upload_config_and_reqtls (self, FALSE)" in f
assert 'g_getenv ("GXFP_DIAGNOSTIC_ONESHOT")' in f
PY2
echo 'test_pmk_cache_retention_source_safety: OK'
