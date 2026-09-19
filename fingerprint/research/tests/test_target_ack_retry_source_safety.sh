#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_TARGET_ACK_ATTEMPTS 2' "$driver"
grep -Fq 'gx51_wait_irq_gpio48 (self->irq_fd, 1200)' "$driver"
grep -Fq 'errno == ETIMEDOUT' "$driver"
grep -Fq 'target ACK diagnostic: no-irq retry' "$driver"
grep -Fq 'g_usleep (8000 * self->timing_scale / 100)' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_target_send_ack (")
b=s.index("gx_factory_staging_read_cb", a)
f=s[a:b]
assert "for (attempt = 1; attempt <= GX_TARGET_ACK_ATTEMPTS; attempt++)" in f
assert "if (errno == ETIMEDOUT && attempt < GX_TARGET_ACK_ATTEMPTS)" in f
# Malformed/status-bearing ACKs must fail immediately, not retry.
assert 'ack-parse-failed' in f
assert 'status-failed' in f
echo = None
PY2
echo 'test_target_ack_retry_source_safety: OK'
