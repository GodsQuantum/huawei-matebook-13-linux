#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
p="$root/integration/kscreenlocker-upstream-s3"
pkg="$p/PKGBUILD"
patch="$p/0001-upstream-992f3fa8-keep-pam-across-suspend.patch"

grep -Fq 'pkgver=6.7.5' "$pkg"
grep -Fq 'pkgrel=1.5' "$pkg"

# Password PAM must never be cancelled by suspend/resume handling.
grep -Fq -- '-        m_authenticators->cancel();' "$patch"
grep -Fq 'if (sleeping)' "$patch"
grep -Fq 'Preserve password PAM' "$patch"

# Resume restarts only noninteractive authenticators.
grep -Fq 'Resume: rearming fingerprint PAM' "$patch"
grep -Fq 'void PamAuthenticators::resumeAuthenticating()' "$patch"
grep -Fq 'noninteractive->restartAuthentication();' "$patch"
! sed -n '/void PamAuthenticators::resumeAuthenticating()/,/^+}/p' "$patch" | grep -Fq 'interactive->cancel'

# Stale fingerprint PAM is allowed to unwind, then restarted.
grep -Fq 'void PamAuthenticator::restartAuthentication()' "$patch"
grep -Fq 'm_restartPending = true' "$patch"
grep -Fq 'if (m_inAuthentication)' "$patch"
grep -Fq 'cancel();' "$patch"
grep -Fq 'runPendingRestart();' "$patch"

# Sticky PAM_AUTHINFO_UNAVAIL is cleared only at the resume restart boundary.
grep -Fq 'void PamWorker::resetUnavailable()' "$patch"
grep -Fq 'worker->resetUnavailable();' "$patch"
grep -Fq 'worker->authenticate();' "$patch"
grep -Fq 'm_nextAttemptAllowedTime = std::chrono::steady_clock::now();' "$patch"

# Real authentication failures keep PAM fail-delay. Only a resume restart whose
# previous result was hardware-unavailable may ignore the stale inherited delay.
grep -Fq 'm_restartDelayActive = true' "$patch"
grep -Fq 'm_restartFromUnavailable = m_unavailable' "$patch"
grep -Fq 'if (m_restartFromUnavailable)' "$patch"
grep -Fq 'ignoring stale fail-delay from unavailable noninteractive PAM' "$patch"
grep -Fq 'QTimer::singleShot(delay' "$patch"
! grep -Fq 'heartbeat' "$patch"
! grep -Fq 'power/control' "$patch"
! grep -Fq 'Pre-QML: starting authenticators' "$patch"

printf '%s  %s\n' \
  adba7bb7c27eb3a572e5e9d3cea0dbeebe59d3634472d1863d14fe892cb13b2b "$p/kde.pam" \
  32734b4e1ec8b7f7e32b6cb2d68285c5c4f15f53736bba085096e76095181241 "$p/kde-fingerprint.pam" \
  5d9c31cbf66e8e455b9559c929f184efd598f714743d5a1e6ce20adb44dc4b2d "$p/kde-smartcard.pam" |
  sha256sum -c -

echo 'test_kscreenlocker_suspend_pam_source_safety: OK (robust fingerprint-only resume restart)'
