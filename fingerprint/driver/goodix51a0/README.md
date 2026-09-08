# GXFP51A0 experimental libfprint candidate

**Status: builds and links against libfprint v1.94.100; hardware communication
is not established.**

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
- SPI mode 0, 8 bits, 10 MHz
- Milan split write: outer 4 bytes -> about 2 ms -> remaining bytes
- reviewed `/dev/gxfp_irq_wait` readiness bridge contract
- GPIO264 reset HIGH 10 ms -> LOW 100 ms -> final LOW
- target NOP checksum `0xA5`
- DriverState Install `(9,3)` / `0x96`
- GetEvkVersion NOP + 5 ms + A8 with one identical same-attempt A8 retry
- no unconditional initial reset before DriverState
- fallback reset continues into `init_MCU` without DriverState replay

## Deliberately blocked

`gx_upload_config_and_reqtls()` remains target-gated.

The candidate does **not** promote GXFP5187-specific configuration or RAM-PSK
behavior to GXFP51A0. TLS/capture/matcher/enroll/verify code is preserved as a
downstream architectural base but remains unreachable until exact-device
communication/config/TLS evidence exists.

`GOODIX_PSK_LEN=48` is inherited precedent and is **not a validated GXFP51A0
constant**. Windows `_DSM` handling at the reconstructed layer is
variable-length.

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

The corrected Windows-faithful software model is already represented in a
separate research harness that remained silent on target hardware:

```text
34 physical SPI transfers
180 TX bytes
12 IRQ waits
0 Goodix IRQ
180 retained RX bytes, all 0xFF
```

Therefore rebuilding this candidate does not itself justify another active
hardware probe.

Resume from [`../../HANDOFF_CURRENT.md`](../../HANDOFF_CURRENT.md).

## Licensing

The Goodix TLS/matcher-derived files retain their original
`LGPL-2.1-or-later` SPDX headers and Benjamin Allègre / Sigfrodr attribution.
Those per-file SPDX headers are authoritative.
