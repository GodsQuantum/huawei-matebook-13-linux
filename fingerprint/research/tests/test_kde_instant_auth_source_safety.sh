#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate"
hook="$root/integration/kde-lockscreen/90-gxfp51a0-kde-lockscreen.hook"

grep -Fq 'GXFP51A0 native-S3-continuity fingerprint integration v9' "$h"
grep -Fq 'rewrite_v8_to_v9' "$h"
grep -Fq 'apply_v9' "$h"
grep -Fq 'Target = plasma-desktop' "$hook"
grep -Fq -- '--apply' "$hook"

tmp="$(mktemp)"
stock="$(mktemp)"
trap 'rm -f "$tmp" "$stock"' EXIT

cat >"$stock" <<'QML'
MouseArea {
        id: lockScreenRoot
        property bool uiVisible: false
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }
            authenticator.startAuthenticating();
        }
        onBlockUIChanged: {
        }
        Component.onCompleted: launchAnimation.start();
}
QML
cp "$stock" "$tmp"

# Stock -> v9: normal startup must match rel51 window-ready semantics.
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
grep -Fq 'GXFP51A0 native-S3-continuity fingerprint integration v9' "$tmp"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$tmp"
grep -Fq 'if (lockScreenRoot.Window.window)' "$tmp"
grep -A4 -F 'GXFP51A0 native-S3-continuity fingerprint integration v9' "$tmp" |
  grep -Fq 'gxfp51a0StartupAuthTimer.start();'
! grep -A4 -F 'GXFP51A0 native-S3-continuity fingerprint integration v9' "$tmp" |
  grep -Fq 'authenticator.startAuthenticating();'

# Resume has one idempotent kick, with no pending/delay/heartbeat machinery.
grep -Fq 'function onResumingFromSuspend()' "$tmp"
grep -A9 -F 'function onResumingFromSuspend()' "$tmp" |
  grep -Fq 'gxfp51a0StartupAuthTimer.restart();'
grep -A9 -F 'function onResumingFromSuspend()' "$tmp" |
  grep -Fq 'authenticator.startAuthenticating();'
! grep -Fq 'gxfp51a0ResumeRearmPending' "$tmp"
! grep -Fq 'gxfp51a0ResumeRearmTimer' "$tmp"
! grep -Fq 'onLoginFailedDelayStarted' "$tmp"
! grep -Fq 'GXFP51A0 upstream fingerprint heartbeat backport BEGIN' "$tmp"

GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --remove
cmp -s "$tmp" "$stock"

# v8 -> v9 regression gate: remove rel52's early Component.onCompleted auth.
cp "$stock" "$tmp"
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
python3 - "$tmp" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
s=s.replace("GXFP51A0 native-S3-continuity fingerprint integration v9",
            "GXFP51A0 upstream-suspend-safe fingerprint integration v8", 1)
a=s.index("        // GXFP51A0 resume rearm BEGIN\n")
b=s.index("        // GXFP51A0 resume rearm END\n", a)+len("        // GXFP51A0 resume rearm END\n")
s=s[:a]+s[b:]
needle="            // GXFP51A0 upstream-suspend-safe fingerprint integration v8\n"
s=s.replace(needle, needle+"            authenticator.startAuthenticating();\n", 1)
p.write_text(s)
PY
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
echo 'test_kde_instant_auth_source_safety: OK (rel51 startup + one-shot resume kick)'
