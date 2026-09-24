#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
i="$root/integration/plasma-login-manager-6.7-pam-messages"
p="$i/0005-split-fingerprint-password-auth.patch"
pkg="$i/PKGBUILD"

grep -Fq 'pkgrel=3.4' "$pkg"
grep -Fq '0005-split-fingerprint-password-auth.patch' "$pkg"

# Password path must lose pam_fprintd; fingerprint gets a dedicated PAM stack.
grep -Fq -- '-auth        sufficient  pam_fprintd.so max-tries=3 timeout=12' "$p"
grep -Fq 'diff --git a/data/pam/arch/plasmalogin-fingerprint' "$p"
grep -Fq '+-auth      required     pam_fprintd.so max-tries=3 timeout=12' "$p"

# Distinct protocol, explicit helper PAM selection, and password preemption.
grep -Fq 'FingerprintLogin' "$p"
grep -Fq 'CancelLogin' "$p"
grep -Fq 'LoginCancelled' "$p"
grep -Fq 'setPamService' "$p"
grep -Fq 'service == QStringLiteral("plasmalogin-fingerprint")' "$p"
grep -Fq 'onTextChanged:' "$p"
grep -Fq 'cancelFingerprintForPassword(false)' "$p"
grep -Fq 'm_auth->stop();' "$p"
grep -Fq 'm_socketServer->loginCancelled(m_cancelSocket);' "$p"

# Never allow arbitrary PAM service selection from the greeter.
grep -Fq 'm_pamService.clear();' "$p"

echo 'test_plasma_login_dual_auth_source_safety: OK'
