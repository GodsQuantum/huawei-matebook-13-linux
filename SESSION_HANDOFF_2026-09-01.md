# Session handoff — 2026-09-01

You are continuing reverse engineering of the Goodix `GXFP51A0` / GF3658 Milan fingerprint sensor for Linux.

## Mission

Reach stable, generic, upstream-friendly Linux support, preferably:

```text
validated Milan transport/state machine
-> libfprint SPI integration
-> fprintd
-> desktop/PAM
```

No firmware flashing is part of this project.

Repository:

`https://github.com/GodsQuantum/huawei-matebook-fingerprint-linux`

The public base before this documentation update was:

`061923a8ed87f9ec214dbd0adb7c7695ab81d141` — `research: prepare native IRQ probe4`

Always verify the current remote `main` instead of assuming that SHA is still HEAD.

## Read order

1. `docs/reassessment-2026-09-01.md`
2. `PROJECT_HANDOFF.md`
3. `docs/state-of-research-2026-08-31.md`
4. `docs/safety.md`
5. `docs/protocol.md`
6. the tail of `docs/research-log.md`

The 2026-09-01 reassessment supersedes older statements that Probe #4 was only prepared.

## Confirmed hardware/protocol boundary

- Goodix `GXFP51A0`, GF3658 / Milan.
- ACPI device `\_SB.PCI0.SPI1.SPBA`.
- SPI1 CS0, mode 0, 8 bits, 10 MHz, four-wire.
- GPIO48 = ActiveHigh level readiness/IRQ.
- Linux ACPI IRQ mapping = hwirq 48, `LEVEL_HIGH`; Linux virtual IRQ is dynamic.
- GPIO264 reset/restoration = HIGH 10 ms -> LOW 100 ms -> final LOW.
- DriverState:Install = `(9,3)` / packed `0x96`.
- B/0 payload[0] identifies ACK target.
- DriverState effective ACK timeout >= 1000 ms.
- Maximum silent DriverState path = four Install sends, then conditional hard reset.
- `GetEvkVersion` = NOP -> 5 ms -> A/4; one A/4 retransmission after first ACK timeout; separate response event after ACK.
- A/4 payload `00 00` is only a Linux fixture.

## Probe #4 is complete and negative

Fresh-boot, one-shot native-IRQ result:

```text
DRIVERSTATE_RESULT=ACK_TIMEOUT
DRIVERSTATE_RESET_PERFORMED=YES
SPI_TRANSFER_COUNT=16
IRQ_WAIT_COUNT=6
IRQ_EVENT_COUNT=0
SPI reads=0
EVK_RESPONSE_LEN=0
cleanup=successful
```

Therefore:

- userspace GPIO polling was not the cause of the silence;
- native ACPI IRQ waiting also sees no Goodix readiness;
- do not rerun Probe #3 or Probe #4.

## Controller-side postmortem

The Intel LPSS/PXA2xx controller stack accounts for the submitted work and its interrupt accounting correlates with the 16 transactions.

That is controller-side evidence only. It does not prove electrical reachability or MCU acceptance.

Runtime autosuspend after the run is normal. Do not force power/control on without new evidence.

## Probe #5 / ftrace

Several Probe #5 attempts failed in trace/preflight configuration before any new sensor transaction.

Do not interpret them as hardware results.

Ftrace is deprioritized for now because the main unresolved boundary has moved below protocol/readiness into physical/platform SPI reachability.

## New GF3658 Windows transport proof

Goodix FP `1.1.141.36` `gfspi.dll` SHA-256:

`4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`

`SpiSendDataToDevice -> 0x180007e60` dispatches by transport/hardware mode.

For modes `2`, `3`, `5` the binary performs:

```text
transfer(buffer, 4)
Sleep(2)
transfer(buffer + 4, len - 4)
```

Modes `0/1` use one full transfer; mode `6` has a separate path.

The split calls go through `0x180008b68 -> 0x180009c34`.

This independently validates the existence of the 4-byte outer + 2 ms + inner transport path in the GF3658 Windows binary.

Still unresolved:

1. prove which runtime mode GXFP51A0 selects;
2. follow `0x180009c34` to the final Windows/SPB I/O primitive.

Do not claim those two points are already closed.

## Rejected/deprioritized hypotheses

- unconditional reset before DriverState: rejected;
- GPIO userspace polling missed readiness: rejected by Probe #4;
- generic Goodix wake/chip-ID command before DriverState: unsupported;
- missing 1 ms pre-submit delay: unsupported by the GF3658 1.1.141.36 path;
- forcing LPSS runtime PM on: unjustified;
- further ftrace work before resolving physical reachability: low priority.

## Exact next task

Do not touch the sensor immediately.

1. Resolve the GF3658 hardware-mode string/value mapping and tie it to GXFP51A0.
2. Follow `0x180008b68 -> 0x180009c34` to the final SPB primitive.
3. Reconcile that with the already implemented Linux two-transfer transport.
4. If software transaction boundaries remain correct, move to the most direct physical discriminator: read-only pin/pad/controller evidence or external logic analyzer/scope on CS/SCLK/MOSI/MISO.
5. No new Goodix command is justified until this is resolved.
6. Once a real ACK is obtained, move toward libfprint rather than growing a permanent bespoke research harness.

## Non-negotiable safety

- No flash/UPFW/erase/bootloader/firmware-management.
- No speculative pinmux writes.
- No unmodified OpenGoodixSPI/goodix-fp-dump full-device flows.
- Exact-length RX only.
- `FF FF FF FF` is terminal for that read.
- Fresh-state/one-shot discipline when an active experiment depends on initial state.
- Independent supervisor and final GPIO264 LOW restoration for any future live probe.
- Never publish raw `_DSM`, PSKs, proprietary Windows binaries, raw disassembly, local paths, usernames, boot IDs or private diagnostics.

## Collaboration style

- French, direct, technical.
- One CLI block per step.
- Diagnostic-first.
- No repeated active hardware probe on the same boot after an active action.
- Push meaningful, sanitized milestones regularly.
