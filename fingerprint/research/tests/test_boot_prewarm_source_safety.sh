#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/boot-prewarm/gxfp51a0-boot-prewarm"
u="$root/integration/boot-prewarm/gxfp51a0-boot-prewarm.service"
p="$root/packaging/arch/PKGBUILD"

grep -Fq 'GXFP51A0' "$h"
grep -Fq 'GetDefaultDevice' "$h"
grep -Fq 'Claim s ""' "$h"
grep -Fq 'timeout 45s' "$h"
! grep -Fq 'VerifyStart' "$h"
! grep -Fq 'EnrollStart' "$h"

grep -Fq 'Requires=fprintd.service' "$u"
grep -Fq 'After=fprintd.service' "$u"
grep -Fq 'Before=display-manager.service' "$u"
grep -Fq 'WantedBy=graphical.target' "$u"
grep -Fq 'TimeoutStartSec=55s' "$u"

grep -Fq 'gxfp51a0-boot-prewarm' "$p"
grep -Fq 'graphical.target.wants/gxfp51a0-boot-prewarm.service' "$p"

echo 'test_boot_prewarm_source_safety: OK'
