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
- `suspend` / `resume`
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

Enumeration and biometric preparation are deliberately separate.

`probe` is passive with respect to the sensor protocol: it checks only that
the host transport can be opened and closed. It never resets the MCU, starts
TLS, captures a background image or calibrates FDT.

A real `open`/Claim owns sensor preparation. It starts from a deterministic
MCU boundary, performs bounded TLS/background/FDT preparation, and reports a
protocol error if that preparation cannot be completed. It never reports an
open device while the capture context is known to be unusable.

A validated warm context may survive an ordinary Claim/Release for low latency,
but never blindly survives a power-state boundary. Native libfprint
`suspend`/`resume` callbacks invalidate it during active use, and an
idle-suspend fallback detects elapsed sleep from the
`CLOCK_BOOTTIME - CLOCK_MONOTONIC` delta at the next Claim.

For systems where deep sleep removes sensor power, the package also installs a
small system-level resume integration. A `sleep.target` hook schedules an
asynchronous worker which briefly performs the standard fprintd `Claim("")`.
This drives the same libfprint open/close lifecycle early enough to rebuild
TLS/background/FDT before the lock-screen finger normally arrives. It does not
restart fprintd, does not perform verification/enrollment, and never blocks the
resume target on a slow sensor.

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
