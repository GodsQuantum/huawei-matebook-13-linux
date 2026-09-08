# Project handoff — GXFP51A0 / GF3658 Milan Linux driver research

## Canonical current state

<!-- canonical-2026-09-08 -->
Current canonical boundary:

- [Session handoff — 2026-09-08](SESSION_HANDOFF_2026-09-08.md)
- [Current boundary — 2026-09-08](docs/current-boundary-2026-09-08.md)
- [Windows .36 → .40 differential](docs/windows-14136-14140-differential-2026-09-08.md)
- [Buildable libfprint candidate](driver/goodix51a0/)

The GXFP51A0 candidate compiles and links against libfprint v1.94.100, but target communication remains silent.

Later 2026-09-08 closures: exact-target ACPI/LPSS hidden-switch search and GPIO112 hypothesis are closed; `.36/.40` comparison is grounded by PE `.pdata`; WdfInterruptCreate is already present in `.36`; `.40` helper `0x18000a71c` is logging; WakeupMCU/DriverState/GetEvkVersion/GPIO paths are stable; `init_MCU` changes are dominated by firmware-policy branches.

Do not repeat unchanged common-init. The next work item is one broad Windows lifecycle/SPB reconstruction through the first Milan transfer followed by a Windows/Linux parity matrix. Only exact-device `MISSING` or materially `DIFFERENT` prerequisites should trigger implementation or a fresh active experiment.

<!-- canonical-2026-09-07 -->
Current canonical boundary:

- [Session handoff — 2026-09-07](SESSION_HANDOFF_2026-09-07.md)
- [Current boundary — 2026-09-07](docs/current-boundary-2026-09-07.md)

The complete common-init, DMA/PIO, normal-DMA trace, runtime-PM-held and
same-wire MISO discriminators are complete. Latest result: 180/180 retained RX
bytes `0xFF`, exactly 34 concrete target iDMA IRQ completions, 0 Goodix IRQs,
no trace loss. No new active probe without same-device evidence.

<!-- canonical-2026-09-03 -->
Current canonical boundary:

- [Session handoff — 2026-09-03](SESSION_HANDOFF_2026-09-03.md)
- [Controller boundary — 2026-09-03](docs/controller-boundary-2026-09-03.md)
- [DMA / PIO reassessment — 2026-09-02](docs/dma-pio-reassessment-2026-09-02.md)

The deterministic PIO discriminator is complete and must not be rerun merely
to reconfirm the same silent result. DMA versus PIO is closed as the primary
explanation. The next gate is passive, root-privileged tracefs enumeration,
followed by one bounded unchanged common-init run with controller/runtime-PM
instrumentation only.


Read first:

- [Session handoff — 2026-09-01](SESSION_HANDOFF_2026-09-01.md)
- [Reassessment — 2026-09-01](docs/reassessment-2026-09-01.md)
- [State of research — 2026-08-31](docs/state-of-research-2026-08-31.md)
- [Hardware evidence](docs/hardware.md)
- [Protocol evidence](docs/protocol.md)
- [Safety policy](docs/safety.md)
- [Research log](docs/research-log.md)

There is now a buildable GXFP51A0 libfprint candidate, but no hardware-functional Linux fingerprint driver yet.

The intended end state remains:

```text
validated GXFP51A0 Milan transport
-> libfprint
-> fprintd
-> desktop/PAM integration
```

## Strongest confirmed facts

- Goodix `GXFP51A0`, GF3658 / Milan family.
- ACPI `\_SB.PCI0.SPI1.SPBA`.
- SPI1 CS0, mode 0, 8-bit, 10 MHz, four-wire.
- GPIO48 is level-triggered ActiveHigh readiness/IRQ.
- Linux resolves ACPI `GpioInt[0]` to hardware IRQ 48 with `LEVEL_HIGH`; the Linux virtual IRQ is dynamic and must never be hardcoded.
- GPIO264 reset is HIGH 10 ms -> LOW 100 ms -> final LOW.
- Milan framing is outer header + inner packet; the Windows GF3658 transport contains a split-write path that transfers 4 bytes, waits 2 ms, then transfers the remaining bytes.
- DriverState:Install is logical `(9,3)`, packed `0x96`.
- B/0 `payload[0]` identifies the command being acknowledged.
- A silent DriverState path can submit at most four Install packets before its conditional hard reset.
- `GetEvkVersion` is NOP -> 5 ms -> A/4, with one exact A/4 retransmission after first ACK timeout and a separate response-event phase after ACK.
- Linux A/4 `00 00` remains only a deterministic research fixture.

## Latest active result: Probe #4

Probe #4 was executed once on a fresh boot. Relative to Probe #3 it changed only readiness handling: userspace GPIO48 polling was replaced by the native kernel ACPI IRQ wait.

Result:

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

The native IRQ path remained completely silent. Therefore the hypothesis that userspace GPIO polling was missing a readiness transition is rejected.

Do not rerun Probe #3 or Probe #4.

## Linux controller boundary

Passive postmortem correlates the 16 submitted transactions with activity in the Intel LPSS / PXA2xx SPI controller stack. Runtime autosuspend after the probe is normal and is not evidence that the controller stayed asleep during submissions.

This proves progressively more of the Linux software/controller path, but it still does not prove that correct CS/SCLK/MOSI waveforms reach the Goodix MCU or that MISO/IRQ physically respond.

Do not force runtime PM or modify pinmux without stronger evidence.

## Probe #5 / ftrace status

Probe #5 was designed as Probe #4 plus tracing only.

Its attempts failed in trace/preflight setup before any new sensor SPI transaction. One attempt loaded the native IRQ bridge and partially configured ftrace, then cleaned up without protocol traffic.

These attempts provide no new sensor-side result.

Ftrace is currently deprioritized because it would mostly add controller-side software evidence while the unresolved boundary is increasingly physical/platform reachability.

## Windows GF3658 transport reassessment

Static analysis of Goodix FP `1.1.141.36` `gfspi.dll` SHA-256:

```text
4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59
```

shows that `SpiSendDataToDevice` passes the complete frame to helper `0x180007e60`, which dispatches on a hardware/transport mode.

Visible behavior:

```text
mode 0 or 1:
    transfer(buffer, full_length)

mode 2, 3 or 5:
    transfer(buffer, 4)
    Sleep(2 ms)
    transfer(buffer + 4, full_length - 4)

mode 6:
    separate special path
```

Both split-path calls go through `0x180008b68`, which delegates to common SPB helper `0x180009c34`.

This independently corroborates the existing `outer 4 bytes -> 2 ms -> inner` Milan model.

Two static points remain deliberately unresolved:

1. tie GXFP51A0's runtime hardware-mode selector directly to its matching mode value;
2. follow `0x180009c34` to the final Windows/SPB I/O primitive and close the transaction/CS boundary there.

The same audit rejects the proposed “missing 1 ms pre-submit delay” hypothesis for this GF3658 path. The visible 15 ms / 50 ms sleeps belong to ACK/response waiting, not to a proven initial SPI delay.

## Public-source reassessment

A separate 2026 Goodix SPI/libfprint effort independently corroborates the same broad Milan-style framing and logical command family:

<https://github.com/berkekbgz/libfprint-goodix-spi>

Use it only as corroboration. Do not copy unrelated startup, firmware or wake sequences onto GXFP51A0.

Generic OpenGoodixSPI-style wake/chip-ID commands remain unsupported for the first GXFP51A0 startup path and must not be prepended without same-device proof.

## Exact next boundary

No new protocol command and no repeat of Probe #3/#4 is authorized.

Continue with the shortest discriminating path:

1. statically map the GF3658 transport-mode selector to GXFP51A0;
2. statically follow `0x180008b68 -> 0x180009c34` to the final SPB write/read primitive;
3. if the GXFP51A0 split-write path is fully closed, stop spending live probes on timing;
4. prefer read-only controller/pinctrl inspection or an external logic analyzer/oscilloscope to prove physical CS/SCLK/MOSI/MISO behavior;
5. only after a credible ACK/response exists, migrate the validated state machine to libfprint SPI helpers and then fprintd.

## Privacy rules

Never commit:

- local usernames or personal filesystem paths;
- machine nicknames or boot IDs;
- local IP addresses or unrelated hardware inventory;
- raw `_DSM` payloads, PSKs or derived keys;
- proprietary Windows binaries, firmware, raw generated disassembly or private diagnostics.

Only sanitized, generic research facts belong in the public repository.

## Safety

No firmware flashing, UPFW, erase, bootloader, firmware-management flow, speculative pinmux write or unrelated USB Goodix firmware procedure is authorized.

Any future active experiment requires one reviewed hypothesis, minimum bounded writes, exact-length RX, independent supervision, explicit stop conditions and final GPIO264 LOW restoration.

<!-- current-boundary-2026-09-02 -->
## 2026-09-02 correction

`send_driver_install_to_MCU()` does not propagate the `SetDriverState()` result
as the startup gate. Windows continues to `init_MCU()`, whose first meaningful
sensor-response gate is `GetEvkVersionWithRetry`.

Exact Goodix FP 1.1.141.36 common-init default:

- 3 GetEvkVersion attempts;
- HardResetMcu after all three fail when D0Exit has not started;
- reset BOOL ignored by the wrapper;
- one final GetEvkVersion.

The Linux research harness now models this exact control flow. Maximum fully
silent default path: 34 SPI transfers.

Canonical current state: `docs/software-boundary-2026-09-02.md`.

<!-- common-init-live-closure-2026-09-02 -->
## 2026-09-02 live common-init closure

The corrected Windows-faithful common-init sequence has now executed to
completion on Linux.

Observed complete-silence result:

- 34 SPI transfers;
- 12 IRQ waits;
- 0 Goodix IRQ events;
- 0 reads / 0 EVK response bytes;
- DriverState fallback reset succeeded;
- common-init fallback reset succeeded;
- no SPI-controller error or timeout;
- final GPIO264 LOW cleanup succeeded.

The remaining problem is below the reconstructed common-init protocol flow.

Current discriminator: PXA2xx/LPSS DMA versus PIO.

A simple IDMA64 blacklist must not be assumed sufficient. The next experiment must first establish and prove a deterministic PXA2xx PIO-only state, using boot-time binding control or a minimal instrumented controller variant if necessary, and abort before sensor traffic unless PIO is proven.

Canonical next-boundary document:
`docs/dma-pio-reassessment-2026-09-02.md`.

<!-- operational-boundary-2026-09-07 -->
## Operational boundary — 2026-09-07

Earlier DMA/PIO/runtime-PM "next step" sections are historical. Current rule: no new active GXFP51A0 traffic without same-device evidence; static/pre-first-command analysis first. See `docs/current-boundary-2026-09-07.md`.
