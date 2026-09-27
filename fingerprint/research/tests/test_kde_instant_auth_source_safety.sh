#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate"
hook="$root/integration/kde-lockscreen/90-gxfp51a0-kde-lockscreen.hook"

grep -Fq 'GXFP51A0 cpp-lifecycle-auth fingerprint integration v10' "$h"
grep -Fq 'rewrite_v9_to_v10' "$h"
grep -Fq 'apply_v10' "$h"
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

# Stock -> v10: QML only owns rel51-style window-ready startup.
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
grep -Fq 'GXFP51A0 cpp-lifecycle-auth fingerprint integration v10' "$tmp"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$tmp"
grep -Fq 'if (lockScreenRoot.Window.window)' "$tmp"
grep -A4 -F 'GXFP51A0 cpp-lifecycle-auth fingerprint integration v10' "$tmp" |
  grep -Fq 'gxfp51a0StartupAuthTimer.start();'
! grep -A4 -F 'GXFP51A0 cpp-lifecycle-auth fingerprint integration v10' "$tmp" |
  grep -Fq 'authenticator.startAuthenticating();'
! grep -Fq 'GXFP51A0 resume rearm BEGIN' "$tmp"
! grep -Fq 'function onResumingFromSuspend()' "$tmp"
! grep -Fq 'gxfp51a0ResumeRearmPending' "$tmp"
! grep -Fq 'gxfp51a0ResumeRearmTimer' "$tmp"
! grep -Fq 'onLoginFailedDelayStarted' "$tmp"

GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --remove
cmp -s "$tmp" "$stock"

# v9 -> v10: remove only the QML resume block.
cp "$stock" "$tmp"
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
python3 - "$tmp" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
s=s.replace("GXFP51A0 cpp-lifecycle-auth fingerprint integration v10",
            "GXFP51A0 native-S3-continuity fingerprint integration v9", 1)
needle="        // GXFP51A0 window-ready startup timer END\n"
resume="""        // GXFP51A0 resume rearm BEGIN
        Connections {
            target: sessionManagement
            function onResumingFromSuspend() {
                gxfp51a0StartupAuthTimer.restart();
                authenticator.startAuthenticating();
            }
        }
        // GXFP51A0 resume rearm END
"""
s=s.replace(needle, needle+resume, 1)
p.write_text(s)
PY
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
! grep -Fq 'GXFP51A0 resume rearm BEGIN' "$tmp"

echo 'test_kde_instant_auth_source_safety: OK (window-ready QML; lifecycle auth in C++)'
