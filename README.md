# Huawei MateBook 13 on Linux

> Practical Linux-readiness notes, fixes and reverse-engineering for the Huawei MateBook 13 family.
>
> **Français : [README.FR.md](README.FR.md)**

The MateBook 13 is already a very usable Linux laptop, but on the tested Intel + NVIDIA MX250 models two issues remain disproportionately important when moving from Windows:

1. **GPU & power management** — using the NVIDIA MX250 only when an application actually needs it, without leaving the dGPU consuming power all day and without logging out to switch modes.
2. **Fingerprint reader support** — the Goodix GXFP51A0 / GF3658 Milan sensor is not yet supported by a production Linux driver and still requires reverse-engineering.

This repository is organized around those two gaps.

## Status at a glance

| Area | Status | What this repository provides |
| --- | --- | --- |
| **GPU & power — NVIDIA MX250** | **Working on the validated setup** | Full-Integrated idle state, hot dGPU activation per app, PRIME Render Offload, automatic unload/PCI removal, Plasma/KWin isolation, Desktop and Steam helpers |
| **Fingerprint — Goodix GXFP51A0 / GF3658** | **Research / not yet usable for login** | Full Windows-faithful common-init replay completes all 34 SPI transfers but still produces 0 Goodix IRQ/RX; current discriminator is controller DMA vs PIO |

### Validated GPU configuration

The on-demand GPU design has been validated on a Huawei MateBook 13 with:

- Intel integrated graphics;
- NVIDIA GeForce MX250 / GP108M (`10de:1d13`);
- KDE Plasma Wayland;
- proprietary NVIDIA **R580** driver branch.

The management script detects hardware dynamically and contains package-manager paths for Arch/CachyOS, Fedora and Debian/Ubuntu families. **Plasma Wayland is the validated desktop path; other compositors are intentionally fail-closed until tested.**

NVIDIA 590+ no longer supports Pascal GPUs such as the MX250, so this project deliberately targets the maintained legacy R580 branch.

## 1. GPU & Power — on-demand MX250

**Start here:** [`gpu-power/`](gpu-power/)

The goal is not to emulate a permanently enabled Hybrid mode. At idle, the MX250 is removed from PCI and the machine stays on Intel graphics. When a managed application starts, the helper:

```text
full Integrated idle
        ↓
PCI rescan
        ↓
load NVIDIA R580
        ↓
PRIME Render Offload for the selected app
        ↓
app exits
        ↓
unload NVIDIA
        ↓
PCI remove
        ↓
full Integrated idle again
```

KWin is pinned to the Intel GPU so it does not grab the hot-added NVIDIA render node and keep the MX250 awake.

### Quick start

```bash
cd gpu-power
chmod +x huawei-matebook-13-gpu-manager.sh
./huawei-matebook-13-gpu-manager.sh install
```

After the requested reboot:

```bash
# interactive menu
./huawei-matebook-13-gpu-manager.sh

# or CLI
./huawei-matebook-13-gpu-manager.sh add
./huawei-matebook-13-gpu-manager.sh status
./huawei-matebook-13-gpu-manager.sh test
```

See [`gpu-power/README.md`](gpu-power/README.md) for architecture, supported distributions, Steam handling, rollback and troubleshooting.

## 2. Fingerprint reader — Goodix GXFP51A0 / GF3658 Milan

**Start here:** [`fingerprint/`](fingerprint/)

The entire original fingerprint research project is preserved under this directory. It includes the protocol notes, ACPI/SPI/GPIO mapping, supervised probes, Windows driver cross-checks and safety documentation.

Current reality: **there is still no working Linux fingerprint driver for this sensor.** The complete reconstructed Windows common-init sequence now runs to completion on Linux but remains silent (34 SPI transfers, 0 Goodix IRQ/RX). The next controlled discriminator is the PXA2xx controller datapath: DMA versus PIO.

Target architecture remains:

```text
validated Linux Milan transport
-> libfprint
-> fprintd
-> KDE/GNOME/PAM login and sudo
```

## Supported hardware vs. project scope

Huawei sold multiple machines under the MateBook 13 name. Do not assume every revision uses the same NVIDIA GPU, ACPI layout or fingerprint controller.

The GPU tooling requires an NVIDIA MX250 with PCI ID `10de:1d13` and refuses unsupported hardware by default. The fingerprint research specifically targets `ACPI\GXFP51A0` / GF3658 Milan.

If your revision differs, open an issue with **generic hardware identifiers only**. Do not post serial numbers or machine-unique security material.

## Privacy and safety

This is a public hardware repository. Please do **not** publish:

- user names, home-directory paths or hostnames;
- device serial numbers or machine UUIDs;
- LAN/public IP addresses that are not required for reproduction;
- passwords, API tokens, private keys or credentials;
- raw Goodix `_DSM` payloads, PSKs or other machine-unique fingerprint security material;
- proprietary Windows binaries, firmware images or raw disassembly.

Use hashes, PCI/ACPI hardware IDs and minimal reproducible excerpts instead. Fingerprint hardware experiments must also follow [`fingerprint/docs/safety.md`](fingerprint/docs/safety.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). When reporting a result, distinguish **CONFIRMED**, **INFERRED** and **HYPOTHESIS** claims and include enough generic system context to reproduce it.

Security-sensitive reports should follow [SECURITY.md](SECURITY.md).

## License

GPL-2.0-only. See [LICENSE](LICENSE).
