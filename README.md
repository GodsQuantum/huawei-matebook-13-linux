# Goodix GXFP51A0 / GF3658 Milan on Linux

> Experimental reverse-engineering research. There is no working Linux fingerprint driver yet. Do not flash firmware or run unreviewed vendor flows.

> Version française: [README.FR.md](README.FR.md)

## Current status

Confirmed work includes ACPI/SPI/GPIO mapping, Milan framing, proven reset behavior, exact-length readiness-driven RX, DriverState ACK/retry/reset reconstruction, `GetEvkVersion` ACK/response reconstruction, native ACPI IRQ mapping, supervised Linux probes through Probe #4, the Goodix-specific ACPI `_DSM`, Windows startup reconstruction and a lower-level GF3658 Windows transport cross-check.

**Latest live result:** Probe #4 replaced userspace GPIO48 polling with the native kernel ACPI IRQ path and remained completely silent: 16 SPI transactions, 6 IRQ waits, 0 Goodix IRQ events, 0 reads and no ACK. This rejects the GPIO-polling hypothesis.

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

The remaining static tasks are to tie GXFP51A0 to its exact runtime transport mode and follow the common SPB helper to the final Windows I/O primitive.

## ACPI `_DSM`

UUID:

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

Function 1 returns a 2048-byte `HWFP/FPDT` buffer. Linux can evaluate it successfully and Windows identifies this path as a PSK source.

**The raw DSM payload and any PSK are private per-machine material and are not part of this repository.**

## Current research question

The main unresolved problem is now below readiness/protocol scheduling: why controller-submitted Linux SPI traffic produces no observable Goodix IRQ/RX.

Probe #3 and Probe #4 are complete and must not be rerun.

Current priority:

1. close the GXFP51A0 Windows transport-mode mapping;
2. close the final Windows SPB leaf below the split-write helper;
3. if Linux transaction boundaries remain correct, move to direct physical SPI observability rather than adding speculative commands.

Do not add generic Goodix wake commands without same-device evidence.

## Repository map

- [Current state](docs/state-of-research-2026-08-31.md)
- [2026-09-01 reassessment](docs/reassessment-2026-09-01.md)
- [Project handoff](PROJECT_HANDOFF.md)
- [Session handoff](SESSION_HANDOFF_2026-09-01.md)
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

GPL-2.0-only. See [LICENSE](LICENSE).

<!-- current-boundary-2026-09-02 -->
## Current research boundary — 2026-09-02

The Windows startup reconstruction has been corrected: `DriverState:Install`
is not the fatal `_DeviceInit` gate. The first meaningful sensor-response gate
is `GetEvkVersionWithRetry`, whose exact 1.1.141.36 default outer retry count
is 3, followed by a separate hard-reset fallback and one final attempt.

A live Linux trace also confirmed the tested transfers reach the LPSS
`lpss_ssp_cs_control` path.

See [`docs/software-boundary-2026-09-02.md`](docs/software-boundary-2026-09-02.md).
