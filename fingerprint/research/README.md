# Safe Milan transport research

This directory contains the evidence-gated research implementation. It is not
a fingerprint driver and exposes no firmware-management API.

## Protocol core


- `milan_packet.*` builds only the confirmed NOP and OTHER A/4 packets; there is
  no generic firmware command API and A/4 payload bytes remain caller supplied.
- `milan_attempt.*` models one `GetEvkVersion` transport attempt: NOP, 5 ms,
  A/4, effective ACK wait, at most one A/4 retransmission, then response event 9.
- `milan_rx.*` validates the restricted framing and recognizes B/0 as generic
  ACK bookkeeping. Current evidenced targets are `0x96` for
  DriverState:Install (9/3) and `0xA8` for A/4. A/4 itself remains the separate
  EVK response. Fragmented frames are rejected.
- `milan_rx_drain.*` waits for readiness, reads exactly four header bytes,
  stops terminally on `FF FF FF FF`, reads exactly the announced body, and
  matches ACKs to the requested command pair.
- `probe_harness.*` models DriverState:Install with effective 1000 ms ACK waits,
  one exact retransmission per wrapper call, two wrapper calls maximum, and the
  proven hard reset only after both calls time out.

## Linux research transport

- `linux/spidev_discovery.*` discovers the node below
  `/sys/bus/spi/devices/spi-GXFP51A0:00/spidev/`; `/dev/spidev1.0` is never
  hardcoded.
- `linux/linux_spi.*` configures SPI mode 0, 8 bits, 10 MHz and provides
  explicit exact-length transfer primitives. Open/configure performs no
  `SPI_IOC_MESSAGE` transfer.
- `linux/irq_logic.*` implements level-oriented active-high IRQ waiting. An
  edge is only a wakeup; protocol meaning belongs to the Milan parser.
- `linux/gpiod_irq.*` is the passive libgpiod 2.x adapter for `/dev/gpiochip0` offset
  48. It requests a plain input and reads only the current level; it deliberately
  does not arm edge detection. The real edge adapter is deferred until a reviewed
  active experiment. It contains no output GPIO API.

Normal unit tests require no hardware and no libgpiod installation. They also run a source-level passive-safety regression guard that rejects edge/output GPIO APIs and SPI-transfer calls from the passive preflight:

```text
make -C research test
```

Build outputs default to `../../../temp/research-build`, outside the repository.
On the target laptop this corresponds to the project `temp/` area required for all
research-generated files.

## Passive target-hardware gate

`make -C research passive-preflight` requires libgpiod major version 2 and
builds `gxfp-passive-preflight`. Before running it, `spi-GXFP51A0:00` must
already be bound to spidev externally.

The program only:

1. discovers the spidev node;
2. opens it and configures mode 0 / 8 bits / 10 MHz;
3. requests GPIO48 as an input and reads its current level;
4. releases both resources.

It performs **zero SPI transfers** and never requests GPIO264. Success output
must include `SPI_TRANSFER_COUNT=0`, `GPIO264_REQUESTED=NO`, and
`PASSIVE_PREFLIGHT=SUCCESS`.

## Current gate and deliberately excluded work


The first supervised hardware probe has been executed. GPIO48 remained LOW
through its DriverState and A/4 readiness windows, so exact-length RX performed
zero SPI reads; A/4 ended in ACK timeout after its one retransmission. Cleanup
and the external fail-safe restored the proven final states. No firmware
operation occurred.

Static follow-up showed that the historical DriverState preamble used by that
probe was incomplete. The corrected generic-ACK/DriverState retry/reset model is
now validated off-hardware on the target laptop with GCC, Clang+ASan/UBSan,
GCC `-fanalyzer`, source-safety/privacy checks and real libgpiod 2.3.1
build/link without hardware execution.

For probe #2 the supervisor requires `GXFP51A0_REVIEWED_PROBE_2` and uses a
12-second wall-clock timeout while retaining process-group kill, cleanup marker
checks, GPIO264-only restore fallback and unconditional spidev cleanup. Probe #2
has not been executed. Full common-init, firmware management, enrollment and
libfprint integration remain excluded.

<!-- current-boundary-2026-09-02 -->
## Active probe model update — 2026-09-02

The previous assumption that DriverState ACK timeout terminates startup is
obsolete.

The harness now models the Windows common-init wrapper:

- DriverState retries and fallback reset;
- continuation into init_MCU;
- three default GetEvkVersion outer attempts;
- separate common-init HardResetMcu fallback;
- one final GetEvkVersion;
- reset failures preserved diagnostically;
- final cleanup still fail-closed.

Maximum fully silent path: 34 physical SPI transfers.

<!-- dma-pio-boundary-2026-09-02 -->
## DMA / PIO boundary — 2026-09-02

The corrected Windows-faithful common-init path has now executed through all
34 expected SPI transfers and remains silent with 0 Goodix IRQ/RX.

Do not change the Goodix protocol for the next experiment.

The next one-variable test is to prove that the PXA2xx controller is using PIO
before sensor traffic, then replay the exact same bounded sequence once.

See `../docs/dma-pio-reassessment-2026-09-02.md`.

<!-- pio-gate-tooling-2026-09-02 -->
## PIO experiment tooling

`linux/pio_preflight.sh` proves the PXA2xx controller entered its native PIO
fallback before any fingerprint traffic.

`linux/pio_live_probe_supervisor.sh` requires the PIO-specific review token,
runs that preflight first, and only then delegates to the existing supervised
Windows-faithful common-init probe.

The PIO gate itself performs no module load/unload, driver bind/unbind, PM
change, GPIO operation or SPI transfer.

<!-- controller-instrumentation-next-2026-09-03 -->
## Controller instrumentation boundary — 2026-09-03

The deterministic PXA2xx PIO discriminator is complete.

PIO was proven before active traffic and the unchanged common-init remained
fully silent through the same 34-transfer / 12-wait boundary as the normal
DMA path.

Do not rerun the PIO experiment.

The next gate is passive, root-privileged tracefs enumeration on a fresh
zero-activity normal boot. Only after selecting a bounded observation
mechanism should another active common-init execution be authorized.

The future active variable is instrumentation only. Protocol bytes, mode,
speed, Milan split, waits, reset behavior and stop conditions must remain
unchanged.
