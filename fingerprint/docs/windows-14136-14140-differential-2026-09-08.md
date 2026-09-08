# GXFP51A0 — Windows 1.1.141.36 → 1.1.141.40 differential

Date: 2026-09-08

This is the sanitized canonical handoff for the latest static reverse-engineering work on the Huawei/Goodix GXFP51A0 (GF3658 / Milan) path.

No sensor I/O, GPIO write, MMIO write, firmware action, Windows-driver execution, raw `_DSM` payload, PSK, derived key, vendor binary or proprietary bulk disassembly is included here.

## Exact binaries

```text
1.1.141.36 gfspi.dll
SHA-256 4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59

1.1.141.40 gfspi.dll
SHA-256 36033fbf507620776d9fb686ecfe7847ff41fcbdee6e2afad119e28c6f81ca04
```

All inspected 1.1.141.40 `gfspi.dll` copies were identical.

## Differential tooling corrections

Whole-file `radiff2 -s` is retired for this pair: it became pathological or timed out. `radiff2 -A -C` was too shallow to be useful.

Two intermediate targeted passes also produced false negatives because this radare2 build exposes instruction addresses as `addr`, not `offset`.

Reliable comparison now uses:

1. exact SHA-256 gates;
2. PE32+ `.pdata` / `RUNTIME_FUNCTION` boundaries;
3. bounded `pdj` extraction;
4. call-site ABI/control-flow comparison;
5. local string evidence only.

Earlier zero-instruction V2/V4 conclusions are invalid.

## Exact-target ACPI / LPSS closure

Confirmed on the exact WRTB-WXX9 ACPI/runtime path:

- two GXFP51A0 templates exist (SPI1 and SPI2);
- SPI1 is active;
- SPI2 fingerprint child is disabled;
- runtime is consistent with `SM01=1`, `SM02=0`;
- `FISW` is fingerprint-presence state, not the parent selector;
- SPI1 is in SerialIO PCI mode;
- no fingerprint-specific child `_PS0`, `_PS3` or `_RST` activation was recovered;
- parent LPSS power handling is generic;
- no exact-device evidence supports GPIO112/GPP_D16 as a fingerprint enable line.

```text
GPIO112_HYPOTHESIS=CLOSED_DO_NOT_TOUCH
LPSS_HIDDEN_FINGERPRINT_SWITCH_SEARCH=CLOSED
ACTIVE_FINGERPRINT_PARENT=SPI1
SPI2_FINGERPRINT_CHILD=DISABLED
```

Do not reopen this branch without new exact-device evidence.

## Stable `.36` ↔ `.40` startup/protocol paths

The following are identical or near-identical:

- WakeupMCU;
- most reset paths;
- DriverState;
- GetEvkVersion;
- GPIO reset helper;
- reviewed D0/power paths;
- most reviewed PSK/DSM helpers.

No `.40`-only first-contact command or wake primitive was recovered.

## `init_MCU`

PE `.pdata` gives exact boundaries:

```text
1.1.141.36: 0x18004d9f4..0x18004e025
1585 bytes / 267 instructions / 24 calls

1.1.141.40: 0x180080a88..0x180080fbd
1333 bytes / 228 instructions / 21 calls

normalized instruction ratio ~= 0.888889
```

The largest removed `.36` branches correspond to firmware-policy/update diagnostics including:

```text
!!!EC:no firmware update
!!!Mach:Update firmware
!!!Watt:Update firmware
```

The change is real, but no new `.40`-only prerequisite explaining Linux's total silence has been established.

## `MilanEvtDevicePrepareHardware`

Exact PE boundaries:

```text
1.1.141.36: 0x1800101b0..0x180011176
4038 bytes / 673 instructions / 52 calls

1.1.141.40: 0x1800100b0..0x18001125c
4524 bytes / 751 instructions / 58 calls

instruction ratio ~= 0.942416
call-sequence ratio ~= 0.727273
```

`.40` has richer WDF/error diagnostics and explicit labels for `WdfInterruptCreate`, `WdfIoTargetCreate`, `WdfIoTargetOpen`, driver version and failure paths.

A new API-name string is not proof of a new hardware operation.

## IRQ creation branch — closed

`.36` already performs the same effective four-argument interrupt-object creation as `.40`:

```text
RCX = device
RDX = &interrupt_config
R8  = 0
R9  = &interrupt_handle
```

`.36` reports generic `Create Interrupt Failed with 0x%x`; `.40` explicitly names `WdfInterruptCreate`.

```text
IRQ_CREATE_PRESENT_IN_14136=YES
IRQ_CREATE_PRESENT_IN_14140=YES
IRQ_14136_VS_14140=SEMANTICALLY_SAME_WDF_INTERRUPT_CREATE
```

Therefore Linux's zero Goodix IRQ events are not explained by an interrupt setup introduced only in `.40`.

Reference: <https://learn.microsoft.com/windows-hardware/drivers/ddi/wdfinterrupt/nf-wdfinterrupt-wdfinterruptcreate>

## `.40` helper `0x18000a71c`

PE `.pdata` bounds it at 367 bytes / 63 instructions / 6 calls. It directly references:

```text
NoFile
NoFunc
NoFormat
```

Classification: logging/error formatting, not a hardware wake/bootstrap primitive.

## WDF I/O target lifecycle

Both `.36` and `.40` contain the strings `WdfIoTargetCreate` and `WdfIoTargetOpen`; only `.40` adds explicit failure labels.

The `.40` PrepareHardware path visibly performs the normal lifecycle:

```text
initialize object attributes
→ create I/O target
→ store handle in device context
→ initialize open parameters
→ open I/O target
→ error/cleanup handling
```

Exact `.36` call-site parity remains to be resolved in the complete lifecycle audit; it must not be inferred from strings alone.

References:

- <https://learn.microsoft.com/windows-hardware/drivers/ddi/wdfiotarget/nf-wdfiotarget-wdfiotargetcreate>
- <https://learn.microsoft.com/windows-hardware/drivers/ddi/wdfiotarget/nf-wdfiotarget-wdfiotargetopen>

## Linux communication boundary already closed

The Windows-faithful common-init has already executed under Linux:

```text
34 physical target SPI transfers
180 TX bytes
12 readiness/IRQ waits
34 concrete target iDMA completions in the DMA run
0 Goodix IRQ events
180 retained same-wire RX bytes
180/180 RX bytes = 0xFF
no SPI controller error/timeout
final GPIO264 LOW
```

Already discriminated and closed:

- DMA vs deterministic PIO;
- runtime PM;
- Linux IRQ mapping;
- polling vs native level IRQ waiting;
- mode-5 outer 4 bytes → ~2 ms → inner split;
- reviewed GPIO264 reset timing/polarity;
- same-wire MISO capture.

Do not rerun the unchanged common-init.

## DSM / PSK / target config boundary

Confirmed outer `_DSM` envelope:

```text
capacity = 4096
first returned DWORD = byte-swapped
low 16 bits = variable payload length
payload starts at +4
length <= 4 = reject
```

A target-specific fixed 48-byte GXFP51A0 PSK is not proven. The candidate's 48-byte constant is inherited from GXFP5187 and must remain gated.

No exact-device `Milan_DlCfg` sequence is validated.

## Closed hypotheses — do not regress

Do not reopen without genuinely new exact-device evidence:

- unchanged 34-transfer common-init;
- DMA vs PIO;
- runtime-PM hold/autosuspend;
- Linux virtual IRQ mapping;
- GPIO polling vs native level IRQ waiting;
- mode-5 split timing/CS semantics;
- reviewed GPIO264 reset;
- GPIO112/GPP_D16 fingerprint enable;
- hidden ACPI/LPSS fingerprint switch;
- `.40`-only `WdfInterruptCreate`;
- `.40` helper `0x18000a71c` as hardware wake;
- blind sibling Milan wake/config blobs;
- generic OpenGoodixSPI startup commands.

## Next program — one mega audit

Stop isolated string/function micro-passes.

Reconstruct the complete Windows causal graph in one analysis:

```text
DriverEntry / FxDriverEntryUm
→ EvtDeviceAdd
→ MilanEvtDevicePrepareHardware
→ raw + translated ACPI resources
→ IRQ + SPB connection resources
→ WdfIoTargetCreate / WdfIoTargetOpen
→ D0Entry / device-context initialization
→ dynamic config / profile / hardware-mode selection
→ DriverState
→ init_MCU
→ GetEvkVersion
→ final WDF/SPB request primitive
→ first physical Milan transfer
```

The report must include:

1. WDF function-table/wrapper resolution;
2. ACPI-resource-to-SPB dataflow;
3. final SPB IOCTL/request/transfer-list primitive;
4. every non-logging operation before first DriverState/A8;
5. exact GXFP51A0/GF3658 profile/config/transport selection;
6. a Windows↔Linux parity matrix.

Every prerequisite gets exactly one state:

```text
MATCHED
MISSING
DIFFERENT
NOT_APPLICABLE
UNKNOWN
```

Only exact-device `MISSING` or materially `DIFFERENT` prerequisites justify the next Linux implementation change or fresh-boot experiment.

## Functional completion target

```text
first real GXFP51A0 ACK
→ valid A8/EVK response
→ target config resolved
→ target TLS/PSK resolved
→ image capture
→ enroll
→ verify
→ fprintd
→ PAM / desktop authentication
```
