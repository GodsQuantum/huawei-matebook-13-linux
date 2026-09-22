#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_TLS_IRQ_POLL_MS 20' "$driver"
grep -Fq '#define GX_TLS_IRQ_POLLS 200' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
for name, end in [("gx_bio_recv (", "gx_gpio_reset"),
                  ("gx_take_tls_frame (", "gx_send_capture_cleanup")]:
    a=s.index(name)
    b=s.index(end, a)
    f=s[a:b]
    assert "gx51_wait_irq_gpio48 (self->irq_fd, GX_TLS_IRQ_POLL_MS)" in f
    assert "errno != ETIMEDOUT" in f
    assert "gx_read_frame (self" in f
    assert f.index("gx51_wait_irq_gpio48 (self->irq_fd, GX_TLS_IRQ_POLL_MS)") < f.index("gx_read_frame (self")
assert 'int max_attempts = capture_diagnostic ? 2 : (diagnostic ? 1 : 5);' in s
assert 'probe_prewarm' not in s
assert 'cached PMK retained after failed diagnostic TLS attempt' in s
a=s.index("gx_tls_session (")
b=s.index("/* Production-only stale-cache recovery", a)
f=s[a:b]
assert "gx_gpio_reset (self);" in f
assert "gx_read_fw_version_stage2e (self, fw, sizeof fw)" in f
assert f.index("gx_gpio_reset (self);") < f.index("gx_read_fw_version_stage2e (self, fw, sizeof fw)")
assert "TLS retry reset/A8 confirmed" in f
PY2
echo 'test_tls_irq_poll_bounds_source_safety: OK'
