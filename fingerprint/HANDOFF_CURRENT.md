# Current handoff — GXFP51A0 / GF3658 Milan

**Updated: 2026-09-14 after first Linux ACK / EVK and target-config confirmation.**

This is the shortest canonical resume point. The historical 2026-09-08
checkpoint remains in [FINAL_HANDOFF_2026-09-08.md](FINAL_HANDOFF_2026-09-08.md).
The decisive first-contact evidence is documented in
[docs/first-contact-confirmed-2026-09-14.md](docs/first-contact-confirmed-2026-09-14.md).

## Current state

```text
candidate libfprint v1.94.100 build       PASS
first-contact source regression           PASS
research unit/safety suite                PASS
Windows .36/.40 first-contact diff        CLOSED
DeviceInit/BESD intermediate action       CLOSED_NO_SENSOR_IO
SPB first-contact split-write boundary    MATCHED_HIGH_CONFIDENCE
first real sensor ACK under Linux         CONFIRMED
A8 ACK                                    CONFIRMED
a8 firmware/EVK response                  CONFIRMED
firmware                                  GF_ST411SEC_APP_14115
target config                              CONFIRMED ON HARDWARE
TLS/PMK                                   NEXT BOUNDARY
image/capture                             NOT REACHED
```
## Confirmed Linux operating recipe

The previous normal-CS 34-transfer run is now a historical negative control.
First contact was reproduced on a MateBook 13 2021 using:

```text
GPIO264 HIGH 300 ms        active MCU reset
GPIO264 LOW                MCU running
settle after LOW           600 ms
SPI CPOL/CPHA              mode 0
Linux CS mode bit          SPI_CS_HIGH (0x04)
SPI rate                   1 MHz (currently proven rate)
final GPIO264              LOW
```

Positive A8 ACK:

```text
a0 06 00 a6 b0 03 00 a8 03 4c
```

Positive EVK response contains `GF_ST411SEC_APP_14115`.
The identical command sequence with normal Linux CS polarity produced only
idle bytes.
## Candidate changes on the current branch

The branch `research/gxfp51a0-config-tls` now carries both the confirmed
first-contact transport and the exact-target ChicagoHS configuration path:

- initial spidev configuration: mode 0 + `SPI_CS_HIGH`;
- recovery reopen: same mode;
- SPI rate: 1 MHz until a separate higher-rate test proves 10 MHz on Linux;
- reset helper: HIGH 300 ms -> LOW -> 600 ms settle;
- source and research regressions assert those values;
- target soft reset A2, chip ID 0x2504 and 64-byte OTP parsing;
- OTP-derived tcode/FDT/DAC calibration;
- exact 256-byte target config patch/checksum/upload;
- runtime config path enabled before TLS.

TLS/PMK remains deliberately gated. No firmware or PMK write path is enabled.

## Software validation

Canonical software-only validation remains:

```bash
make -C fingerprint verify
```

Before merging/pushing this branch, require a fresh PASS of the complete
research suite, source manifest, libfprint v1.94.100 build, privacy gate and
`git diff --check`.

## Next boundary

First-contact transport is no longer the blocker. Work in this order:

1. resolve the target PMK read path using the exact ST411 firmware evidence;
2. establish the TLS-PSK handshake;
3. capture and decode the first 80x64 image;
4. enrol/verify;
5. fprintd/PAM/desktop integration.
## Do not reopen without new evidence

- DMA versus PIO;
- runtime PM as primary cause;
- Linux IRQ mapping;
- userspace polling versus native IRQ wait;
- DeviceInit `besdenable` as missing sensor I/O;
- GPIO112/GPP_D16 or hidden LPSS switch;
- unchanged normal-CS 34-transfer replay;
- fixed 48-byte GXFP51A0 PSK assumption.

The CS-polarity conclusion is now positive hardware evidence: do not revert to
normal Linux CS polarity based only on ACPI `PolarityLow` wording.

## Canonical files

1. `HANDOFF_CURRENT.md`
2. `docs/first-contact-confirmed-2026-09-14.md`
3. `docs/target-config-confirmed-2026-09-14.md`
4. `driver/goodix51a0/README.md`
4. `docs/current-boundary-2026-09-08.md`
5. `docs/deviceinit-besd-spb-closure-2026-09-08.md`
6. `docs/windows-14136-14140-differential-2026-09-08.md`
7. `docs/research-log.md`
8. `FINAL_HANDOFF_2026-09-08.md` (historical checkpoint)
9. `docs/safety.md`

## Public-repository locks

No proprietary binaries/firmware, raw DSM material, PSK/derived keys, private
machine identifiers or bulk proprietary disassembly.

No firmware/PSK write, speculative MMIO/pinmux write or GPIO112 write without
new exact-target evidence. Every active experiment must leave GPIO264 LOW.
