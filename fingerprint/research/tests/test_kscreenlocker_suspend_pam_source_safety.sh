#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
p="$root/integration/kscreenlocker-upstream-s3"

grep -Fq 'pkgver=6.7.5' "$p/PKGBUILD"
grep -Fq 'pkgrel=1.2' "$p/PKGBUILD"
grep -Fq '0001-upstream-992f3fa8-keep-pam-across-suspend.patch' "$p/PKGBUILD"
grep -Fq 'Deliberately do NOT cancel authentication on suspend' "$p/0001-upstream-992f3fa8-keep-pam-across-suspend.patch"
grep -Fq -- '-        m_authenticators->cancel();' "$p/0001-upstream-992f3fa8-keep-pam-across-suspend.patch"
grep -Fq -- '-    , m_logindIntegration(new LogindIntegration(this))' "$p/0001-upstream-992f3fa8-keep-pam-across-suspend.patch"
grep -Fq '992f3fa8f4c4ade5dad7df789e1883a5d5e8ac2c' "$p/README.md"

printf '%s  %s\n'   adba7bb7c27eb3a572e5e9d3cea0dbeebe59d3634472d1863d14fe892cb13b2b "$p/kde.pam"   32734b4e1ec8b7f7e32b6cb2d68285c5c4f15f53736bba085096e76095181241 "$p/kde-fingerprint.pam"   5d9c31cbf66e8e455b9559c929f184efd598f714743d5a1e6ce20adb44dc4b2d "$p/kde-smartcard.pam" |
  sha256sum -c -

echo 'test_kscreenlocker_suspend_pam_source_safety: OK'
