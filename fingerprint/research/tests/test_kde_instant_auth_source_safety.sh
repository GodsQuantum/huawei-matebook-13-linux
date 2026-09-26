#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
h="$root/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate"
hook="$root/integration/kde-lockscreen/90-gxfp51a0-kde-lockscreen.hook"

grep -Fq 'GXFP51A0 upstream-suspend-safe fingerprint integration v8' "$h"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$h"
grep -Fq 'rewrite_v7_to_v8' "$h"
grep -Fq 'apply_v8' "$h"
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

# Stock -> v8: parallel startup only, no suspend/resume workaround in QML.
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
grep -Fq 'GXFP51A0 upstream-suspend-safe fingerprint integration v8' "$tmp"
grep -Fq 'id: gxfp51a0StartupAuthTimer' "$tmp"
grep -Fq 'if (lockScreenRoot.Window.window)' "$tmp"
grep -A4 -F 'GXFP51A0 upstream-suspend-safe fingerprint integration v8' "$tmp" |
  grep -Fq 'authenticator.startAuthenticating();'
! grep -Fq 'GXFP51A0 resume rearm BEGIN' "$tmp"
! grep -Fq 'gxfp51a0ResumeRearmPending' "$tmp"
! grep -Fq 'gxfp51a0ResumeRearmTimer' "$tmp"
! grep -Fq 'onLoginFailedDelayStarted' "$tmp"
! grep -Fq 'GXFP51A0 upstream fingerprint heartbeat backport BEGIN' "$tmp"

GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --remove
cmp -s "$tmp" "$stock"

# v7 -> v8: this is the live rel53 migration. Remove the entire resume workaround
# while preserving the proven startup timer and early authentication call.
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
        // GXFP51A0 resume rearm BEGIN
        property bool gxfp51a0ResumeRearmPending: false
        property bool gxfp51a0ResumeDelayActive: false
        Timer {
            id: gxfp51a0ResumeRearmTimer
            interval: 100
        }
        Connections {
            target: sessionManagement
            function onResumingFromSuspend() {
                lockScreenRoot.gxfp51a0ResumeRearmPending = true;
            }
        }
        Connections {
            target: authenticator
            function onLoginFailedDelayStarted(what, source, uSecDelay) {
                gxfp51a0ResumeRearmTimer.interval = Math.max(100, Math.ceil(uSecDelay / 1000) + 50);
            }
        }
        // GXFP51A0 resume rearm END
        onBlockUIChanged: {
        }
        Component.onCompleted: {
            launchAnimation.start();
            // GXFP51A0 resume-delay-aware fingerprint integration v7
            authenticator.startAuthenticating();
            gxfp51a0StartupAuthTimer.start();
        }
}
QML
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --apply
GXFP51A0_KDE_LOCKSCREEN_QML="$tmp" bash "$h" --check
grep -Fq 'GXFP51A0 upstream-suspend-safe fingerprint integration v8' "$tmp"
! grep -Fq 'GXFP51A0 resume rearm BEGIN' "$tmp"
! grep -Fq 'gxfp51a0ResumeRearmPending' "$tmp"
! grep -Fq 'onLoginFailedDelayStarted' "$tmp"
[[ "$(grep -A4 -F 'GXFP51A0 upstream-suspend-safe fingerprint integration v8' "$tmp" |
      grep -Fc 'authenticator.startAuthenticating();')" -eq 1 ]]

echo 'test_kde_instant_auth_source_safety: OK (v8 uses upstream KScreenLocker S3 handling)'
