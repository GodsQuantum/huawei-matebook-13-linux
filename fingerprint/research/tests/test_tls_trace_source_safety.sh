#!/usr/bin/env bash
set -euo pipefail
tls="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix_tls.c"
grep -Fq 'tls_msg_trace_cb' "$tls"
grep -Fq 'SSL_CTX_set_msg_callback (t->ctx, tls_msg_trace_cb)' "$tls"
grep -Fq 'TLS trace: %s content=%d handshake=%d len=%zu' "$tls"
python3 - "$tls" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("tls_msg_trace_cb")
b=s.index("psk_server_cb", a)
f=s[a:b]
# Metadata only: callback must not format payload or PSK buffers.
assert "buf[" not in f.replace("p[0]", "")
assert "psk" not in f.lower()
assert "g_debug" in f
PY2
echo 'test_tls_trace_source_safety: OK'
