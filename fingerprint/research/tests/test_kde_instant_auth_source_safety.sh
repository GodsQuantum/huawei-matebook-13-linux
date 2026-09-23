#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate"
hook="$root/integration/kde-lockscreen/90-gxfp51a0-kde-lockscreen.hook"

grep -Fq 'GXFP51A0 window-ready fingerprint integration v3' "$h"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$h"
grep -Fq 'if (lockScreenRoot.Window.window)' "$h"
grep -Fq 'gxfp51a0StartupAuthTimer.start();' "$h"
grep -Fq 'interval: 1000' "$h"
grep -Fq 'running: parent.uiVisible' "$h"
grep -Fq 'KDE e5616c6a' "$h"
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
grep -Fq 'GXFP51A0 window-ready fingerprint integration v3' "$tmp"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$tmp"
grep -Fq 'if (lockScreenRoot.Window.window)' "$tmp"
grep -Fq 'lockScreenRoot.uiVisible = true;' "$tmp"
grep -Fq 'GXFP51A0 upstream fingerprint heartbeat backport BEGIN' "$tmp"
grep -Fq 'running: parent.uiVisible' "$tmp"
grep -A6 'Component.onCompleted' "$tmp" | grep -Fq 'gxfp51a0StartupAuthTimer.start();'

GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --remove
cmp -s "$tmp" "$stock"

# rel31 -> rel32 migration.
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
        onBlockUIChanged: {
        }
        Component.onCompleted: {
            launchAnimation.start();
            // GXFP51A0 instant fingerprint integration v2
            // Native onUiVisibleChanged starts PAM and keeps prompts visible.
            uiVisible = true;
        }
}
QML
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
grep -Fq 'GXFP51A0 window-ready fingerprint integration v3' "$tmp"
! grep -Fq 'instant fingerprint integration v2' "$tmp"
grep -Fq 'if (lockScreenRoot.Window.window)' "$tmp"
grep -A6 'Component.onCompleted' "$tmp" | grep -Fq 'gxfp51a0StartupAuthTimer.start();'

echo 'test_kde_instant_auth_source_safety: OK'
