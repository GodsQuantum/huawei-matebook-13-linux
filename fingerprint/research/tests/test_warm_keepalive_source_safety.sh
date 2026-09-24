#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
pkg="$root/packaging/arch/PKGBUILD"
arch="$root/install-arch.sh"
portable="$root/install-linux.sh"

# Historical keepalive sources may remain as research provenance, but rel37+
# must never package, enable or advertise the periodic synthetic Claim loop.
! grep -Fq 'integration/warm-keepalive/' "$pkg"
! grep -Fq 'timers.target.wants/gxfp51a0-warm-keepalive.timer' "$pkg"
! grep -Fq 'systemctl start gxfp51a0-warm-keepalive' "$arch"
! grep -Fq 'OnActiveSec=3min' "$portable"
! grep -Fq 'KEEPALIVE_' "$portable"

# Install/upgrade may stop/delete stale units from old releases.
grep -Fq 'gxfp51a0-warm-keepalive' "$root/packaging/arch/libfprint-goodix51a0.install"
grep -Fq 'gxfp51a0-warm-keepalive' "$portable"

echo 'test_warm_keepalive_source_safety: OK (legacy keepalive remains disabled)'
