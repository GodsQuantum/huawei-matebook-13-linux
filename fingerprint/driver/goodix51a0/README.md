# GXFP51A0 libfprint driver

Production driver source for the Goodix GXFP51A0 / GF3658 Milan ST411 target.

## Validated target

- ACPI HID `GXFP51A0`
- firmware `GF_ST411SEC_APP_14115`
- chip ID `0x2504`
- SPI mode 0 + `SPI_CS_HIGH`, validated at 1 MHz
- GPIO48 readiness/IRQ and GPIO264 MCU reset
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- packed 88x80 wire image → active 64x80 → libfprint-facing 80x64

The driver is integrated as a standard libfprint SPI device and is consumed by
fprintd. It contains no KDE/GNOME-specific protocol path.

## libfprint operations

Implemented:

- open / close
- enroll
- verify
- identify
- cancellation
- finger-needed / finger-present reporting
- press scan type
- bounded session recovery

Authentication uses one usable capture per biometric decision. A valid image is
never recaptured merely because its score was near the decision threshold.

Verify/identify report their terminal match decision immediately after scoring;
finger-lift handling remains cleanup.

## Session lifecycle

Hardware open and biometric context preparation are separate.

Open may prewarm TLS/background/FDT for latency, but a transient prewarm image
timeout does not fail the device claim. Enroll/verify/identify perform a bounded
whole-session retry from a reset boundary if a clean context is unavailable.

A missing TLS image after a command ACK is treated as possible session
desynchronization: recovery tears down TLS and resets to a known firmware
boundary before retrying. PMK state is retained unless key validation itself
fails.

## Release privacy

Default/release builds do not compile `gx_dump_capture()` or its call site.
The build gate rejects a final libfprint shared library containing the biometric
capture dump path or marker.

Developer diagnostics remain source-controlled but must be explicitly compiled
with `GXFP51A0_DEVELOPER`.

## Build validation

From the repository root:

```bash
make -C fingerprint verify
```

The build pins libfprint `v1.94.100`, Meson 1.12.0 and Ninja 1.13.2, injects
the reviewed driver sources and validates the compiled object/archive/shared
library.

The source manifest is checked with:

```bash
cd fingerprint/driver/goodix51a0
sha256sum -c SOURCE_MANIFEST.sha256
```

No active hardware action is performed by the software build verification.

## Licensing and provenance

This driver subtree is `LGPL-2.1-or-later`; see [COPYING](COPYING).

Files inherited from the Sigfrodr/libfprint-goodixtls architecture retain
Benjamin Allègre / Sigfrodr attribution and their original SPDX notices.
Additional project modules carry explicit LGPL SPDX identifiers.

See [../../PROVENANCE.md](../../PROVENANCE.md) for source and behavioral
provenance.
