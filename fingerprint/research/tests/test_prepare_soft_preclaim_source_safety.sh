#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()

assert "#define GX_PREPARE_ATTEMPTS 2" in s
assert "gx_prepare_capture_context_once (" in s
assert "gx_recover_capture_context (" in s

a=s.index("gx_prepare_capture_context (")
b=s.index("gx_session_start (", a)
wrapper=s[a:b]
assert "GX_PREPARE_ATTEMPTS" in wrapper
assert "gx_prepare_capture_context_once (self, FALSE)" in wrapper
assert "gx_recover_capture_context (self)" in wrapper

a=s.index("gx_dev_open (")
b=s.index("gx_dev_close (", a)
op=s[a:b]
assert "gx_prepare_capture_context_once (self, FALSE)" in op
assert "deferring clean preparation to the biometric action" in op
assert "fpi_device_open_complete (dev, NULL)" in op
assert "GXFP51A0 could not prepare a clean capture context" not in op
# A transient prewarm miss must not destroy trusted PMK state or close handles.
tail=op[op.index("gx_prepare_capture_context_once (self, FALSE)"):]
assert "gx_pmk_clear (self)" not in tail
assert "close (self->spi_fd)" not in tail
assert "close (self->irq_fd)" not in tail

a=s.index("gx_recover_capture_context (")
b=s.index("gx_prepare_capture_context (", a)
recovery=s[a:b]
assert "gx_tls_teardown (self)" in recovery
assert "gx_gpio_reset (self)" in recovery
assert "gx_read_fw_version_stage2e" in recovery
assert "gx_pmk_clear" not in recovery
PY2

echo 'test_prepare_soft_preclaim_source_safety: OK'
