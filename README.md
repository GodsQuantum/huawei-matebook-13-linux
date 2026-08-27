# Goodix GXFP51A0 / GF3658 Milan on Linux

> **Experimental research only — safety first.** No working fingerprint driver exists. Do not flash firmware, run an unreviewed probe, or interact with the sensor outside a reviewed, minimal experiment.

> Version française : [README.FR.md](README.FR.md)

## Status


**CONFIRMED:** no working fingerprint driver exists yet. The first supervised
one-shot live probe has been executed without firmware activity. GPIO48 remained
LOW through the DriverState and A/4 ACK windows, so the exact-length RX gate
performed zero SPI reads. Static follow-up established that the probe's
historical DriverState preamble was incomplete: DriverState:Install uses generic
B/0 ACK bookkeeping for CHIP 9/3, an effective 1000 ms ACK window, one exact
retransmission per transport call, two wrapper calls, and a hard reset only
after both wrapper calls fail. That corrected model is now validated
off-hardware on the target laptop. No probe #2 has been executed.

## Confirmed platform summary

Huawei MateBook 13 2021: DMI `WRTB-WXX9`, version `M1020`, board `WRTB-WXX9-PCB`, BIOS Huawei `1.26`, CachyOS, last tested kernel `7.2.0-1-cachyos`. The ACPI/SPI Goodix `GXFP51A0` is a GF3658 Milan sensor. See [hardware evidence](docs/hardware.md).

## Proven reset correction

**CONFIRMED:** Windows HardwareID 3 uses GPIO264 `HIGH` for 10 ms, then `LOW` for 100 ms, ending `LOW`. This replaces the obsolete LOW-to-HIGH reset story. The observed electrical response on the GPIO48 IRQ line/pad is not proof of protocol acceptance. See [hardware](docs/hardware.md) and [safety](docs/safety.md).

## Proven Milan transport summary

**CONFIRMED:** a physical Windows write uses separate outer-header and inner-packet SPI transactions, separate chip-select cycles, and a 2 ms delay. Milan reads are IRQ-driven and exact-length; see [protocol evidence](docs/protocol.md).

## Latest live result


**CONFIRMED:** the first supervised one-shot probe completed its bounded path
and cleanup. Twelve physical SPI write transactions were submitted: the
historical DriverState preamble, one `GetEvkVersion` attempt, and the single A/4
retransmission allowed by the model. GPIO48 remained LOW throughout, so the
exact-length RX gate correctly performed **zero SPI reads**. A/4 ended in ACK
timeout after its one retransmission. Internal cleanup restored GPIO264 LOW and
the supervisor restored the temporary spidev state. No firmware operation
occurred. Controller submission is not MCU acceptance.

## Current boundary


**CONFIRMED:** DriverState is no longer represented by fixed 100 ms sleeps.
Generic B/0 ACK handling now matches the packed command being acknowledged;
DriverState:Install targets `0x96` (CHIP 9/3), waits the effective 1000 ms ACK
window, permits one exact retransmission per wrapper call, makes at most two
wrapper calls, and performs the proven hard reset only after both calls time
out. The target-laptop offline gate passes GCC, Clang+ASan/UBSan, GCC
`-fanalyzer`, source-safety/privacy checks, and real libgpiod 2.3.1 build/link
without executing those binaries.

The independent supervisor now requires the probe-#2 confirmation token
`GXFP51A0_REVIEWED_PROBE_2` and uses a 12-second wall-clock timeout while
retaining TERM/KILL fail-safe handling, cleanup-marker verification,
GPIO264-only restore fallback, and unconditional spidev restoration. The next
gate is final review of this exact corrected command path, followed by at most
one supervised probe #2. Firmware operations and the full three-attempt
common-init fallback remain excluded.

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
