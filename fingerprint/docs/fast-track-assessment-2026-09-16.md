# GXFP51A0 fast-track reassessment — 2026-09-16

This document records a public, non-secret reassessment of the shortest route
to a working Linux fingerprint stack after Linux first contact, target config
and TLS profile were confirmed.

## Main conclusion

The native SGX/WBDI reconstruction remains technically viable, but it is no
longer the preferred route. A newer out-of-tree project,
[`berkekbgz/libfprint-goodix-spi`](https://github.com/berkekbgz/libfprint-goodix-spi),
has a hardware-tested GDIX51C0 driver whose official Windows profile selects
the same chip ID `0x2504`, sensor type 12 `ChicagoHS`, 80x64 geometry and
64-byte OTP family used by this GXFP51A0 target.

That driver already implements capture, calibration, a native Chicago matcher,
enrollment, verification/learning and fprintd persistence. Its remaining
board-specific assumptions must not be copied blindly, but its transport-neutral
Goodix/Chicago layers are a much shorter starting point than rebuilding the
entire Windows biometric stack.

## PSK fast track

The decisive new lead is the Linux-owned PSK provisioning path. The GDIX51C0
work provisions a chosen 32-byte TLS PSK through the Goodix preset-PSK register
contract and verifies the stored container hash before using TLS 1.2
`PSK-AES128-GCM-SHA256`.
The older `goodix-fp-dump` 51x0 implementation independently uses the same
preset-PSK contract (`0xbb010003` write / `0xbb020003` verification) on ST411SEC
parts. Its historical flow may erase/reflash firmware and is therefore **not**
a safe procedure for this machine. Only the protocol evidence is reusable.

This also changes interpretation of the Windows host-secret work: a 48-byte
WBDI/DSM record must not be assumed to be the final TLS PSK merely because its
length was confirmed. Other current Goodix work demonstrates a 48-byte
Windows-side intermediate/entropy path that ultimately yields a 32-byte TLS
PSK. Exact GXFP51A0 semantics still require target evidence.

## Revised gates

1. Keep the proven Pegasus transport: mode 0 + `SPI_CS_HIGH`, target reset
   sequence, 1 MHz and final GPIO264 LOW.
2. Add a **read-only** APP-mode preset-PSK/hash probe for the target firmware.
3. If the target exposes the compatible contract, validate the GDIX51C0
   white-box/provisioning algorithm against exact-target evidence before any
   state-changing write.
4. Use a Linux-owned PSK stored root-only (`0600`) and establish the already
   confirmed TLS 1.2 PSK-GCM session.
5. Reuse/adapt the tested ChicagoHS capture, calibration, matcher and libfprint
   integration instead of reimplementing those layers.
6. Keep SGX/WBDI as a fallback and a Windows-compatibility research path, not
   as the blocking dependency for Linux operation.

## Safety locks

No firmware flash/erase/update is part of this fast-track plan. Do not import
GPIO defaults or target config from another laptop without exact-target checks.
Raw DSM material, PSKs, OTP contents and proprietary binaries remain private.
