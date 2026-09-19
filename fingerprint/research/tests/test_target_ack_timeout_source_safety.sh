#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_TARGET_ACK_IRQ_TIMEOUT_MS 100' "$driver"
grep -Fq 'gx51_wait_irq_gpio48 (self->irq_fd, GX_TARGET_ACK_IRQ_TIMEOUT_MS)' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_target_send_ack (")
b=s.index("gx_factory_staging_read_cb", a)
f=s[a:b]
assert "1200" not in f
assert "GX_TARGET_ACK_IRQ_TIMEOUT_MS" in f
PY2
echo 'test_target_ack_timeout_source_safety: OK'
