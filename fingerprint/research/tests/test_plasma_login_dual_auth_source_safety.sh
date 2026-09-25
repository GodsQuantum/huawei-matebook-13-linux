#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
i="$root/integration/plasma-login-manager-6.7-pam-messages"
p5="$i/0005-split-fingerprint-password-auth.patch"
p6="$i/0006-fingerprint-password-preemption.patch"
p7="$i/0007-parallel-password-fingerprint-auth.patch"
p8="$i/0008-continuous-fingerprint-availability.patch"
pkg="$i/PKGBUILD"

grep -Fq 'pkgrel=3.7' "$pkg"
grep -Fq '0005-split-fingerprint-password-auth.patch' "$pkg"
grep -Fq '0006-fingerprint-password-preemption.patch' "$pkg"
grep -Fq '0007-parallel-password-fingerprint-auth.patch' "$pkg"
grep -Fq '0008-continuous-fingerprint-availability.patch' "$pkg"

# Password and fingerprint remain separate PAM services.
grep -Fq -- '-auth        sufficient  pam_fprintd.so max-tries=3 timeout=12' "$p5"
grep -Fq 'diff --git a/data/pam/arch/plasmalogin-fingerprint' "$p5"
grep -Fq '+-auth      required     pam_fprintd.so max-tries=3 timeout=12' "$p5"

# The driver owns its bounded 3-pose budget: PAM launches one fingerprint op.
grep -Fq 'pam_fprintd.so max-tries=1 timeout=15' "$p6"

# PLM 3.6 follows KDE's multi-authenticator shape: two independent Auth workers,
# one shared session context, and first successful authenticator wins.
grep -Fq '+    Auth *m_fingerprintAuth{nullptr};' "$p7"
grep -Fq '+    , m_fingerprintAuth(new Auth(this))' "$p7"
grep -Fq '+    connect(m_fingerprintAuth, &Auth::authentication' "$p7"
grep -Fq '+    startAuth(m_auth, user, password, session);' "$p7"
grep -Fq '+    startAuth(m_fingerprintAuth, user, QString(), session, QStringLiteral("plasmalogin-fingerprint"));' "$p7"
grep -Fq '+    qDebug() << "Authentication race won by"' "$p7"
grep -Fq '+    if (winner != m_auth && m_auth->isActive())' "$p7"
grep -Fq '+    if (winner != m_fingerprintAuth && m_fingerprintAuth->isActive())' "$p7"
grep -Fq '+        // Password and fingerprint are intentionally independent. Typing or' "$p7"

python3 - "$p7" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
adds="\n".join(line[1:] for line in s.splitlines() if line.startswith("+") and not line.startswith("+++"))

# Never reintroduce password->fingerprint preemption.
for forbidden in (
    "m_passwordPreemptionPending",
    "pendingPasswordLogin",
    "cancelFingerprintForPassword",
    "Password login preempts active fingerprint authentication",
):
    assert forbidden not in adds, forbidden

# Typing password must not cancel fingerprint.
assert "onTextChanged:" not in "\n".join(
    line for line in adds.splitlines()
    if "cancelFingerprint" in line or "passwordBox" in line or "onTextChanged" in line
)
assert "submitting a password must not cancel the active fingerprint worker" in adds

# Fingerprint cancellation remains available for user/session changes only.
assert "cancelFingerprintForUserChange" in adds
assert "m_fingerprintAuth->stop();" in adds

# A single shared auth context prevents two workers from allocating two sessions/VTs.
assert "prepareAuthContext" in adds
assert "m_authEnvironment" in adds
assert "m_authContextSessionFile" in adds
PY


# PLM 3.7 keeps fingerprint available for the whole greeter lifetime while each
# individual PAM/driver operation stays bounded.
grep -Fq 'id: fingerprintRetryTimer' "$p8"
grep -Fq 'interval: 900' "$p8"
grep -Fq 'onTriggered: root.maybeStartFingerprintLogin()' "$p8"
grep -Fq 'fingerprintRetryTimer.restart()' "$p8"
grep -Fq 'fingerprintRetryTimer.stop()' "$p8"
grep -Fq 'root.fingerprintAutoAttemptDone = false' "$p8"
grep -Fq 'password remains usable' "$p8"

echo 'test_plasma_login_dual_auth_source_safety: OK (continuous concurrent password + fingerprint)'
