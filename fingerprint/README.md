# Goodix GXFP51A0 / GF3658 Milan on Linux

> Experimental reverse-engineering project. The public candidate builds against
> libfprint, but the fingerprint sensor is **not functional under Linux yet**.
> Do not flash firmware or run unreviewed vendor flows.

> Français: [README.FR.md](README.FR.md)

## Current status — 2026-09-08

The project has a reproducible **GXFP51A0 libfprint v1.94.100 candidate**.
Software integration is no longer the blocker.

Validated software state:

```text
libfprint build/integration          PASS
first-contact source regression     PASS
research unit/safety suite          PASS
Windows first-contact model         reconstructed
Linux first-contact model           aligned
SPI controller submissions          proven
first sensor ACK                    NOT OBSERVED
A8 / EVK                            NOT OBSERVED
capture/enroll/verify               NOT REACHED
fprintd/PAM                         NOT REACHED
```

The latest canonical handoff is [HANDOFF_CURRENT.md](HANDOFF_CURRENT.md).
The detailed 2026-09-08 reverse-engineering checkpoint remains in
[FINAL_HANDOFF_2026-09-08.md](FINAL_HANDOFF_2026-09-08.md).

## One-command contributor validation

Clone the repository and run:

```bash
make -C fingerprint verify
```

This is the recommended entry point for a new contributor. It:

1. checks every public shell script for Bash syntax;
2. runs the GXFP51A0 first-contact regression;
3. runs the complete software-only research test/safety suite;
4. verifies the candidate source SHA-256 manifest;
5. creates an isolated build-tool venv;
6. pins Meson 1.12.0 and Ninja 1.13.2;
7. clones exact libfprint tag v1.94.100;
8. applies the reviewed integration patch;
9. injects only the reviewed GXFP51A0 sources;
10. compiles and verifies the driver object/type/string.

**No sensor SPI I/O, GPIO write, MMIO write or firmware action is performed.**

Other entry points:

```bash
make -C fingerprint build
make -C fingerprint research
make -C fingerprint passive-audit
```

See [scripts/README.md](scripts/README.md) and
[docs/contributor-validation-2026-09-08.md](docs/contributor-validation-2026-09-08.md).

## Confirmed target facts

- ACPI HID: `GXFP51A0`
- Goodix GF3658 / Milan family
- active parent: SPI1; fingerprint child on SPI2 disabled
- SPI1 CS0, mode 0, 8-bit, 10 MHz, four-wire
- GPIO48: level-triggered ActiveHigh readiness/IRQ
- GPIO264 reset: HIGH 10 ms -> LOW 100 ms -> final LOW
- Milan write: outer 4 bytes -> about 2 ms -> remaining bytes
- DriverState Install: `(9,3)` / packed `0x96`
- NOP checksum: `0xA5`
- GetEvkVersion: NOP -> 5 ms -> A8, one identical A8 retry after first ACK timeout
- exact ST411 vector evidence:
  - SP `0x20020000`
  - Reset_Handler `0x08033198`
  - application base `0x08020000`

## Windows differential closure

Reviewed Windows binaries:

```text
Goodix FP 1.1.141.36 gfspi.dll
SHA-256 4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59

Goodix FP 1.1.141.40 gfspi.dll
SHA-256 36033fbf507620776d9fb686ecfe7847ff41fcbdee6e2afad119e28c6f81ca04
```

Important closures:

- both versions use the same effective WDF interrupt creation semantics;
- GXFP51A0 selects the Milan split-write family;
- the target first-contact write uses separate simple SPB writes, not
  `SpbPeripheralExecuteSequence`;
- `_DeviceInit` calls `device_action(0x0F, &zero, 4)` between DriverState and
  `init_MCU`;
- that selected action only sets the Windows-local `besdenable=0` and logs it;
- no pre-ACK external consumer of `besdenable` is reachable in either reviewed
  Windows build.

See
[docs/deviceinit-besd-spb-closure-2026-09-08.md](docs/deviceinit-besd-spb-closure-2026-09-08.md)
and
[docs/windows-14136-14140-differential-2026-09-08.md](docs/windows-14136-14140-differential-2026-09-08.md).

## Exact Linux silent boundary

The reconstructed Windows-faithful common-init has already been executed under
Linux:

```text
SPI transfers             34
TX bytes                  180
IRQ waits                 12
Goodix IRQ events         0
retained RX bytes         180
RX bytes equal to 0xFF    180
controller completions    proven
controller errors         none
final GPIO264             LOW
```

The 34-transfer count is reconciled with DeviceInit/BESD and the corrected
DriverState/GetEvkVersion state machine.

Do **not** repeat this unchanged active experiment.

## Closed hypotheses

Do not restart these branches without new exact-device evidence:

- DMA versus deterministic PIO
- runtime PM as primary explanation
- Linux IRQ mapping
- userspace GPIO polling versus native IRQ wait
- mode-5 split timing / first-contact SPB transaction boundary
- reviewed reset permutations
- same-wire MISO retention
- GPIO112 / GPP_D16 enable hypothesis
- hidden LPSS fingerprint switch
- DeviceInit intermediate action as missing sensor I/O
- fixed 48-byte GXFP51A0 PSK assumption
- unchanged common-init replay

## Still unresolved

- first real sensor ACK under Linux
- first A8/EVK response
- physical CS/SCLK/MOSI/MISO reachability versus controller completion
- physical GPIO48 behavior
- exact GXFP51A0 target config / `Milan_DlCfg`
- exact `_DSM` TLS/PSK semantics and length
- image capture
- enroll / verify
- fprintd / PAM / desktop integration

## Current next boundary

The primary development installation currently has **no Windows boot**.
Therefore the Windows WDF/SpbCx comparison cannot be collected locally.

The repository now publishes two contributor paths:

### Linux target

```bash
make -C fingerprint passive-audit
```

This collects read-only ACPI/SPI/PCI/runtime-PM/IRQ/pinctrl context. It does not
perform sensor traffic or hardware writes.

### Working Windows GXFP51A0

Use
[scripts/windows/gxfp51a0_windows_observability.ps1](scripts/windows/gxfp51a0_windows_observability.ps1)
to inventory the working Windows stack and optionally capture one WDF trace.

If software observability cannot distinguish Windows from Linux, the
highest-value evidence becomes an external logic-analyzer/oscilloscope
comparison of:

```text
CS / SCLK / MOSI / MISO / GPIO48
```

## Repository map

- [Current handoff](HANDOFF_CURRENT.md)
- [Detailed final handoff — 2026-09-08](FINAL_HANDOFF_2026-09-08.md)
- [Candidate driver](driver/goodix51a0/)
- [Contributor scripts](scripts/)
- [Contributor validation contract](docs/contributor-validation-2026-09-08.md)
- [Current technical boundary](docs/current-boundary-2026-09-08.md)
- [DeviceInit/BESD/SPB closure](docs/deviceinit-besd-spb-closure-2026-09-08.md)
- [Windows .36 -> .40 differential](docs/windows-14136-14140-differential-2026-09-08.md)
- [Hardware evidence](docs/hardware.md)
- [Protocol evidence](docs/protocol.md)
- [Research log](docs/research-log.md)
- [Safety policy](docs/safety.md)
- [Research implementation](research/README.md)
- [Contributing](CONTRIBUTING.md)

## Functional target

```text
first ACK
-> A8/EVK
-> exact target config
-> exact DSM/TLS/PSK
-> image capture
-> enroll
-> verify
-> fprintd
-> PAM/desktop
```

## Public-repository safety

Never publish proprietary CAB/DLL/firmware, raw `_DSM` payloads, PSKs, derived
keys, serial numbers, local usernames/paths, private IPs or unrelated hardware
inventory.

No firmware flash/upload/erase, speculative MMIO/pinmux write, GPIO112 write or
borrowed generic wake command is authorized without new exact-target evidence.

See [docs/safety.md](docs/safety.md).
