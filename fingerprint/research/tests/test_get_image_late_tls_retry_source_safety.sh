#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'GET_IMAGE ACK arrived but TLS image timed out; retrying once' "$driver"
grep -Fq 'gx_retry_get_image_after_tls_timeout' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_retry_get_image_after_tls_timeout (")
b=s.index("gx_send_capture_cleanup (", a)
f=s[a:b]
assert "gxfp_build_get_image" in f
assert "gx_send_plain_drain" in f
assert "gx_take_tls_frame" in f
assert "GET_IMAGE ACK arrived but TLS image timed out; retrying once" in f
assert "GET_IMAGE retry received no TLS image" in f
assert "gx_capture_transport_desync (self)" in f
assert "capture_recovery_pending" in f
a=s.index("gx_capture_frame_ex (")
b=s.index("gx_cmp_dbl", a)
f=s[a:b]
assert "gx_retry_get_image_after_tls_timeout (self, rec, GOODIX_RX_MAX)" in f
PY2
echo 'test_get_image_late_tls_retry_source_safety: OK'
