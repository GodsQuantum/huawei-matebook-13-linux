# Native Linux desktop integration

GXFP51A0 is implemented as a normal libfprint device. There is no
GXFP51A0-specific KDE or GNOME user interface.

```text
GXFP51A0 hardware
    ↓
libfprint goodix51a0 driver
    ↓
fprintd D-Bus service
    ↓
KDE / GNOME / PAM / command-line clients
```

## Driver contract

The production driver exposes the standard libfprint lifecycle:

- `open` / `close`
- `enroll`
- one-to-one `verify`
- one-to-many `identify`
- `FP_SCAN_TYPE_PRESS`
- enrollment-stage count
- `FP_FINGER_STATUS_NEEDED`
- `FP_FINGER_STATUS_PRESENT`

- standard retry and terminal match/no-match results
- cancellable operations

`identify` matters when several fingers are enrolled: fprintd can satisfy
`VerifyStart("any")` from the gallery instead of forcing a desktop frontend to
know which template to choose.

## Lifecycle policy

Opening the hardware and obtaining a clean biometric capture context are
separate concerns.

`open` establishes the hardware handles and may opportunistically prepare the
TLS/background/FDT context. A transient image/TLS timeout during that prewarm
does **not** make the device disappear from fprintd. The actual biometric
operation performs a bounded whole-session retry from a reset protocol
boundary.

This avoids desktop-specific workarounds while keeping initialization failures
bounded and observable.

## Authentication latency

A scored verification/identification result is reported to libfprint
immediately. Waiting for the physical finger to be lifted is cleanup and must
not delay PAM or the login manager.

The driver never retries a usable biometric capture merely because its score
was close to the acceptance threshold. Score-conditioned retries multiply
false-accept opportunities. Only unusable image-quality captures are retryable.

## Desktop policy

PAM/login policy belongs to the distribution and desktop. The driver and public
installer do not edit `/etc/pam.d/*`.

A correctly configured desktop sees only the standard fprintd device and
properties: `scan-type`, enrollment stages, `finger-needed` and
`finger-present`.
