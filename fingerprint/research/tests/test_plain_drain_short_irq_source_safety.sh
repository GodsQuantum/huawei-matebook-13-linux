#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_DRAIN_IRQ_POLL_MS 10' "$driver"
grep -Fq 'gx51_wait_irq_gpio48 (self->irq_fd, GX_DRAIN_IRQ_POLL_MS)' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_send_plain_drain (")
b=s.index("gx_bio_send", a)
f=s[a:b]
assert "GX_DRAIN_IRQ_POLL_MS" in f
assert "errno != ETIMEDOUT" in f
assert "gx_read_frame (self" in f
# The short IRQ poll must happen before the actual frame read. Ignore the
# explanatory comment that mentions gx_read_frame() by name.
assert f.index("gx51_wait_irq_gpio48 (self->irq_fd, GX_DRAIN_IRQ_POLL_MS)") < f.index("r = gx_read_frame (self")
assert "misses >= 25" in f
PY2
echo 'test_plain_drain_short_irq_source_safety: OK'
