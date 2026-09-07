# Goodix GXFP51A0 / GF3658 Milan on Linux

> Experimental reverse-engineering research. There is no working Linux fingerprint driver yet. Do not flash firmware or run unreviewed vendor flows.

> Version française: [README.FR.md](README.FR.md)

## Current status

<!-- current-status-2026-09-08 -->
### Current boundary — 2026-09-08

The project now has a **GXFP51A0 libfprint v1.94.100 candidate that compiles and
links successfully**, including the real driver object/type in libfprint.
This closes the software/build integration blocker, not the hardware blocker.

The sensor still produces no accepted ACK/A8 response under Linux. The already
validated common-init remains 34 transfers, 0 Goodix IRQ and 180 retained RX
bytes all `0xFF`; DMA/PIO, runtime-PM, IRQ mapping and mode-5 split timing are
already closed.

A focused r2ghidra pass also partially resolves the Windows `_DSM` envelope:
variable payload length is encoded in the first returned DWORD and payload
starts at offset +4. A fixed 48-byte GXFP51A0 PSK is **not proven**; the
candidate keeps sibling PSK/config/TLS behavior gated.

Do not repeat the same active common-init. The highest-value next evidence is a
working-Windows SpbCx/WDF/WPP/ETW trace, then physical
CS/SCLK/MOSI/MISO/IRQ comparison if necessary.

See [`docs/current-boundary-2026-09-08.md`](docs/current-boundary-2026-09-08.md)
and [`driver/goodix51a0/`](driver/goodix51a0/).

<!-- controller-status-2026-09-03 -->
### Controller result — 2026-09-03

The deterministic PXA2xx DMA-versus-PIO discriminator is complete.

A fresh boot proved the controller's native PIO fallback before any fingerprint
traffic: IDMA64 was absent, the matching controller logged
`no DMA channels available, using PIO`, and target SPI statistics were zero.
The unchanged Windows-faithful common-init then again completed 34 physical SPI
transfers and 12 waits with 0 Goodix IRQ events, 0 RX reads and 0 EVK response
bytes. Both fallback resets succeeded, the controller reported no SPI
error/timeout, and final GPIO264 cleanup was LOW.

A separate normal-boot passive baseline confirmed IDMA64 loaded and bound, two
DMAengine channels associated with the matching LPSS PCI parent, no PIO
fallback, and zero prior GXFP51A0 SPI activity.

DMA versus PIO is therefore closed as the primary explanation for the current
silence. The next software boundary is runtime-PM / LPSS / PXA2xx transfer
instrumentation.

See
[`docs/controller-boundary-2026-09-03.md`](docs/controller-boundary-2026-09-03.md)
and
[`SESSION_HANDOFF_2026-09-03.md`](SESSION_HANDOFF_2026-09-03.md).


Confirmed work includes ACPI/SPI/GPIO mapping, Milan framing, proven reset behavior, exact-length readiness-driven RX, DriverState ACK/retry/reset reconstruction, `GetEvkVersion` ACK/response reconstruction, native ACPI IRQ mapping, supervised Linux probes through Probe #4, the Goodix-specific ACPI `_DSM`, Windows startup reconstruction and a lower-level GF3658 Windows transport cross-check.

**Latest live result:** the complete corrected Windows-faithful common-init path has now run once on a fresh boot: 34 SPI transfers, 12 IRQ waits, 0 Goodix IRQ events, 0 reads and 0 EVK response bytes. Both fallback resets completed successfully, controller statistics reported no SPI error/timeout, and final GPIO264 cleanup was confirmed LOW.

See:

- **[State of research — 2026-08-31](docs/state-of-research-2026-08-31.md)**
- **[Reassessment — 2026-09-01](docs/reassessment-2026-09-01.md)**

## Important Windows startup result

```text
MilanEvtDeviceD0Entry
  -> _StartInitThread
      -> InitThread
          -> _DeviceInit
              -> send_driver_install_to_MCU
                  -> SetDriverState(9,3 / 0x96)
              -> init_MCU
                  -> GetEvkVersionWithRetry
          -> later SGX/TLS/PSK work
```

DriverState therefore occurs before the visible EVK query and before the later TLS/PSK stage.

## GF3658 transport cross-check

Goodix FP `1.1.141.36` contains a transport path that performs:

```text
transfer first 4 bytes
wait 2 ms
transfer remaining bytes
```

for transport modes `2`, `3` and `5`. This independently corroborates the existing outer/inner Milan model.

Those static transport tasks are now closed for this target: GXFP51A0 selects mode 5 and the final Windows path uses separate synchronous SPB writes for the outer 4 bytes and remaining packet bytes, separated by 2 ms.

## ACPI `_DSM`

UUID:

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

Function 1 returns a 2048-byte `HWFP/FPDT` buffer. Linux can evaluate it successfully and Windows identifies this path as a PSK source.

**The raw DSM payload and any PSK are private per-machine material and are not part of this repository.**

## Current research question

Why does a controller-validated Windows-faithful GXFP51A0 sequence produce no informative MISO data and no readiness IRQ?

Current priority: static/pre-first-command Goodix FP 1.1.141.36 analysis and evidence-backed comparison with working sibling drivers. No forced sibling binding and no new active probe without one precise same-device hypothesis.

See [`docs/current-boundary-2026-09-07.md`](docs/current-boundary-2026-09-07.md).

## Repository map

- [Current state](docs/state-of-research-2026-08-31.md)
- [2026-09-01 reassessment](docs/reassessment-2026-09-01.md)
- [DMA / PIO reassessment — 2026-09-02](docs/dma-pio-reassessment-2026-09-02.md)
- [Project handoff](PROJECT_HANDOFF.md)
- [Session handoff](SESSION_HANDOFF_2026-09-02.md)
- [Hardware](docs/hardware.md)
- [Protocol](docs/protocol.md)
- [Windows fallback](docs/windows-fallback.md)
- [Windows 1.1.141.36 cross-check](docs/windows-14136-crosscheck.md)
- [Cross-machine research](docs/cross-machine-research.md)
- [Research log](docs/research-log.md)
- [Safety](docs/safety.md)
- [Architecture](docs/architecture.md)
- [Research transport](research/README.md)
- [Contributing](CONTRIBUTING.md)

## Target architecture

```text
validated Linux Milan transport
-> libfprint
-> fprintd
-> KDE/GNOME/PAM login and sudo
```

## Safety

Firmware flashing, UPFW, erase, bootloader programming and unrelated USB Goodix firmware procedures are outside the research boundary.

See [docs/safety.md](docs/safety.md).

## License

GPL-2.0-only. See [LICENSE](../LICENSE).

<!-- current-boundary-2026-09-02 -->
## Current research boundary — 2026-09-02

The Windows startup reconstruction has been corrected: `DriverState:Install`
is not the fatal `_DeviceInit` gate. The first meaningful sensor-response gate
is `GetEvkVersionWithRetry`, whose exact 1.1.141.36 default outer retry count
is 3, followed by a separate hard-reset fallback and one final attempt.

A live Linux trace also confirmed the tested transfers reach the LPSS
`lpss_ssp_cs_control` path.

See [`docs/software-boundary-2026-09-02.md`](docs/software-boundary-2026-09-02.md).
