# Goodix GXFP51A0 / GF3658 Milan on Linux

Experimental native libfprint driver for the SPI Goodix GXFP51A0 used in the
Huawei MateBook 13 2021 family.

> Français: [README.FR.md](README.FR.md)

## Status — 2026-09-19

Hardware-validated target:

- ACPI HID: `GXFP51A0`
- Goodix GF3658 / Milan, ST411
- firmware: `GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`, 1 MHz validated
- GPIO48 readiness/IRQ, GPIO264 MCU reset
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- host-side 80x64 capture/matching through libfprint

Current production path:

```text
GXFP51A0 → libfprint → fprintd → KDE / GNOME / PAM / CLI
```

There is no device-specific desktop UI and no KDE/GNOME protocol patch.

Validated on the reference machine:

- standard fprintd enrollment completed;
- genuine right-index verification matched;
- two different non-enrolled fingers were rejected;
- the driver requires 15 biometric enrollment captures; fprintd exposes 16
  frontend stages when `identify` is available because it adds one internal
  identify-related step; it also exposes `press`, `finger-needed` and
  `finger-present`;
- the current candidate implements standard libfprint `identify` for
  multi-finger `VerifyStart("any")`;
- verification/identification reports the biometric decision before finger-lift
  cleanup, so login managers do not wait on the release timeout.

The current candidate also treats a transient TLS/background prewarm failure as
recoverable: hardware `open` remains successful and the biometric action gets a
bounded whole-session retry from a reset boundary.

## Install on Arch / CachyOS

From the repository root:

```bash
./fingerprint/install-arch.sh
```

The installer builds locally, installs the package and fprintd, reloads udev and
restarts fprintd. It does **not** modify PAM, KDE or GNOME configuration.

After installation, use the normal fprintd tools:

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
fprintd-list "$USER"
```

Desktop authentication policy remains distribution-specific. A desktop only
needs to support the normal fprintd/PAM stack.

## Guided verification diagnostic

For interactive testing, use the local harness rather than chat-timed commands:

```bash
./fingerprint/tools/gxfp51a0-verify-diagnostic.py
```

It waits for fprintd's standard `finger-needed` / `finger-present` state,
prints a local 3-2-1 countdown, then gives explicit `POSE`, `GARDE` and
`RETIRE` instructions. The requested physical finger is shown in uppercase.
Driver logs are used only for optional score/timing details; the guidance
itself relies on the standard fprintd D-Bus state.

For a multi-finger comparison against one enrolled template:

```bash
./fingerprint/tools/gxfp51a0-compare-fingers.py
```

The default sequence performs three genuine `RIGHT INDEX` scans, then three
negative controls (`LEFT INDEX`, `LEFT MIDDLE`, `RIGHT MIDDLE`) and writes an
aggregate JSON report containing scores, thresholds, verdicts and capture time.

## Contributor validation

```bash
make -C fingerprint verify
```

This runs the deterministic research/safety suite, verifies the source
manifest, fetches exact libfprint `v1.94.100`, builds the candidate and checks
the resulting artifacts.

Release gates include:

```text
SOURCE_MANIFEST=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES
RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT
SOFTWARE_BUILD_READY=YES
```

The validation command performs no active sensor transfer, GPIO/MMIO write or
firmware action.

## Safety and privacy

Normal release builds do not compile the biometric capture-dump writer.
Developer-only capture diagnostics are excluded from distributed artifacts.

Never commit or publish:

- biometric captures or templates;
- PMK/PSK/key material or private per-unit fixtures;
- proprietary Goodix/Huawei binaries or firmware;
- serial numbers or private machine identifiers.

The driver does not flash sensor firmware.

## Scope

The proven target is the GXFP51A0/ST411 firmware and hardware combination above.
Other laptops carrying the same ACPI HID may use different GPIO wiring or
firmware and must be validated before being marked supported.

See:

- [native desktop integration](docs/native-desktop-integration.md)
- [provenance](PROVENANCE.md)
- [driver source](driver/goodix51a0/)
- [current handoff](HANDOFF_CURRENT.md)
- [research log](docs/research-log.md)

The driver source subtree is `LGPL-2.1-or-later`; historical research and other
repository content may carry separate licensing. See per-file SPDX notices and
[provenance](PROVENANCE.md).
