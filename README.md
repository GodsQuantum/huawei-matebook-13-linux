# Goodix GXFP51A0 / GF3658 Milan on Linux

> **Experimental research only — safety first.** No working fingerprint driver exists. Do not flash firmware, run an unreviewed probe, or interact with the sensor outside a reviewed, minimal experiment.

> Version française : [README.FR.md](README.FR.md)

## Status

**CONFIRMED:** no working fingerprint driver exists yet. The Windows common-init/ACK/response state machine is statically resolved far enough to model one `GetEvkVersion` attempt, the passive spidev/libgpiod hardware gate has passed with zero SPI transfers, and both the restricted RX parser and exact-length IRQ/RX drain state machine are validated off-hardware on the target laptop. No new active Milan command is authorized yet.

## Confirmed platform summary

Huawei MateBook 13 2021: DMI `WRTB-WXX9`, version `M1020`, board `WRTB-WXX9-PCB`, BIOS Huawei `1.26`, CachyOS, last tested kernel `7.2.0-1-cachyos`. The ACPI/SPI Goodix `GXFP51A0` is a GF3658 Milan sensor. See [hardware evidence](docs/hardware.md).

## Proven reset correction

**CONFIRMED:** Windows HardwareID 3 uses GPIO264 `HIGH` for 10 ms, then `LOW` for 100 ms, ending `LOW`. This replaces the obsolete LOW-to-HIGH reset story. The observed electrical response on the GPIO48 IRQ line/pad is not proof of protocol acceptance. See [hardware](docs/hardware.md) and [safety](docs/safety.md).

## Proven Milan transport summary

**CONFIRMED:** a physical Windows write uses separate outer-header and inner-packet SPI transactions, separate chip-select cycles, and a 2 ms delay. Milan reads are IRQ-driven and exact-length; see [protocol evidence](docs/protocol.md).

## Latest live result

**CONFIRMED:** every controlled Linux SPI submission returned `0`, but GPIO48 did not transition, IRQ remained low, and the single four-byte read was `FF FF FF FF`. No second read and no firmware operation occurred. Controller submission is not MCU acceptance.

## Current boundary

**CONFIRMED:** 1.1.141.36 independently corroborates the 1.1.141.40 `GetEvkVersion` behavior and closes RX classification: B/0 with payload byte `A8` is the ACK for A/4, while A/4 is the EVK response that signals event 9. Both builds pass the two A/4 payload bytes from storage not initialized in the visible function. The target laptop has passed the passive hardware preflight and now also validates the exact-length RX drain model under GCC, Clang+ASan/UBSan and GCC `-fanalyzer`. The next gate is a reviewed Linux active-research backend that connects the already-tested state machine to real spidev exact reads and GPIO48 readiness without introducing reset or firmware APIs; see [protocol](docs/protocol.md), [1.1.141.36 cross-check](docs/windows-14136-crosscheck.md), [cross-machine research](docs/cross-machine-research.md), and [handoff](PROJECT_HANDOFF.md).

## Repository map

- [Hardware evidence](docs/hardware.md) — ACPI, GPIO, reset facts.
- [Protocol evidence](docs/protocol.md) — Milan framing and bounded reads.
- [Windows fallback analysis](docs/windows-fallback.md) — retry provenance, D0Exit gate, and exact control flow.
- [Windows 1.1.141.36 cross-check](docs/windows-14136-crosscheck.md) — independent A/4/ACK/RX corroboration.
- [Cross-machine research](docs/cross-machine-research.md) — same/sibling Huawei Goodix devices and comparison priority.
- [Research log](docs/research-log.md) — append-only chronology.
- [Safety policy](docs/safety.md) — prohibited procedures and experiment gate.
- [Architecture](docs/architecture.md) — staged Linux integration.
- [Research transport](research/README.md) — off-hardware-tested Milan core plus passive spidev/libgpiod preflight.
- [Contributing](CONTRIBUTING.md) — evidence and reporting requirements.

## Staged roadmap

ACPI ownership → temporary minimal SPI/libgpiod research transport → validated Milan state machine → libfprint → fprintd → KDE/GNOME/PAM login and sudo. See [architecture](docs/architecture.md).

## Reference projects

- [berkekbgz/libfprint-goodix-spi](https://github.com/berkekbgz/libfprint-goodix-spi) is a transport precedent.
- [buxel/libfprint-27c6-5110](https://github.com/buxel/libfprint-27c6-5110) is relevant only to higher GF3658 image/matcher/TLS layers, never its USB firmware workflow.

## License

GPL-2.0-only research documentation and future Linux integration work. See [LICENSE](LICENSE).
