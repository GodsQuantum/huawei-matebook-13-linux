# GXFP51A0 experimental libfprint candidate

**Status: builds and links against libfprint v1.94.100; hardware communication is not established.**

This directory preserves the exact GXFP51A0 candidate source that passed the
2026-09-08 libfprint build gates. It exists so future research can resume from
a reproducible software baseline rather than rebuilding the port from scratch.

## Build result

Validated:

```text
MESON_CONFIGURE=PASS
UPSTREAM_LIBFPRINT_BUILD=PASS
COMPILE_ERROR_GROUPS=0
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES
GOODIX51A0_STRING_IN_SHARED_LIBRARY=YES
SOFTWARE_BUILD_READY=YES
```

The reviewed ACPI IRQ helper under `../../research/linux/` also compiles for
the tested CachyOS kernel when Kbuild uses the same LLVM toolchain as the
kernel (`LLVM=1`).

## What is proven in this candidate

- ACPI HID `GXFP51A0`.
- SPI mode 0, 8-bit, 10 MHz.
- Windows mode-5 write boundary: outer 4 bytes -> ~2 ms -> separate inner write.
- reviewed `/dev/gxfp_irq_wait` readiness bridge contract.
- GPIO264 reset HIGH 10 ms -> LOW 100 ms -> final LOW.
- target NOP checksum `0xA5`.
- DriverState `0x96` and A8 common-init retry/reset flow.
- source compiles and links with libfprint `v1.94.100`.

## Deliberately blocked

`gx_upload_config_and_reqtls()` returns failure intentionally.

The candidate does **not** promote GXFP5187-specific configuration or RAM-PSK
behavior to GXFP51A0. TLS/capture/matcher/enroll/verify code is present as a
downstream architectural base but remains unreachable until same-device
communication/config/TLS evidence exists.

`GOODIX_PSK_LEN=48` is inherited from the GXFP5187 precedent and is **not a
validated GXFP51A0 constant**. The exact Windows driver uses a variable-length
DSM result at this layer. See
[`../../docs/current-boundary-2026-09-08.md`](../../docs/current-boundary-2026-09-08.md).

## libfprint integration

Apply `libfprint-v1.94.100.patch` to libfprint `v1.94.100`, and place this
directory at:

```text
libfprint/drivers/goodix51a0/
```

Build with:

```text
-Ddrivers=goodix51a0
```

Canonical driver metadata:

```meson
'goodix51a0': { 'spi': true, 'helper': ['udev', 'openssl'], 'optional': true },
```

The tested patch also contains the Meson dictionary-iteration compatibility fix
required by Meson 1.12.0 in the tested environment.

## Licensing

The Goodix TLS/matcher-derived files retain their original
`LGPL-2.1-or-later` SPDX headers and Benjamin Allègre / Sigfrodr attribution.
Those per-file SPDX headers are authoritative for these files.

No proprietary Goodix/Huawei binary, firmware, raw `_DSM`, PSK or derived key
is included here.

<!-- first-contact-fidelity-2026-09-08 -->

## First-contact fidelity correction — 2026-09-08

The candidate now mirrors the validated 34-transfer Windows-faithful research
model: no unconditional initial reset, DriverState NOP+5 ms, no DriverState
replay after fallback reset, and one exact same-attempt A8 retransmission.

The `_DeviceInit` intermediate call is `device_action(0x0F, &zero, 4)` and
contains no sensor I/O.

Canonical resume point:
[`../../FINAL_HANDOFF_2026-09-08.md`](../../FINAL_HANDOFF_2026-09-08.md).
