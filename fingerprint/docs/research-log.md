# Research log

Append-only chronology; evidence labels preserve the limits of each finding.

## Relative chronology: obsolete baseline

**CONFIRMED:** historical correction — the old OpenGoodixSPI baseline, LOW-to-HIGH reset story, and firmware/wake assumptions are obsolete for GXFP51A0 / GF3658 Milan.

## July 2024: Windows package identification

**CONFIRMED:** Goodix FP `1.1.141.40` is the reference package; `1.1.124.12` is a different Goodix USB branch. CAB SHA-256: `20da727ec91df771a0cb2fa7c92939b5853c5004855333e9943cd06b4a080805`; `gfspi.dll` SHA-256: `36033fbf507620776d9fb686ecfe7847ff41fcbdee6e2afad119e28c6f81ca04`.

## Relative chronology: reset and transport proof

**CONFIRMED:** HardwareID 3 pulses GPIO264 HIGH 10 ms then LOW 100 ms, final state LOW. The response on the GPIO48 IRQ line/pad did not prove protocol acceptance. Windows physical writes use separate outer/inner chip-select cycles with a 2 ms delay.

## Relative chronology: exact-length reads and vectors

**CONFIRMED:** IRQ then exactly four bytes, validate little-endian length, then exactly that body length; never over-read or make a second read after `FF FF FF FF`. NOP, DriverState:Install, and deterministic A/4 vectors were recovered; A/4 `00 00` is a Linux fixture, not a Windows-proven payload.

## Relative chronology: latest Linux result

**CONFIRMED:** the controlled sequence returned `0` for each SPI submission; GPIO48 did not transition, IRQ remained low, and the sole four-byte read was `FF FF FF FF`. No firmware action occurred. This is neither MCU acceptance nor evidence firmware is absent.

## Current static fallback audit

**CONFIRMED by disassembly:**

```text
0x18036ecb8: Get Evk Version...
0x18036ece0: GetEvkVersionWithRetry
0x18036ed10: !!get evk version failed, Hard reset mcu and try again
0x18036ed80: D0Exit start, not hardResetMCU
0x18036edc0: Get MCU Version Failed
config +0x45e default byte: 0x03
```

**CONFIRMED by disassembly:** the default three-attempt shape, a conditional hard-reset fallback, and a final 500 ms A/4 query. **Open questions:** runtime retry provenance and effective value, the exact fallback conditions and call relationships, the lifecycle and semantics of `0x18041a80c`, and return ordering remain unresolved. The exact fallback is not ready for live reproduction. The 145 KB raw disassembly and proprietary DLL are not committed.

## 2026-08-26: static fallback audit completed

**CONFIRMED by disassembly:** configuration `+0x45e` is
`retry_count_for_common_init`, compiled as `3`. Initialization optionally reads
`HKLM\Software\Goodix\FP\RetryCountForComminInit`; the spelling `Commin` is
exact. Its first returned byte replaces the default only when at least `1`.

**CONFIRMED by disassembly:** `0x18041a80c` is `g_d0exit_start`. D0Entry clears
it, ordinary D0Exit sets it, and SPI/init paths use it to stop traffic during
power exit. It is not a generic fallback-enable flag.

**CONFIRMED by disassembly:** with the default, Windows clears the output and
makes at most three initial A/4 queries with a 500 ms timeout, stopping on the
first success. If all fail, it logs the fallback, returns without reset when
D0Exit has started, otherwise calls `HardResetMcu` and immediately makes
exactly one final 500 ms A/4 query. The caller neither clears the output again
nor adds another delay. Full addresses and control flow are recorded in
[windows-fallback.md](windows-fallback.md). No GPIO, SPI, or firmware operation
was performed during this audit.

## 2026-08-26: exact `GetEvkVersion` attempt expanded

**CONFIRMED by disassembly:** `0x180070308` calls `SendNopCmd`, which sends NOP
and waits 5 ms, before it sends OTHER A/4. A/4 uses a 100 ms ACK timeout and
the 500 ms response timeout supplied by `GetEvkVersionWithRetry`. Its two
payload bytes remain visibly uninitialized; Linux `00 00` remains only a
deterministic fixture.

**CONFIRMED by disassembly:** the DriverState helper is a separate fallback:
NOP, DriverState:Install, one retry after timeout, then `HardResetMcu` after a
second failure. This separate reset was not part of the previous Linux test
and must not be silently combined with the A/4 fallback when defining the
next one-hypothesis experiment. No GPIO or SPI operation was performed.

## 2026-08-27: ACK/response transport ambiguity resolved

**CONFIRMED by disassembly:** the 100 ms ACK and 500 ms response values at the
`GetEvkVersion` call sites are requested values. `SpiSendDataToDevice` and its
wrapper independently clamp each positive timeout below 1000 ms to 1000 ms in
Goodix FP `1.1.141.40`.

**CONFIRMED by disassembly:** ACK and response are separate software phases.
ACK state is tracked per logical `(cmd0, cmd1)` pair and polled in approximately
15 ms slices. If the first A/4 send times out waiting for ACK, the same A/4 is
sent once more; a second ACK timeout fails the send. After ACK success,
`GetEvkVersion` waits separately for logical response event 9 in 50 ms slices.
This does not prove two physical GPIO edges.

**CONFIRMED by disassembly:** the receive path marks the parsed command-pair ACK
and a distinct response branch copies response data before signaling event 9.
The earlier Linux probe, which waited approximately 500 ms once before a single
four-byte read, therefore did not reproduce this Windows transport state
machine.

**CONFIRMED by disassembly:** the two A/4 payload bytes passed from
`GetEvkVersion` remain uninitialized in the visible function. No public source
reviewed during this audit established their intended values. Linux `00 00`
remains an explicit deterministic fixture only. No GPIO, SPI, or firmware
operation was performed during this audit.

## 2026-08-27: Linux transport preflight established

**CONFIRMED on the target laptop:** `spi-GXFP51A0:00` exists under the PXA2xx SPI
controller with no driver bound. The running CachyOS kernel provides a signed
`spidev.ko` with `CONFIG_SPI_SPIDEV=m`, but no `GXFP51A0` spidev ACPI alias.
A temporary `driver_override=spidev` bind created `/dev/spidev1.0`; the test
then unbound it, cleared the override, and unloaded the module, returning to
`driver=NONE` with no spidev node. The device was never opened and no SPI
message was submitted.

**CONFIRMED on the target laptop:** `/dev/gpiochip0` belongs to `INT34BB:00` and exposes
312 lines. Pinctrl debug data maps GPIO offset 48 to Intel pin 41
(`GSPI0_CLK`) and GPIO offset 264 to Intel pin 189 (`UART0_RXD`). Neither
fingerprint line was shown as consumed in the GPIO debug snapshot. The
preflights did not request or modify either line.

**IMPLEMENTED OFF-HARDWARE:** `research/` now contains spidev discovery, fixed
mode-0/8-bit/10-MHz SPI configuration, exact one-message transfer primitives,
a level-oriented IRQ wait algorithm tested against fake operations, and a
libgpiod-2.x passive GPIO48 level reader. The passive executable does not call
the transfer primitives, does not arm GPIO edge detection, and has no GPIO264
API. Its remaining gate is compilation and passive execution against the real
libgpiod package on the target laptop while spidev is temporarily bound.


## 2026-08-27: passive hardware preflight completed

**CONFIRMED on the target laptop:** temporary spidev binding created
`/dev/spidev1.0`. The passive executable read back mode 0, 8 bits, 10 MHz,
performed `SPI_TRANSFER_COUNT=0`, requested GPIO48 only as a plain input, read
GPIO48 at LOW, and reported `GPIO264_REQUESTED=NO`. Cleanup unbound spidev,
cleared `driver_override`, removed the spidev node, and restored the module to
its previous unloaded state. No protocol read/write and no reset occurred.

## 2026-08-27: Goodix FP 1.1.141.36 independent cross-check

**CONFIRMED by static analysis:** package SHA-256
`74052a274239e17ac8fa95314e22d8db1770a3b9df28c90c9a9178231418f435`
contains a `gfspi.dll` with SHA-256
`4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`.
Its INF is `1.1.141.36` and explicitly supports both `ACPI\\GXFP51A7` and
`ACPI\\GXFP51A0`; internal paths identify MilanSpi/GF3658 and the binary contains
`GF_ST411SEC_APP_14114`.

**CONFIRMED by static analysis:** this older build reproduces the same
`GetEvkVersion` A/4 two-byte uninitialized visible-stack behavior as 1.1.141.40,
the same effective >=1000 ms ACK clamp, ~15 ms ACK polling, one retransmission,
and separate response event 9 phase.

**CONFIRMED by static analysis:** RX classification is now explicit. B/0 is the
message/ACK path; its first payload byte identifies the packed command being
acknowledged, so `A8` sets ACK(A,4). A/4 is the normal OTHER response path that
copies the EVK payload and signals event 9. ACK and response therefore do not
require two physical GPIO edges.

## 2026-08-27: restricted Milan RX parser validated offline

**IMPLEMENTED OFF-HARDWARE:** `research/milan_rx.*` validates outer-A headers,
exact body lengths, inner checksum, the `FF FF FF FF` stop sentinel, B/0 ACK(A8),
and A/4 EVK response. Fragmented frames are rejected instead of guessed.

**VERIFIED:** the complete research unit-test suite passes with GCC and with
Clang + ASan/UBSan. The build-directory-with-spaces regression test also passes.
No GPIO, SPI, or firmware operation occurred during this verification.

## 2026-08-27: exact-length RX drain/state model validated offline

**IMPLEMENTED OFF-HARDWARE:** `research/milan_rx_drain.*` now composes readiness
with the restricted Milan parser and the one-attempt `GetEvkVersion` state
machine. It performs exactly one four-byte header read after readiness, stops
terminally on `FF FF FF FF`, validates the announced body length before an
exact body read, classifies B/0 ACK(A8) and A/4 response frames, and permits
ACK plus response to be drained while the same IRQ-high readiness window is
active.

**IMPLEMENTED OFF-HARDWARE:** if an A/4 response is observed before ACK, it may
be cached for the separate response phase. If that ACK wait times out and
`milan_attempt` retransmits A/4, the cached pre-timeout response is invalidated
so a response from the first send cannot be paired with the second-send ACK.
Fatal header/body read errors, invalid/oversize frames, cancellation and the
`FF FF FF FF` sentinel fail closed for that drain instance.

**VERIFIED ON THE TARGET LAPTOP WITHOUT HARDWARE I/O:** the complete research
suite passes with GCC and with Clang + ASan/UBSan; `test_milan_rx_drain` passes
independently; GCC `-fanalyzer` reports no issue; the passive preflight still
compiles without being executed; the source audit finds no active write,
GPIO264/reset or firmware primitive in the new drain code. No SPI bind/open/
transfer, GPIO request/write or reset occurred during this verification.

## 2026-08-27: Linux active-research backend validated offline

**IMPLEMENTED OFF-HARDWARE:** `research/linux/active_backend.*` composes the
restricted Milan packet/state/RX layers with the existing exact spidev
primitives. NOP and A/4 each remain two distinct physical transactions with a
2 ms gap. The backend checks cancellation before every physical SPI write/read
and preserves one A/4 retransmission only through the already-tested
`milan_attempt` state machine.

**DESIGN CORRECTION:** GPIO48 readiness is level-only. The target is ACPI
level-triggered ActiveHigh and its Intel pad is firmware configuration-locked,
so the runtime does not request edge detection or change IRQ trigger
configuration. It polls the already-proven input value in bounded 5 ms sleeps.

**VERIFIED ON THE TARGET LAPTOP WITHOUT HARDWARE I/O:** the complete suite
passes GCC and Clang + ASan/UBSan; the active-backend test and GCC `-fanalyzer`
pass; the real runtime object and passive preflight compile but are not
executed; source guards confirm no GPIO264/reset, GPIO output, IRQ trigger
change or firmware-management API in this milestone. No SPI bind/open/transfer,
GPIO request/write, IRQ reconfiguration or reset occurred.

## 2026-08-27: single-purpose live-probe harness validated offline

**IMPLEMENTED OFF-HARDWARE:** the research tree now contains a one-purpose probe
harness with the proven GPIO264 HIGH-10-ms / LOW-100-ms reset both before the
experiment and unconditionally during cleanup. GPIO264 is accepted only when
libgpiod reports an already-configured free active-high OUTPUT and is then
requested `AS_IS`.

**EXPERIMENT SCOPE FIXED:** the harness keeps the earlier Linux DriverState
preamble constant (NOP, 5 ms, Install, 100 ms, Install, 100 ms) and executes
exactly one Windows-faithful `GetEvkVersion` logical attempt. A/4 remains the
explicit deterministic Linux `00 00` fixture. It does not implement the
separate DriverState hard-reset branch or the full three-attempt common-init
fallback.

**VERIFIED ON TARGET WITHOUT HARDWARE I/O:** GCC and Clang+ASan/UBSan suites,
the probe-harness and active-backend tests, GCC `-fanalyzer`, source safety
guards, and build-directory-with-spaces regression all pass. The real
`gxfp-live-probe` binary links against libgpiod 2.3.1; it was built only and
never executed. No SPI bind/open/transfer, GPIO request/write, IRQ trigger
change or reset occurred during this gate.

**NEXT:** validate an external supervisor and separate GPIO264-only restore
helper before authorizing a single live probe.

## 2026-08-27: external live-probe fail-safe validated offline

**IMPLEMENTED OFF-HARDWARE:** an independent shell supervisor now owns the
temporary spidev lifecycle and runs the live-probe process group under an
8-second hard timeout. Normal cleanup is accepted only when the probe emits
both `CLEANUP_RESULT=0` and `GPIO264_AFTER=0`.

**FAIL-SAFE:** if cleanup cannot be confirmed, the terminated probe is followed
by a separate GPIO264-only restore helper. The helper contains no SPI/Milan
logic and reuses the proven HIGH-10-ms / LOW-100-ms reset sequence, verifying
the final LOW level.

**VERIFIED ON TARGET WITHOUT HARDWARE I/O:** fake supervisor tests cover normal
cleanup, crash, timeout, restore failure, supervisor interruption and spidev
initially unloaded. GCC and Clang+ASan/UBSan suites pass. The real probe and
restore helper link against libgpiod 2.3.1 but were not executed. No real SPI
bind/open/transfer, GPIO request/write or reset occurred during this gate.

**NEXT:** final command-path review, then at most one supervised hardware probe.


## 2026-08-27: first supervised one-shot hardware probe

**CONFIRMED on the target laptop:** the independent supervisor executed one
bounded live probe after the offline fail-safe gate. The run used the proven
GPIO264 reset, the then-current historical DriverState preamble, and exactly one
`GetEvkVersion` logical attempt with A/4 Linux fixture `00 00`.

Twelve physical SPI write transactions were submitted. GPIO48 remained LOW
throughout all readiness windows, therefore the exact-length RX backend
performed zero SPI reads. No ACK was observed; A/4 reached its effective ACK
timeout, retransmitted exactly once, and reached the second ACK timeout.
Internal cleanup restored GPIO264 LOW and the supervisor restored temporary
spidev/module state. No firmware operation occurred.

**INTERPRETATION LIMIT:** controller-successful SPI submission is not MCU
acceptance, and this run did not isolate A/4. Its DriverState preamble still
used the research approximation of two Install sends separated by fixed
100 ms sleeps.

## 2026-08-27: DriverState ACK/retry/reset model corrected offline

**CONFIRMED by static analysis:** DriverState:Install is CHIP 9/3, packed
command `0x96`. The B/0 message handler performs generic ACK bookkeeping from
its first payload byte, so `payload[0] == 0x96` sets ACK(9,3). The DriverState
wrapper requests a 100 ms ACK timeout, which `SpiSendDataToDevice` raises to an
effective 1000 ms minimum. This command has no separate response-event phase.

**CONFIRMED by static analysis:** each DriverState wrapper call may retransmit
the exact Install packet once after the first ACK timeout. The higher helper
makes at most two wrapper calls. Success in either call skips the DriverState
reset; only two failed wrapper calls invoke `HardResetMcu`. A fully silent path
therefore permits at most four physical Install packet sends before the
conditional reset.

**IMPLEMENTED/VERIFIED OFF-HARDWARE ON THE TARGET LAPTOP:** the RX parser/drain
now match generic ACK targets, the probe harness implements the exact
DriverState nested retry/reset behavior, A/4 remains the unchanged deterministic
`00 00` fixture, and the independent supervisor requires
`GXFP51A0_REVIEWED_PROBE_2` with a 12-second wall-clock timeout. GCC,
Clang+ASan/UBSan, focused generic-ACK/DriverState tests, GCC `-fanalyzer`,
source-safety/privacy checks, and real libgpiod 2.3.1 build/link all pass.
No real binary, SPI bind/open/transfer, GPIO request/write or reset was executed
during this correction gate.

**NEXT:** final review of this exact corrected command path, then at most one
supervised probe #2. No firmware operation or full common-init fallback is
authorized.

## 2026-08-31: probe #3, ACPI DSM and Windows startup ordering

**CONFIRMED ON HARDWARE:** probe #3 was executed once on a fresh boot with the unproven unconditional pre-DriverState reset removed. DriverState still reached ACK timeout, triggered its Windows-faithful conditional reset, and the following single GetEvkVersion attempt also timed out. GPIO48 remained LOW and exact-length RX therefore performed zero reads. Sixteen physical SPI transactions were submitted. Cleanup restored GPIO264 LOW and temporary spidev state. No firmware operation occurred.

**INTERPRETATION:** the hypothesis that the earlier total silence was caused solely by an unnecessary initial reset is rejected. Controller completion still does not prove Goodix MCU acceptance.

**CONFIRMED BY ACPI STATIC ANALYSIS:** the SPBA `_INI` `SHPO` calls manipulate Intel HOSTSW_OWN ownership bits rather than a Goodix power/wake function. No conventional target-local child power-resource transition was found.

**CONFIRMED BY SAFE ACPI READ:** Goodix SPBA `_DSM` UUID `cc58b68a-4479-4893-a8bb-961209db59e5`, revision 0, function 1 returns exactly 2048 bytes under Linux. No SPI, GPIO, reset or firmware action was involved. Windows static analysis identifies this data path as a PSK source. The raw payload is machine-private and deliberately excluded from Git.

**CONFIRMED BY WINDOWS STATIC ANALYSIS:** `MilanEvtDeviceD0Entry` calls `_StartInitThread`; `_StartInitThread` passes `InitThread` as the thread entry. `InitThread` calls `_DeviceInit`. On first initialization `_DeviceInit` calls `send_driver_install_to_MCU` / `SetDriverState(9,3)` before `init_MCU`. `init_MCU` then reaches `GetEvkVersionWithRetry`. Later InitThread stages contain SGX/TLS work. The PSK/TLS branch is therefore not the prerequisite for the very first DriverState send.

**CURRENT BOUNDARY:** do not run probe #4 yet. First map PrepareHardware, Windows SPI target/controller setup, interrupt/readiness registration and the remaining intermediate `_DeviceInit` operation. Define another active probe only after one missing variable is justified.


### Probe #4 native-IRQ preparation

A mapping-only Linux check resolved the target ACPI `GpioInt[0]` as hardware IRQ 48 with `LEVEL_HIGH` semantics, without binding the SPI device, requesting an IRQ handler, transferring SPI data, touching reset GPIO264, invoking `_DSM`, or performing firmware activity.

Combined with the Windows `PrepareHardware` / D0Entry / InitThread audits, this isolates the next active variable: replace userspace GPIO48 polling with the native kernel ACPI IRQ wait while leaving the Probe #3 protocol sequence unchanged.

Probe #4 is prepared only. It requires a fresh boot, the reviewed confirmation token, the independent 12-second supervisor and one-shot execution.

## 2026-08-31: Probe #4 native-IRQ experiment executed

**CONFIRMED on the target laptop:** Probe #4 executed exactly once on a fresh boot with the Probe #3 protocol/reset model unchanged and readiness moved from userspace GPIO48 polling to the kernel-resolved ACPI `GpioInt[0]`.

The dynamic Linux IRQ resolved to hwirq 48 with `LEVEL_HIGH` semantics. The run submitted 16 SPI transactions, entered six native IRQ waits, observed zero Goodix IRQ events, performed zero SPI reads, timed out DriverState ACK, performed the existing conditional DriverState reset, and completed cleanup with GPIO264 LOW.

**CONCLUSION:** the hypothesis that userspace GPIO polling missed a readiness transition is rejected. Do not rerun Probe #4.

## 2026-08-31: passive controller postmortem

**CONFIRMED passively:** GXFP51A0 sits below the Intel LPSS / PXA2xx SPI stack. Controller interrupt accounting increased in step with the 16 Probe #4 submissions. Runtime autosuspend after the run is normal.

**LIMIT:** this is controller-side evidence only. It does not prove that CS/SCLK/MOSI reach the sensor electrically or that the MCU accepts the transfers.

## 2026-09-01: Probe #5 tracing path deprioritized

Probe #5 was intended to add ftrace/SPI observation without changing Probe #4 protocol traffic. Its attempts failed in trace/preflight configuration before any new sensor SPI transaction. One attempt loaded the native IRQ bridge and partially configured ftrace, then cleaned up without protocol I/O.

**CONCLUSION:** these attempts provide no new sensor result. Ftrace is deprioritized because the unresolved boundary is increasingly physical/platform reachability rather than Linux userspace readiness logic.

## 2026-09-01: GF3658 low-level transport independently cross-checked

**CONFIRMED by static analysis of Goodix FP 1.1.141.36:** `SpiSendDataToDevice` delegates the complete frame to helper `0x180007e60`, which dispatches by a transport/hardware mode selector.

For modes `2`, `3` and `5`, the binary performs a 4-byte transfer, waits 2 ms, then transfers `buffer + 4` for `length - 4`. Modes `0/1` use one full transfer and mode `6` has a separate path. The split transfers go through `0x180008b68 -> 0x180009c34`.

This independently corroborates the existing 4-byte outer + 2 ms + inner Milan transport model.

**OPEN:** the newest audit has not yet tied GXFP51A0 directly to its runtime mode value and has not yet followed `0x180009c34` to the final Windows/SPB I/O primitive.

**CORRECTION:** a proposed missing 1 ms pre-submit delay is not supported by this GF3658 path; the visible 15 ms / 50 ms sleeps belong to ACK/response waiting.

**CURRENT BOUNDARY:** do not add new Goodix commands. Close the runtime mode and final SPB leaf statically; if Linux transaction boundaries remain correct, move to direct physical SPI observability.

<!-- current-boundary-2026-09-02 -->
## 2026-09-02

Fresh-boot Linux ftrace confirmed each tested SPI transfer traverses
`spi_set_cs -> pxa2xx_spi_set_cs -> lpss_ssp_cs_control`, with clean controller
completion but no sensor IRQ.

Exact Goodix FP 1.1.141.36 reconstruction then corrected the startup model:
`send_driver_install_to_MCU()` does not propagate the SetDriverState result.
Windows continues to `init_MCU()` and `GetEvkVersionWithRetry`.

The compiled `retry_count_for_common_init` default is 3. After three failed
GetEvkVersion calls, Windows performs HardResetMcu when D0Exit has not begun,
ignores that reset BOOL, and performs one final GetEvkVersion.

The Linux research harness was updated TDD-first and passed the complete test
suite, runtime compilation, ASAN/UBSAN, GCC fanalyzer and source-safety checks.

<!-- full-common-init-live-result-2026-09-02 -->
## 2026-09-02 — full Windows-faithful common-init live run

The corrected common-init harness completed the full expected silent path:

- 34 SPI transfers / 180 transmitted bytes;
- 12 IRQ waits;
- 0 Goodix IRQ events;
- 0 reads;
- DriverState reset fallback succeeded;
- common-init reset fallback succeeded;
- no SPI-controller errors or timeouts;
- safe final cleanup succeeded.

This closes the question of whether previous probes simply stopped before
Windows' real startup response gate.

A subsequent consumed-boot passive audit examined PXA2xx/LPSS DMA/PIO
topology without performing any sensor action.

Sanitized next-experiment candidate: **deterministic PXA2xx PIO-only setup**.

See `dma-pio-reassessment-2026-09-02.md`.

<!-- 2026-09-03-pio-controller-closure -->
## 2026-09-03: deterministic PXA2xx PIO experiment completed

**CONFIRMED on the target laptop:** a dedicated fresh boot explicitly blocked
IDMA64 and proved the matching PXA2xx SPI controller selected its native PIO
fallback before any GXFP51A0 traffic. The kernel emitted
`no DMA channels available, using PIO`; the target had zero prior messages,
transfers, TX bytes and RX bytes.

**CONFIRMED on the target laptop:** the unchanged Windows-faithful common-init
then completed all 34 physical SPI transfers and 12 readiness/ACK waits. It
produced 0 Goodix IRQ events, 0 RX reads and 0 EVK bytes. DriverState and
common-init fallback resets both succeeded, there were no SPI errors/timeouts,
and final GPIO264 cleanup was LOW.

**INTERPRETATION:** the PIO result is materially identical to the established
normal DMA result. DMA versus PIO is therefore closed as the primary
explanation for the present silence.

No firmware-management action occurred.

## 2026-09-03: normal DMA / LPSS passive baseline

**CONFIRMED without sensor I/O:** a later normal boot loaded and bound the
matching IDMA64 device, kept the PXA2xx SPI controller on its normal path,
reported no native PIO fallback and preserved zero GXFP51A0 target activity
throughout the audit.

**DIAGNOSTIC CORRECTION:** the first sysfs DMA-channel counter incorrectly
reported zero because it only accepted descendants of the LPSS PCI parent.
The relevant DMAengine channel devices resolve to the parent itself. Corrected
matching identifies two channels.

**CONFIRMED by Linux v7.2 source:** the LPSS PXA2xx platform path enables DMA,
uses a one-byte burst size, filters DMA channels by the LPSS parent device and
requests separate TX and RX channels. The short transfers used in common-init
are DMA-eligible.

## 2026-09-03: passive tracing capability audit

**CONFIRMED without sensor I/O:** tracefs and debugfs are mounted; the running
kernel enables tracing, dynamic ftrace, function graph tracing, kprobes,
kprobe events, fprobe, BPF and BTF. Relevant PXA2xx/LPSS/IDMA symbols are
visible in kallsyms.

The audit's non-root readability check did not obtain tracefs event/function
lists. Root-privileged passive enumeration is the next step before another
active run is authorized.

**NEXT:** instrument runtime-PM, PXA2xx transfer, DMA and chip-select state
around one future unchanged common-init execution. Do not introduce new Goodix
protocol commands.

<!-- research-update-2026-09-07 -->
## 2026-09-07: Linux transport boundary closed further

**CONFIRMED on target hardware:** normal-DMA tracing captured 34 target SPI
start/stop pairs, 34 PXA2xx DMA prepare/start calls, 68 `idma64_issue_pending`
calls and exactly 34 concrete `irq=23 name=idma64.4` entries, all handled.
There were 0 Goodix IRQ events and no trace loss.

**CORRECTION:** `idma64_irq=10957` was a false-positive gate caused by counting
a global shared function. The concrete target iDMA IRQ count remained 34.

**CONFIRMED:** holding LPSS/PXA2xx runtime-active through the complete common-init
produced zero relevant runtime-PM callbacks and did not change the silence.
Runtime-PM cycling is strongly eliminated.

**CONFIRMED:** retaining RX bytes already clocked by the PXA2xx MUST_RX path did
not add traffic. All 180 retained bytes were `0xFF`; target iDMA completion was
normal and Goodix produced no IRQ. `0xFF` does not distinguish driven-high from
high-impedance plus pull-up.

**PUBLIC-SOURCE REASSESSMENT:** no working GXFP51A0 driver was found. A working
GXFP3200 Milan SPI libfprint driver appeared on 2026-09-02 and reached v0.2.0 on
2026-09-05. It is a strong architectural precedent but must not be force-bound
to GXFP51A0 because its F0/F1 transport and reset behavior differ. Working
GXFP5187 and GDIX51C0 drivers provide additional downstream implementation
references.

**DECISION:** stop blind active probing. Continue static/pre-first-command
GXFP51A0 analysis; require same-device evidence before any new live experiment.

## 2026-09-08: Windows 1.1.141.36 → 1.1.141.40 differential closure

**CONFIRMED by static analysis:** reliable comparison uses exact SHA gates, PE32+ `.pdata`/`RUNTIME_FUNCTION` boundaries and bounded radare2 disassembly. Whole-file radiff and earlier zero-instruction parser verdicts are retired.

**CONFIRMED:** WakeupMCU, DriverState, GetEvkVersion, GPIO reset and most reviewed reset/power paths remain identical or near-identical.

**CONFIRMED:** `init_MCU` changed from 1585 bytes / 267 instructions / 24 calls to 1333 bytes / 228 instructions / 21 calls. The largest removed branches are EC/Mach/Watt firmware-selection/update diagnostics. No `.40`-only first-contact command was recovered.

**CONFIRMED:** `MilanEvtDevicePrepareHardware` changed materially, but `.36` already performs the same effective four-argument WdfInterruptCreate operation. `.40` mainly adds clearer WDF/failure diagnostics around it.

**CONFIRMED:** `.40` helper `0x18000a71c` is a 367-byte / 63-instruction logging/error-formatting path referencing `NoFile`, `NoFunc`, `NoFormat`.

**CONFIRMED:** both DLLs contain `WdfIoTargetCreate` and `WdfIoTargetOpen`; `.40` adds explicit failure labels. Exact `.36` call-site parity is deferred to the complete lifecycle graph.

**CONFIRMED:** exact-target ACPI/LPSS analysis closes GPIO112/GPP_D16 enable and hidden fingerprint-switch hypotheses. SPI1 is active and SPI2 fingerprint child disabled.

**NEXT:** stop micro-passes. Reconstruct DeviceAdd → PrepareHardware → resource mapping → WDF IoTarget/SPB → D0Entry → config/profile → DriverState → init_MCU → GetEvkVersion → final SPB primitive in one audit, then classify Windows/Linux prerequisites as MATCHED/MISSING/DIFFERENT/NOT_APPLICABLE/UNKNOWN.

## 2026-09-08: final DeviceInit/BESD/SPB and candidate-fidelity closure

**CONFIRMED:** exact `device_action(0x0F, &zero, 4)` between DriverState and
`init_MCU` writes only `besdenable=0`; previous `SENSOR_IO` classification was
a whole-dispatcher false positive.

**CONFIRMED:** targeted BESD xref/reachability audit finds no pre-ACK reachable
external consumer in either reviewed Windows build.

**CONFIRMED:** GXFP51A0 first-contact split write reaches simple SPB Read/Write
requests in `.36` and `.40`; ExecuteSequence is not selected for this target
write.

**RECONCILED:** the fully silent Windows-faithful first-contact path remains
34 physical SPI transfers.

**CORRECTED:** the libfprint candidate now reproduces DriverState NOP+5 ms,
removes the unconditional initial reset, continues after fallback reset without
DriverState replay, and implements the exact same-attempt A8 retransmission.

**BOUNDARY:** the already-faithful research harness was still silent, so the
next discriminating evidence is physical/platform Windows-vs-Linux
CS/SCLK/MOSI/MISO/GPIO48 behavior.

Canonical resume:
`../FINAL_HANDOFF_2026-09-08.md`.

## 2026-09-08: contributor-tooling consolidation

**CONFIRMED:** the first-contact fidelity candidate and research suite are now
published with a reproducible one-command software baseline:

```bash
make -C fingerprint verify
```

**CONFIRMED:** the public build path pins libfprint `v1.94.100`, Meson `1.12.0`
and Ninja `1.13.2`, verifies `SOURCE_MANIFEST.sha256`, applies the reviewed
integration patch, compiles the candidate and checks the driver object/type
artifacts.

**CONFIRMED:** a separate public passive Linux observability script contains no
sensor transfer, GPIO output, MMIO write, module load/unload or driver
bind/unbind path.

**BOUNDARY:** the primary development installation has no Windows boot.
Working-Windows WDF/SpbCx evidence is now an external-contributor path.

**NEXT:** physical/platform observability remains the discriminating boundary.
The first real success criterion remains a sensor-side ACK.
