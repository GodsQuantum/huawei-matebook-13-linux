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

**CONFIRMED:** the exact RX drain and level-only Linux active backend are validated off-hardware, and the single-purpose live-probe harness now also passes GCC, Clang+ASan/UBSan and GCC `-fanalyzer` on the target laptop. The real harness links against libgpiod 2.3.1 but has not been executed. GPIO264 is accepted only when firmware already exposes it as a free active-high OUTPUT, then requested `AS_IS`; the harness performs the proven HIGH 10 ms -> LOW 100 ms reset, keeps the historical DriverState:Install preamble fixed, runs exactly one `GetEvkVersion` logical attempt, and repeats the proven reset unconditionally during cleanup. A live probe remains **not authorized** until the independent external supervisor/restore fail-safe is validated.

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
