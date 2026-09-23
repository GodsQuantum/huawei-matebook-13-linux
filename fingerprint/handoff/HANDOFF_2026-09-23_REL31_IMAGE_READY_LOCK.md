# GXFP51A0 rel31 — image-ready lock

Date: 2026-09-23
Branch: fingerprint-rel31-image-ready-lock

## Trigger

The first rel30 direct-lock human test failed. KScreenLocker started at 03:27:04
and fprintd immediately attempted fingerprint I/O, proving the rel30
Component.onCompleted hook fired. However:

- the UI remained visually idle, so the fingerprint prompt was hidden;
- GET_IMAGE/FDT retries followed;
- a Claim-only keepalive had completed about 78 seconds earlier, proving that
  FDT/Claim success alone did not guarantee the encrypted image path was healthy.

The failure occurred before biometric matching. Existing template-v4 enrollments
remain valid; rel29 had already matched the existing right-index enrollment.

## rel31 changes

### Warm readiness

gx_warm_validate() now requires:
1. successful FDT probe;
2. one successful encrypted background-mode GET_IMAGE/TLS frame.

The validation frame is immediately discarded. It does not enter the matcher,
enrollment/template storage or any release dump path.

If this image-path validation fails:
- capture pacing learning is suppressed;
- stale TLS is abandoned host-side without close_notify;
- the MCU is reset;
- normal bounded cold preparation runs before Verify proceeds.

This prevents a stale context from being advertised as ready merely because FDT
still answers.

### KDE lock screen

The rel30 direct authenticator call is removed. The rel31 integration migrates
rel30 automatically and changes stock Plasma 6.7.5 LockScreenUi.qml so:

- Component.onCompleted sets uiVisible=true;
- stock onUiVisibleChanged performs authenticator.startAuthenticating();
- the existing UI/prompt is visible immediately;
- no synthetic input and no duplicate direct auth call are used.

The pacman hook still reapplies the integration after plasma-desktop upgrades;
driver removal restores the stock Component.onCompleted line.

## Software validation

- targeted KDE migration test: PASS
- lifecycle/warm-image readiness test: PASS
- boot-binding/source gate: PASS
- full verify-software-baseline.sh: PASS
- reproducible libfprint v1.94.100 build: PASS
- active sensor I/O during software baseline: NONE
- GPIO/MMIO writes during software baseline: NONE
- firmware actions during software baseline: NONE

Built package:
libfprint-goodix51a0 1.94.100.goodix51a0-31
SHA-256:
a6afbf60ad308c1702658a37733f8b52e8ab5a6d105b5b0e2554e4966d101ff8

Installed on Pegasus without reboot.

## External GitHub refresh

Latest tracked external message remains szlukabence in
Sigfrodr/libfprint-goodixtls#5 at 2026-09-22 22:53 CEST. It supports a
privacy-preserving local FAR/FRR/EER harness and does not require a rel31 code
change. No newer tracked external commit requires a port.

## Next human test

1. lock Pegasus;
2. do not move the mouse or press a key;
3. wait for the fingerprint prompt to be visible;
4. place an enrolled finger;
5. report whether unlock succeeds.

After that, deep-S3 and first-cold-boot validation remain.

Never reboot Pegasus automatically.
