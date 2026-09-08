# GXFP51A0 contributor tooling

These scripts are the supported entry points for reproducing the public
GXFP51A0 software baseline. They intentionally separate software validation,
build integration and passive platform observation from active sensor traffic.

## Fastest path

From the repository root:

```bash
make -C fingerprint verify
```

Equivalent direct command:

```bash
./fingerprint/scripts/verify-software-baseline.sh
```

This runs the first-contact regression suite, the complete software-only
research test suite, verifies the driver source manifest and builds the
candidate against **libfprint v1.94.100**.

It performs **no fingerprint hardware I/O**.

## Scripts

### `verify-software-baseline.sh`

Canonical one-shot validation. Use `--no-build` only when testing repository
logic without network access.

### `build-libfprint-v1.94.100.sh`

Reproducible candidate build. It:

1. verifies `SOURCE_MANIFEST.sha256`;
2. checks required development libraries with `pkg-config`;
3. creates an isolated Python venv outside the repository;
4. pins Meson `1.12.0` and Ninja `1.13.2`;
5. clones exact libfprint tag `v1.94.100`;
6. verifies and applies the integration patch;
7. copies only the reviewed candidate source files;
8. configures with `drivers=goodix51a0`, introspection/docs/installed-tests off;
9. builds with Ninja;
10. verifies the exact GXFP51A0 object, its GObject type symbol and ACPI ID, then proves that object/type are present in the libfprint driver archive.

Override the external workspace with `GXFP51A0_BUILD_ROOT`.

### `passive-linux-observability.sh`

Read-only Linux platform inventory for the current unresolved boundary. It
collects ACPI/SPI topology, runtime-PM state, interrupts, PCI driver state,
optional GPIO/pinctrl debugfs state and relevant kernel logs.

It does **not** bind/unbind drivers, load/unload modules, change power states,
perform SPI transfers, request output GPIOs or touch firmware.

### `windows/gxfp51a0_windows_observability.ps1`

Optional contributor tool for a machine where the same GXFP51A0 works under
Windows. It inventories the PnP/WDF stack and can collect a WDF WPR trace around
one successful fingerprint authentication.

The primary development machine currently has no Windows installation, so this
path is published for external contributors rather than claimed as locally
validated.

## Active research tooling

The historical bounded active-probe tooling remains under `../research/` for
auditability. Closed experiments must not be repeated unchanged. Read
`../FINAL_HANDOFF_2026-09-08.md` and `../docs/safety.md` before considering any
hardware-active experiment.
