# GXFP51A0 experimental libfprint candidate

**Status: builds and links against libfprint v1.94.100; first contact and exact-target configuration are confirmed. The 14115 PMK/TLS path and real imaging are independently confirmed on the same GXFP51A0 target; Pegasus still requires hardware validation of the read-only boot-staging provider before TLS is enabled.**

This directory preserves the reviewed GXFP51A0 candidate source. Compilation is
not evidence of working fingerprint capture.

## Recommended build

From the repository root:

```bash
make -C fingerprint build
```

For the complete software baseline:

```bash
make -C fingerprint verify
```

These commands are implemented by the public scripts under
[`../../scripts/`](../../scripts/) and perform no sensor hardware I/O.

The reproducible build pins:

```text
libfprint v1.94.100
Meson 1.12.0
Ninja 1.13.2
drivers=goodix51a0
introspection=false
doc=false
installed-tests=false
```

Validated artifact gates:

```text
SOURCE_MANIFEST=PASS
LIBFPRINT_PATCH=PASS
MESON_CONFIGURE=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES
GOODIX51A0_STRING_IN_DRIVER_ARCHIVE=YES
SOFTWARE_BUILD_READY=YES
```

## Target-specific facts represented by the candidate

- ACPI HID `GXFP51A0`
- SPI CPOL/CPHA mode 0 + `SPI_CS_HIGH`, 8 bits; 1 MHz currently proven on Linux
- Milan split write: outer 4 bytes -> about 2 ms -> remaining bytes
- reviewed `/dev/gxfp_irq_wait` readiness bridge contract
- GPIO264 active-HIGH reset: HIGH 300 ms -> LOW -> 600 ms settle -> final LOW
- target NOP checksum `0xA5`
- DriverState Install `(9,3)` / `0x96`
- GetEvkVersion NOP + 5 ms + A8 with one identical same-attempt A8 retry
- no unconditional initial reset before DriverState
- fallback reset continues into `init_MCU` without DriverState replay
- TLS 1.2 target suite `0x00A8` / `PSK-AES128-GCM-SHA256`
- PSK identity `Client_identity`; sensor is TLS client, host is server

## Deliberately blocked

`gx_upload_config_and_reqtls()` now executes the same-device target init/config
path: A2 soft reset, chip ID, OTP validation/calibration, IDLE + four DAC
register writes, then the exact 256-byte config upload. The PMK/TLS step remains
strictly gated.

The candidate does **not** promote GXFP5187-specific PMK addresses or keys to
GXFP51A0. The exact target TLS ciphersuite is integrated and regression-tested,
but the runtime PMK read remains gated until the F2 address mapping is proven.

Same-device Windows logs confirm a 48-byte PMK. Exact ST411 firmware control
flow identifies its TLS RAM globals, but Linux F2 retrieval is still being
hardware-validated and no key material is published. Windows `_DSM` handling
at the reconstructed layer remains variable-length.

No proprietary Goodix/Huawei binary, firmware, raw `_DSM`, PSK or derived key
is included here.

## Source integrity

Before every supported build:

```bash
cd fingerprint/driver/goodix51a0
sha256sum -c SOURCE_MANIFEST.sha256
```

The one-shot build script performs this automatically.

## Manual integration reference

For manual work only:

1. clone libfprint tag `v1.94.100`;
2. apply `libfprint-v1.94.100.patch`;
3. copy this directory into `libfprint/drivers/goodix51a0/`;
4. configure with `-Ddrivers=goodix51a0`.

Canonical metadata:

```meson
'goodix51a0': { 'spi': true, 'helper': ['udev', 'openssl'], 'optional': true },
```

The patch also carries the Meson dictionary-iteration compatibility adjustment
used by the validated Meson 1.12.0 environment.

## Current research boundary

Historical runs with normal chip-select polarity remained silent:

```text
34 physical SPI transfers
180 TX bytes
12 IRQ waits
0 Goodix IRQ
180 retained RX bytes, all 0xFF
```

Those runs are superseded by the 2026-09-14 hardware results: `SPI_CS_HIGH` + GPIO264 LOW produces a real A8 ACK and `GF_ST411SEC_APP_14115`, and the exact OTP-derived ChicagoHS config is accepted. TLS/PMK/capture remain the next boundary.

Resume from [`../../HANDOFF_CURRENT.md`](../../HANDOFF_CURRENT.md).

## Update 2026-09-18: exact-target staging and image format

The 14115 F2 range gate remains closed: only the application window is a
legitimate memory read. The previously reported factory-slot read has now been
reconciled upstream: a rejected F2 request can return an address-independent
stale staging buffer which, immediately after boot on the reproducing unit,
contained the encrypted factory blob. The public parser models that as a
rejected staging response, never as a private-flash read, and explicitly
excludes the valid application window.

Real GXFP51A0 imaging is also independently reproduced on Linux. The target
image plaintext is 10,573 bytes: 8-byte header, 10,560 packed 12-bit bytes and
a 5-byte trailer. The wire raster is 88x80 with 64 active columns. The candidate
decoder crops the active 64x80 raster and transposes it to the existing 80x64
libfprint-facing orientation under regression tests.

Pegasus must still reproduce the stale boot-staging response with the read-only
immediate-post-reset probe before that provider is enabled at runtime. SGX/WBDI
is now a fallback rather than the primary route.

## Licensing

The Goodix TLS/matcher-derived files retain their original
`LGPL-2.1-or-later` SPDX headers and Benjamin Allègre / Sigfrodr attribution.
Those per-file SPDX headers are authoritative.
