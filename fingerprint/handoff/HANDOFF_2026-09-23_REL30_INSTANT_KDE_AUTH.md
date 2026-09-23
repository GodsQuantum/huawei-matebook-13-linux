# GXFP51A0 rel30 — instant KDE authentication

Date: 2026-09-23
Branch: fingerprint-rel30-instant-kde-auth

## Validated facts

- Existing template-v4 enrollments remain valid.
- rel29 succeeded at lock with the existing right-index enrollment after a clean prewarm.
- A second enrolled finger also authenticated.
- The remaining UX defect was KDE Plasma 6.7.5 lockscreen activation: stock
  LockScreenUi.qml calls authenticator.startAuthenticating() when uiVisible
  changes, so an idle lock screen could require mouse/keyboard activity before
  fingerprint PAM was armed.

## rel30

- keeps rel29 five-minute stale warm-context expiry;
- adds a package-owned Claim-only keepalive every 3 minutes;
- adds a reversible KDE Plasma 6.7.5 integration that arms the existing
  authenticator in Component.onCompleted;
- keeps post-resume asynchronous prewarm;
- keeps template v4 / SIGFM v3 / threshold 7 / 20 views / max 3 presses;
- does not require re-enrollment.

## Packaging

The Arch/CachyOS package owns:
- libfprint GXFP51A0 driver;
- resume prewarm hook/worker;
- 3-minute warm keepalive timer/service;
- KDE lockscreen integration helper;
- pacman hook that reapplies the KDE integration after plasma-desktop upgrades.

The KDE integration intentionally modifies exactly one plasma-desktop-owned QML
file while installed. Removal restores the stock Component.onCompleted line.

The one-shot reinstall kit must contain rel30 driver, Plasma Login Manager
6.7.5-3.2 integration package, exact source archive, INSTALL-GXFP51A0.sh,
INSTALL.txt and SHA256SUMS.

## GitHub refresh

The latest external message was szlukabence in Sigfrodr/libfprint-goodixtls#5
at 2026-09-22 22:53 CEST. It confirms NBIS is unsuitable in real GXFP51A0 use
and proposes a local-only FAR/FRR/EER harness. No external repo has a newer patch
that should alter rel30.

## Remaining human validation

After final install/cleanup:
1. lock Pegasus;
2. do not move the mouse or press a key;
3. place an enrolled finger directly;
4. verify immediate unlock;
5. later validate deep-S3 resume and first cold boot manually.

Never reboot Pegasus automatically.
