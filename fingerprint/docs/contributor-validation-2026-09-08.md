# GXFP51A0 contributor validation baseline — 2026-09-08

## Purpose

The repository now exposes a reproducible contributor workflow instead of
requiring a new researcher to reconstruct the build commands from handoff
notes.

Canonical commands:

```bash
make -C fingerprint verify
make -C fingerprint build
make -C fingerprint research
make -C fingerprint passive-audit
```

`verify` is the recommended first command. It is software-only and must remain
safe to run on a system that physically contains GXFP51A0.

## Reproducible build contract

The validated integration target remains:

```text
libfprint tag:      v1.94.100
Meson:              1.12.0
Ninja:              1.13.2
driver:             goodix51a0
introspection:      false
doc:                false
installed-tests:    false
```

Required build evidence:

```text
SOURCE_MANIFEST=PASS
LIBFPRINT_PATCH=PASS
MESON_CONFIGURE=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES
GOODIX51A0_ACPI_ID_IN_OBJECT=YES
GOODIX51A0_OBJECT_IN_DRIVER_ARCHIVE=YES
SOFTWARE_BUILD_READY=YES
```

The build script creates its workspace outside the repository under `../temp/`
by default. It never accesses the fingerprint device.

## Platform-observability boundary

The first real sensor-side ACK remains absent under Linux. Since the current
development installation has no Windows boot, the repository publishes two
external-contributor paths:

1. Linux: `scripts/passive-linux-observability.sh`
2. Windows: `scripts/windows/gxfp51a0_windows_observability.ps1`

The Linux script is read-only. The Windows script is optional and exists so a
contributor with a known-working Windows GXFP51A0 can collect the missing
comparison evidence.

## What a useful external report contains

Before opening an issue:

```bash
make -C fingerprint verify
```

If on Linux target hardware:

```bash
make -C fingerprint passive-audit
```

Attach only sanitized output. Never publish raw `_DSM`, PSK, derived keys,
proprietary Windows binaries, serial numbers or unrelated personal system data.

## Current research boundary

Closed:

- DMA versus deterministic PIO;
- runtime PM as primary cause;
- Linux IRQ mapping and userspace-vs-native wait;
- mode-5 outer/inner timing;
- simple SPB split-write semantics;
- DeviceInit `besdenable` intermediate operation;
- GPIO112/GPP_D16 and hidden LPSS-switch hypotheses;
- repeated unchanged 34-transfer common-init.

Still open:

- physical CS/SCLK/MOSI/MISO reachability versus controller-side completion;
- physical GPIO48 response;
- first accepted sensor ACK;
- A8/EVK;
- exact target config;
- exact target DSM/TLS/PSK semantics;
- capture/enroll/verify/fprintd/PAM.

The first success criterion is still a real GXFP51A0 ACK.
