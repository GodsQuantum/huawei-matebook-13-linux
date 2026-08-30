# Goodix GXFP51A0 / GF3658 Milan on Linux

> Experimental reverse-engineering research. There is no working Linux fingerprint driver yet. Do not flash firmware or run unreviewed vendor flows.

> Version française: [README.FR.md](README.FR.md)

## Current status

Confirmed work now includes ACPI/SPI/GPIO mapping, Milan framing, proven reset behavior, exact-length readiness-driven RX, DriverState ACK/retry/reset reconstruction, `GetEvkVersion` ACK/response reconstruction, supervised Linux probes through corrected probe #3, the Goodix-specific ACPI `_DSM`, and Windows startup call-graph reconstruction.

**Latest live result:** probe #3 remains completely silent at the sensor side. GPIO48 stays LOW and no RX is attempted. Removing the previously assumed pre-DriverState reset did not restore communication.

See the canonical current snapshot:

**[State of research — 2026-08-31](docs/state-of-research-2026-08-31.md)**

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

## ACPI `_DSM`

UUID:

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

Function 1 returns a 2048-byte `HWFP/FPDT` buffer. Linux can evaluate it successfully and Windows identifies this path as a PSK source.

**The raw DSM payload and any PSK are private per-machine material and are not part of this repository.**

## Current research question

The main unresolved problem is why correctly submitted Linux SPI traffic receives no readiness/ACK at all.

Current priority:

1. map Windows `PrepareHardware`;
2. map SPI target/controller setup;
3. map interrupt/readiness registration;
4. classify remaining platform state before `InitThread`;
5. compare with Linux before authorizing another probe.

Do not add generic Goodix wake commands without same-device evidence.

## Repository map

- [Current state](docs/state-of-research-2026-08-31.md)
- [Project handoff](PROJECT_HANDOFF.md)
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
