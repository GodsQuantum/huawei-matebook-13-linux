#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate"
hook="$root/integration/kde-lockscreen/90-gxfp51a0-kde-lockscreen.hook"

grep -Fq 'GXFP51A0 window-ready fingerprint integration v5' "$h"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$h"
grep -Fq 'function onResumingFromSuspend()' "$h"
grep -Fq 'property bool gxfp51a0ResumeRearmPending: false' "$h"
grep -Fq 'function onStateChanged()' "$h"
! grep -Fq 'KDE e5616c6a: keep backend active' "$h"
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

GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
grep -Fq 'GXFP51A0 window-ready fingerprint integration v5' "$tmp"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$tmp"
grep -Fq 'function onResumingFromSuspend()' "$tmp"
grep -Fq 'function onStateChanged()' "$tmp"
grep -Fq 'gxfp51a0ResumeRearmPending = true;' "$tmp"
! grep -Fq 'GXFP51A0 upstream fingerprint heartbeat backport BEGIN' "$tmp"

GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --remove
cmp -s "$tmp" "$stock"

# v4 -> v5: retain the proven startup gate and add exactly one resume-rearm block.
cat >"$tmp" <<'QML'
MouseArea {
        id: lockScreenRoot
        property bool uiVisible: false
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }
            authenticator.startAuthenticating();
        }
        // GXFP51A0 window-ready startup timer BEGIN
        Timer {
            id: gxfp51a0StartupAuthTimer
            interval: 25
            repeat: true
            triggeredOnStart: true
            property int attempts: 0
            onTriggered: {
                attempts++;
                if (lockScreenRoot.Window.window) {
                    stop();
                    lockScreenRoot.uiVisible = true;
                } else if (attempts >= 80) {
                    stop();
                }
            }
            onRunningChanged: {
                if (running) {
                    attempts = 0;
                }
            }
        }
        // GXFP51A0 window-ready startup timer END
        onBlockUIChanged: {
        }
        Component.onCompleted: {
            launchAnimation.start();
            // GXFP51A0 window-ready fingerprint integration v4
            gxfp51a0StartupAuthTimer.start();
        }
}
QML
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
[[ "$(grep -Fc 'GXFP51A0 resume rearm BEGIN' "$tmp")" -eq 1 ]]
grep -Fq 'GXFP51A0 window-ready fingerprint integration v5' "$tmp"

# v3 -> v5: remove the unsafe partial heartbeat and add the one-shot resume path.
sed 's/integration v5/integration v3/' "$tmp" >"$stock"
python3 - "$stock" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="        onBlockUIChanged: {\n"
hb="""        // GXFP51A0 upstream fingerprint heartbeat backport BEGIN
        Timer {
            interval: 1000
            running: parent.uiVisible
            repeat: true
            onTriggered: authenticator.startAuthenticating()
        }
        // GXFP51A0 upstream fingerprint heartbeat backport END
"""
# Strip the v5 resume block from this synthetic migration fixture.
a=s.index("        // GXFP51A0 resume rearm BEGIN\n")
b=s.index("        // GXFP51A0 resume rearm END\n", a)+len("        // GXFP51A0 resume rearm END\n")
s=s[:a]+s[b:]
s=s.replace(needle, hb+needle, 1)
p.write_text(s)
PY
cp "$stock" "$tmp"
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
grep -Fq 'GXFP51A0 window-ready fingerprint integration v5' "$tmp"
! grep -Fq 'GXFP51A0 upstream fingerprint heartbeat backport BEGIN' "$tmp"
[[ "$(grep -Fc 'GXFP51A0 resume rearm BEGIN' "$tmp")" -eq 1 ]]

echo 'test_kde_instant_auth_source_safety: OK'
