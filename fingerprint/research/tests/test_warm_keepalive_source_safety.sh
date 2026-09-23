#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/warm-keepalive/gxfp51a0-warm-keepalive"
s="$root/integration/warm-keepalive/gxfp51a0-warm-keepalive.service"
t="$root/integration/warm-keepalive/gxfp51a0-warm-keepalive.timer"
grep -Fq 'Claim s ""' "$h"
grep -Fq 'timeout 45s' "$h"
! grep -Eq 'VerifyStart|EnrollStart|restart fprintd' "$h"
grep -Fq 'ExecStart=/usr/libexec/gxfp51a0-warm-keepalive' "$s"
grep -Fq 'TimeoutStartSec=50s' "$s"
grep -Fq 'OnBootSec=20s' "$t"
grep -Fq 'OnUnitActiveSec=3min' "$t"
grep -Fq 'WantedBy=timers.target' "$t"
echo 'test_warm_keepalive_source_safety: OK'
