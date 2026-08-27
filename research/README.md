# Safe Milan transport research

This directory contains the evidence-gated research implementation. It is not
a fingerprint driver and exposes no firmware-management API.

## Protocol core

- `milan_packet.*` builds only the confirmed NOP packet and OTHER A/4 packet.
  There is deliberately no generic Milan command encoder or firmware command
  API. The two A/4 payload bytes must be supplied explicitly by the caller.
- `milan_attempt.*` models one `GetEvkVersion` transport attempt: NOP, 5 ms
  delay, A/4, ACK wait, at most one A/4 retransmission on ACK timeout, then a
  separate response wait on logical event 9.
- `milan_rx.*` is the restricted receive parser for that path. It validates the
  outer A header and exact body length, validates the inner checksum, explicitly
  recognizes `FF FF FF FF` as the no-data stop sentinel, classifies B/0 messages
  targeting packed command `A8` as A/4 ACKs, and classifies A/4 as the separate
  EVK response. Fragmented frames are intentionally rejected for now.
- `milan_rx_drain.*` is the off-hardware exact-length drain/state adapter used by
  `milan_attempt.*`. It waits for readiness, reads exactly four header bytes,
  stops terminally on `FF FF FF FF`, reads exactly the announced body, classifies
  ACK/response frames, permits ACK and response in one IRQ-high window, and
  invalidates a response cached before an ACK timeout before retransmission.
- The model uses the effective 1000 ms minimum ACK and response timeouts
  observed in Goodix FP `1.1.141.40`, not merely the 100 ms / 500 ms values
  requested by `GetEvkVersion`.

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

The passive target-hardware preflight and the exact-length RX drain/state model
are complete. The narrow Linux active-research backend is also implemented and
validated off-hardware. It composes:

- the restricted NOP/A4 packet builders;
- the one-attempt `GetEvkVersion` state machine;
- exact spidev write/read primitives;
- the restricted RX drain;
- GPIO48 input-level readiness using bounded 5 ms polling.

The backend deliberately does **not** request GPIO edge detection. The target
GPIO48 pad is ACPI level-triggered ActiveHigh and firmware configuration-locked,
so readiness is determined only from the current input level.

The new runtime has no GPIO264/reset API, no firmware API, no DriverState
fallback and no full common-init fallback. No active runtime was executed
during its validation.

The next gate is a separately reviewed one-purpose live-probe harness containing
the proven GPIO264 reset/cleanup and fixed DriverState:Install preamble around
exactly one `GetEvkVersion` attempt. That harness must pass fake/off-hardware
tests before any real transfer is authorized.
