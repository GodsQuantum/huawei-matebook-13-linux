# GXFP51A0 driver provenance

This file documents source and behavioral provenance for the public GXFP51A0
libfprint driver. It keeps interoperability research, adapted code and
independent implementation boundaries explicit.

## Upstream contracts

- **libfprint** — https://gitlab.freedesktop.org/libfprint/libfprint
  - integration target: `v1.94.100`
  - the driver implements the standard `FpDevice` open/close/enroll/verify/
    identify lifecycle and finger-status contract.
- **fprintd** — https://gitlab.freedesktop.org/libfprint/fprintd
  - validated daemon line: `1.94.5`
  - no GXFP51A0-specific desktop protocol is required; KDE/GNOME/PAM consume
    the normal fprintd D-Bus API.

## Source lineage retained in-tree

- **Sigfrodr/libfprint-goodixtls**
  - https://github.com/Sigfrodr/libfprint-goodixtls
  - high-level Goodix TLS, matcher and libfprint architecture informed the
    original candidate.
  - derived files retain Benjamin Allègre / Sigfrodr copyright notices and
    `SPDX-License-Identifier: LGPL-2.1-or-later`.

The complete `driver/goodix51a0/` production driver subtree is distributed
under `LGPL-2.1-or-later`; see `driver/goodix51a0/COPYING`. More specific
per-file notices remain authoritative.

## Behavioral / interoperability references

The following projects were used as independent protocol or architecture
references. Their source is not silently copied into this driver.

- **szlukabence/goodix-fingerprint-spi-linux**
  - https://github.com/szlukabence/goodix-fingerprint-spi-linux
  - exact-target GXFP51A0 SPI/FDT/image observations were independently
    reproduced before being promoted to confirmed behavior.
- **berkekbgz/libfprint-goodix-spi**
  - https://github.com/berkekbgz/libfprint-goodix-spi
  - comparative reference for bounded session recovery, lifecycle separation,
    identify support and release-vs-developer diagnostic separation.
- **wrobelda/goodix-fp-spi-linux**
  - https://github.com/wrobelda/goodix-fp-spi-linux
  - reference for keeping hardware/protocol research separate from production
    libfprint integration.

## Proprietary reference material

Goodix Windows components were used only as interoperability/reverse-engineering
oracles. No proprietary DLL, CAB, firmware, private disassembly dump, biometric
capture, per-unit OTP/PMK/PSK, serial number or other private fixture belongs in
the public repository.

## Public release boundary

A normal release build:

- contains no biometric capture-dump writer;
- stores no private development fixture in the source tree;
- uses the standard libfprint/fprintd interfaces;
- does not patch KDE, GNOME or PAM;
- does not flash or replace sensor firmware.

Developer-only diagnostics that can handle biometric images must never be
enabled in a distributed release artifact.
