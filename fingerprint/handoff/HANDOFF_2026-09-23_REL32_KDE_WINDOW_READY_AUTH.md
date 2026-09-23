# GXFP51A0 rel32 — KDE window-ready authentication

Date: 2026-09-23
Branch: fingerprint-rel32-kde-window-ready-auth

## Trigger

A later rel31 human lock test failed with no fingerprint prompt even after mouse
movement. The exact user journal at 09:48 showed:

LockScreenUi.qml:128 TypeError: Cannot call method 'requestActivate' of null

rel31 set uiVisible=true directly from Component.onCompleted. Plasma 6.7.5 then
entered its stock onUiVisibleChanged handler before Window.window was attached.
The exception at Window.window.requestActivate() aborted the handler before
authenticator.startAuthenticating(). Because uiVisible was already true, later
mouse movement could not retrigger the handler.

This was a KDE/QML startup race, not a matcher or enrollment failure.

## rel32 KDE integration

The rel31 driver / TLS / matcher / warm-image validation is unchanged.

The KDE helper now:
- migrates rel30 and rel31 patches automatically;
- starts a 25 ms retry timer from Component.onCompleted;
- waits until lockScreenRoot.Window.window is non-null;
- only then sets uiVisible=true;
- leaves stock Plasma onUiVisibleChanged to run requestActivate() and
  authenticator.startAuthenticating() in native order;
- stops the startup timer after success and caps it at 80 attempts;
- backports KDE plasma-desktop commit e5616c6a (2026-08-18) narrowly:
  while uiVisible is true, authenticator.startAuthenticating() is refreshed once
  per second;
- skips the heartbeat backport if a future Plasma already contains the upstream
  heartbeat.

## Evidence / validation

- targeted rel31->rel32 migration test: PASS
- helper --check: PASS
- qmllint on a real copied Plasma 6.7.5 lockscreen directory: PASS
- rel32 --apply followed by --remove restores the official
  plasma-desktop-6.7.5-1.1 LockScreenUi.qml byte-for-byte: PASS
- full verify-software-baseline.sh: PASS
- reproducible libfprint v1.94.100 build: PASS
- active sensor I/O during software baseline: NONE
- GPIO/MMIO writes during software baseline: NONE
- firmware actions during software baseline: NONE
- real kscreenlocker_greet --testing --immediateLock under QT_QPA_PLATFORM=offscreen:
  QML loaded, PAM started, no requestActivate-null exception observed.
- offscreen --testing did not start the separate fingerprint PAM backend, so it
  is not claimed as an end-to-end fingerprint test.
- direct fprintd-verify pre-finger path reaches:
  Verify started! / Verifying: right-index-finger
- fprintd is active and all three enrollments are present.

## Enrollment state

A fresh KDE right-index enrollment completed at 2026-09-23 09:37:37.
Left index and right middle remain the previous enrollments.

A root-only temporary rollback archive remains at:
/run/gxfp51a0-enroll-backup.tar

Do not inspect or expose its contents. Remove it only after the first successful
rel32 human lock validation. It is volatile and would disappear on reboot.

## Remaining human validation

Only after all automated checks above:
1. lock Pegasus;
2. do not move mouse or keyboard;
3. confirm fingerprint prompt appears;
4. place the freshly enrolled right index;
5. report success/failure.

After direct lock succeeds, remove the temporary enrollment backup. Then deep-S3
and first-cold-boot tests remain.

Never reboot Pegasus automatically.
