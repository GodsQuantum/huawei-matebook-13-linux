#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate"
hook="$root/integration/kde-lockscreen/90-gxfp51a0-kde-lockscreen.hook"

grep -Fq 'GXFP51A0 instant fingerprint integration v2' "$h"
grep -Fq 'uiVisible = true;' "$h"
grep -Fq 'onUiVisibleChanged starts PAM' "$h"
grep -Fq 'Target = plasma-desktop' "$hook"
grep -Fq -- '--apply' "$hook"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<'QML'
MouseArea {
        id: lockScreenRoot
        property bool uiVisible: false
        onUiVisibleChanged: {
            authenticator.startAuthenticating();
        }
        Component.onCompleted: launchAnimation.start();
}
QML
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
grep -Fq 'GXFP51A0 instant fingerprint integration v2' "$tmp"
grep -A6 'Component.onCompleted' "$tmp" | grep -Fq 'uiVisible = true;'
grep -A6 'Component.onCompleted' "$tmp" | grep -Fq 'onUiVisibleChanged starts PAM'
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --remove
grep -Fq 'Component.onCompleted: launchAnimation.start();' "$tmp"
! grep -Fq 'GXFP51A0 instant fingerprint integration' "$tmp"

# rel30 -> rel31 migration must be automatic on package upgrade.
cat >"$tmp" <<'QML'
MouseArea {
        id: lockScreenRoot
        property bool uiVisible: false
        onUiVisibleChanged: {
            authenticator.startAuthenticating();
        }
        Component.onCompleted: {
            launchAnimation.start();
            // GXFP51A0 instant fingerprint integration: arm PAM immediately
            // while keeping the lock-screen UI visually idle.
            authenticator.startAuthenticating();
        }
}
QML
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
grep -Fq 'GXFP51A0 instant fingerprint integration v2' "$tmp"
grep -A6 'Component.onCompleted' "$tmp" | grep -Fq 'uiVisible = true;'
! grep -Fq 'arm PAM immediately' "$tmp"

echo 'test_kde_instant_auth_source_safety: OK'
