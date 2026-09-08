# Session handoff — 2026-09-08

Canonical state:

- [`docs/current-boundary-2026-09-08.md`](docs/current-boundary-2026-09-08.md)
- [`docs/windows-14136-14140-differential-2026-09-08.md`](docs/windows-14136-14140-differential-2026-09-08.md)
- [`driver/goodix51a0/`](driver/goodix51a0/)

## Current state

A real GXFP51A0 libfprint 1.94.100 candidate builds and links, but the exact target remains non-communicative under Linux. The blocker is the missing first sensor-side ACK/response, not software integration.

## Build closure

```text
MESON_CONFIGURE=PASS
UPSTREAM_LIBFPRINT_BUILD=PASS
COMPILE_ERROR_GROUPS=0
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES
GOODIX51A0_STRING_IN_SHARED_LIBRARY=YES
SOFTWARE_BUILD_READY=YES
```

## Exact Linux boundary

```text
SPI_TRANSFER_COUNT=34
TX_BYTES=180
IRQ_WAIT_COUNT=12
GOODIX_IRQ_EVENTS=0
RETAINED_RX_BYTES=180
RX_FF_BYTES=180
CONTROLLER_COMPLETIONS=PROVEN
SPI_CONTROLLER_ERROR=NONE
FINAL_GPIO264=LOW
```

Closed: DMA/PIO, runtime PM, IRQ mapping, polling/native IRQ wait, mode-5 split timing/CS, reviewed resets, same-wire MISO.

## Exact-target ACPI closure

```text
ACTIVE_FINGERPRINT_PARENT=SPI1
SPI2_FINGERPRINT_CHILD=DISABLED
SM01=1
SM02=0
GPIO112_HYPOTHESIS=CLOSED_DO_NOT_TOUCH
LPSS_HIDDEN_FINGERPRINT_SWITCH_SEARCH=CLOSED
```

## Windows `.36 → .40` closure

Exact DLL SHA-256:

```text
1.1.141.36  4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59
1.1.141.40  36033fbf507620776d9fb686ecfe7847ff41fcbdee6e2afad119e28c6f81ca04
```

Reliable comparison uses PE `.pdata` plus bounded radare2 disassembly.

Stable/near-stable: WakeupMCU, reset, DriverState, GetEvkVersion, GPIO reset, reviewed D0/power paths.

`init_MCU` changed from 1585 bytes / 267 instructions / 24 calls to 1333 bytes / 228 instructions / 21 calls; the largest removed branches are firmware-policy/update diagnostics.

PrepareHardware changed from 4038 bytes / 673 instructions / 52 calls to 4524 bytes / 751 instructions / 58 calls, mainly with richer WDF/error diagnostics.

Both versions perform the same effective `WdfInterruptCreate` operation. `.40` merely names it explicitly in diagnostics.

`.40` helper `0x18000a71c` is a logging/error-formatting helper (`NoFile`, `NoFunc`, `NoFormat`), not hardware wake/bootstrap.

Both DLLs contain `WdfIoTargetCreate` and `WdfIoTargetOpen`; exact `.36` call-site parity is deferred to the full lifecycle audit.

## DSM / PSK

Outer `_DSM` result is variable length (4096-byte capacity, byte-swapped first DWORD, low 16-bit length, payload at +4, reject <=4). A fixed 48-byte GXFP51A0 PSK is not proven. No exact-device `Milan_DlCfg` is validated.

## Next work

No more micro-passes. One mega audit must reconstruct:

```text
DeviceAdd
→ PrepareHardware
→ ACPI resources
→ IRQ + SPB target
→ WdfIoTarget create/open
→ D0Entry
→ config/profile/hardware mode
→ DriverState
→ init_MCU
→ GetEvkVersion
→ final WDF/SPB primitive
→ first physical transfer
```

Output: complete Windows/Linux parity matrix using `MATCHED`, `MISSING`, `DIFFERENT`, `NOT_APPLICABLE`, `UNKNOWN`.

Only a concrete exact-device `MISSING` or materially `DIFFERENT` prerequisite justifies a Linux driver change.

Functional target remains: first ACK → A8/EVK → target config/TLS → image capture → enroll → verify → fprintd → PAM/desktop.
