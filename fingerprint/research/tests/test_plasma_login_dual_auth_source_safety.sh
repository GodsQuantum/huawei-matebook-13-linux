#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
i="$root/integration/plasma-login-manager-6.7-pam-messages"
p="$i/0005-split-fingerprint-password-auth.patch"
p6="$i/0006-fingerprint-password-preemption.patch"
pkg="$i/PKGBUILD"

grep -Fq 'pkgrel=3.5' "$pkg"
grep -Fq '0005-split-fingerprint-password-auth.patch' "$pkg"
grep -Fq '0006-fingerprint-password-preemption.patch' "$pkg"

# Password path must lose pam_fprintd; fingerprint gets a dedicated PAM stack.
grep -Fq -- '-auth        sufficient  pam_fprintd.so max-tries=3 timeout=12' "$p"
grep -Fq 'diff --git a/data/pam/arch/plasmalogin-fingerprint' "$p"
grep -Fq '+-auth      required     pam_fprintd.so max-tries=3 timeout=12' "$p"

# Distinct protocol, explicit helper PAM selection, and client-side cancellation.
grep -Fq 'FingerprintLogin' "$p"
grep -Fq 'CancelLogin' "$p"
grep -Fq 'LoginCancelled' "$p"
grep -Fq 'setPamService' "$p"
grep -Fq 'service == QStringLiteral("plasmalogin-fingerprint")' "$p"
grep -Fq 'onTextChanged:' "$p"
grep -Fq 'cancelFingerprintForPassword(false)' "$p"
grep -Fq 'm_auth->stop();' "$p"
grep -Fq 'm_socketServer->loginCancelled(m_cancelSocket);' "$p"

# PLM 3.5: the driver already owns the bounded multi-pose budget, so PAM runs
# exactly one fingerprint operation. Intermediate pose errors must not look
# terminal to the greeter, and a submitted password must preempt server-side.
grep -Fq 'pam_fprintd.so max-tries=1 timeout=15' "$p6"
grep -Fq 'Password login preempts active fingerprint authentication' "$p6"
grep -Fq 'm_passwordPreemptionPending = true;' "$p6"
grep -Fq 'm_pendingPassword = password;' "$p6"
grep -Fq 'Ignoring authentication result while fingerprint stop is pending' "$p6"
grep -Fq 'm_auth->pamService() != QStringLiteral("plasmalogin-fingerprint")' "$p6"
grep -Fq 'Fingerprint helper stopped; starting queued password authentication' "$p6"
grep -Fq 'startAuth(user, password, session)' "$p6"

# Never allow arbitrary PAM service selection from the greeter.
grep -Fq 'm_pamService.clear();' "$p"

echo 'test_plasma_login_dual_auth_source_safety: OK (single PAM fingerprint op + password preemption)'
