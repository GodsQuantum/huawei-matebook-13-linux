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

The exact `GF_ST411SEC_APP_14115` behavior is now discriminated. On reference MateBook, a
read-only `E4` probe returns status `0`, type `0x0000aaaa` and 32 bytes. Static
analysis of the exact target firmware independently explains that response: the
category-`0xE` operation-2 handler constructs the `AAAA`/32-byte result.

The GDIX51C0 Linux-owned provisioning route does **not** transfer directly to
this firmware. Its operation-0 (`E0`) entry is absent/no-op on the exact 14115
dispatch path, so no `0xbb010003` write should be attempted. This closes the
state-changing provisioning experiment before touching sensor state.

The replacement fast track is the factory flash-secret path. Independent work
on another GXFP51A0 running the same 14115 firmware has now recovered and
validated the complete scheme. Three redundant records exist at the known
factory slots; each has an 8-byte header declaring a 256-byte body. That body is
16 bytes of salt plus 240 bytes of AES-128-CBC ciphertext. The record is
decrypted with AES-128-CBC;
the key is the first 16 bytes of `SHA256(salt || 48 zero bytes || fallback
seed)`, the IV is the 16-byte salt, and the authenticated plaintext begins with
record type `0x000d`, length `0x30`, followed by the 48-byte TLS PSK. The full
48 bytes, not a 32-byte prefix, are used as the TLS PSK.

That same investigation completed a live hardware TLS 1.2
`PSK-AES128-GCM-SHA256` handshake on GXFP51A0/14115. Thus SGX/WBDI is no longer
a prerequisite for Linux operation. reference MateBook still needs an independent local
reproduction before this repository may claim local TLS success.

A follow-up from the working 5187 path also confirms the oversized-record trap:
a post-handshake image record must be authenticated/decrypted outside the stock
TLS record reader, using the sensor/client write material and the implicit TLS
record sequence number. The GXFP51A0 branch now carries that GCM path with the
first application-data sequence set to 1 and a 22,176-byte regression vector.


reference MateBook hardware testing now closes one important portability assumption. The
exact 14115 F2 read handler admits only absolute addresses in the application
flash window `0x08020000` through `0x08040000`. Reads aimed at the lower factory
regions therefore return the request echo without memory data. Factory-blob
recovery through F2 must stay disabled on reference MateBook unless a genuinely different
command/state is demonstrated.

F2 remains useful for read-only flash access, but upstream testing found two
possible dump artifacts: an echoed request prefix and corruption of the first
data byte of a read. reference MateBook also showed that an unaligned `base+3` header read
can reflect request metadata into the apparent payload; factory headers are now
read from the aligned record base and the body length is taken from bytes `+4..+7`.
Any extractor must use strict response-shape checks and redundant-record agreement
before use.

## Revised gates

1. Keep the proven reference MateBook transport: mode 0 + `SPI_CS_HIGH`, target reset
   sequence, 1 MHz and final GPIO264 LOW.
2. Reconstruct the 14115 factory flash record on reference MateBook using read-only,
   overlapping F2 reads and strict known-vector/record-integrity checks.
3. Decrypt only in memory, recover the F2-corrupted first byte by requiring a
   unique type `0x000d` / length `48` candidate, and require matching PMKs from
   at least two redundant copies. E4 is a firmware sanity check, not a body hash.
   Never log, store or publish the PSK.
4. Establish the already-modelled TLS 1.2 PSK-GCM session on reference MateBook.
5. Reuse/adapt the tested same-die ChicagoHS capture, calibration, matcher and
   libfprint/fprintd integration instead of reimplementing those layers.
6. Keep SGX/WBDI only as a Windows-compatibility/fallback research path.

## Safety locks

No firmware flash/erase/update is part of this fast-track plan. Do not import
GPIO defaults or target config from another laptop without exact-target checks.
Raw DSM material, PSKs, OTP contents and proprietary binaries remain private.
