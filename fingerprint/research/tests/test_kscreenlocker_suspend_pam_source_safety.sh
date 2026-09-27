#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
p="$root/integration/kscreenlocker-upstream-s3"
pkg="$p/PKGBUILD"
patch="$p/0001-upstream-992f3fa8-keep-pam-across-suspend.patch"

grep -Fq 'pkgver=6.7.5' "$pkg"
grep -Fq 'pkgrel=1.3' "$pkg"
grep -Fq '0001-upstream-992f3fa8-keep-pam-across-suspend.patch' "$pkg"
! grep -Fq '0002-pegasus-start-auth-before-qml.patch' "$pkg"

# Suspend is not a PAM failure.
grep -Fq -- '-        m_authenticators->cancel();' "$patch"
grep -Fq 'if (sleeping)' "$patch"
grep -Fq 'suspend is not an authentication failure' "$patch"

# Resume handles both races:
#  - Idle group: start password + noninteractive authenticators.
#  - Active group: preserve password and re-kick only noninteractive workers.
grep -Fq 'void PamAuthenticators::resumeAuthenticating()' "$patch"
grep -Fq 'if (d->state == AuthenticatorsState::Idle)' "$patch"
grep -Fq 'startAuthenticating();' "$patch"
grep -Fq 'noninteractive->tryUnlock();' "$patch"
grep -Fq 'Resume: rearming missing authenticators' "$patch"
grep -Fq 'm_authenticators->resumeAuthenticating();' "$patch"

# No pre-QML forced authentication and no timer/heartbeat/power workaround.
! grep -Fq 'Pre-QML: starting authenticators' "$patch"
! grep -Fq 'initialViewSetup()' "$patch"
! grep -Fq 'Timer' "$patch"
! grep -Fq 'heartbeat' "$patch"
! grep -Fq 'power/control' "$patch"

printf '%s  %s\n'   adba7bb7c27eb3a572e5e9d3cea0dbeebe59d3634472d1863d14fe892cb13b2b "$p/kde.pam"   32734b4e1ec8b7f7e32b6cb2d68285c5c4f15f53736bba085096e76095181241 "$p/kde-fingerprint.pam"   5d9c31cbf66e8e455b9559c929f184efd598f714743d5a1e6ce20adb44dc4b2d "$p/kde-smartcard.pam" |
  sha256sum -c -

echo 'test_kscreenlocker_suspend_pam_source_safety: OK (precise C++ resume rearm)'
