# Project handoff — GXFP51A0 / GF3658 Milan Linux driver research

## Canonical repository

Repository: https://github.com/GodsQuantum/huawei-matebook-fingerprint-linux

This file is the durable technical handoff. It intentionally contains no local username,
private filesystem path, account identifier, proprietary binary, firmware image, or raw
disassembly.

## Target hardware

**CONFIRMED:** Huawei MateBook 13 2021, DMI `WRTB-WXX9`, product version `M1020`,
board `WRTB-WXX9-PCB`, BIOS Huawei `1.26`. The fingerprint sensor is Goodix
`GXFP51A0` / GF3658 Milan at ACPI path `\_SB.PCI0.SPI1.SPBA`.

**CONFIRMED:** SPI1 CS0, mode 0, 8 bits, 10 MHz, four-wire. ACPI GPIO48 is the
level-triggered active-high data-ready IRQ. ACPI GPIO264 is the reset/control output.
Do not confuse GPIO48 with the Linux virtual IRQ number.

## Safety invariants

- No firmware flashing, UPFW, firmware erase, bootloader programming, or blind firmware flow.
- Do not run unmodified OpenGoodixSPI, goodix-fp-dump full device flows, or USB firmware procedures on this SPI sensor.
- Read flow is exact-length only: wait IRQ -> read exactly 4-byte outer header -> validate -> read exactly body length.
- After `FF FF FF FF`, stop immediately; no second read.
- Any future active experiment must restore the proven Windows reset state: GPIO264 HIGH 10 ms -> LOW 100 ms -> final LOW.
- One hypothesis per experiment; minimum writes; explicit stop condition; unconditional cleanup.
- Proprietary Windows binaries and generated raw disassembly stay outside Git.

See [docs/safety.md](docs/safety.md).

## Proven reset behavior

**CONFIRMED from Goodix Windows HardwareID 3 path:** GPIO264 HIGH for 10 ms, then
LOW for 100 ms, final state LOW. The older LOW-to-HIGH OpenGoodixSPI reset story is
obsolete for this target.

## Proven Milan write framing

Windows performs two physical SPI transactions with separate chip-select cycles:
outer header, wait 2 ms, inner packet.

```text
outer_A_checksum = (byte0 + byte1 + byte2) & 0xff
cmd = (cmd0 << 4) | (cmd1 << 1)
len = payload_len + 1
inner_checksum = (0xAA - cmd - len_lo - len_hi - sum(payload)) & 0xff
```

Confirmed vectors:

```text
NOP outer: A0 08 00 A8
NOP inner: 00 05 00 00 00 00 00 A5
DriverState:Install outer: A0 06 00 A6
DriverState:Install inner: 96 03 00 01 00 10
A/4 deterministic Linux outer: A0 06 00 A6
A/4 deterministic Linux inner: A8 03 00 00 00 FF
```

The A/4 `00 00` payload is a deterministic Linux fixture, not a recovered Windows constant.

## Windows `GetEvkVersion` state machine

**CONFIRMED in Goodix FP 1.1.141.40 and independently corroborated in 1.1.141.36:**

1. send NOP;
2. wait 5 ms;
3. send OTHER A/4 with a two-byte payload;
4. requested ACK timeout is 100 ms, but the transport clamps positive values below 1000 ms to 1000 ms;
5. ACK state is polled in ~15 ms slices;
6. first ACK timeout retransmits the same A/4 exactly once;
7. second ACK timeout fails the send;
8. after ACK success, response handling is separate and waits on logical event 9 in 50 ms slices; requested response timeout 500 ms is also clamped to at least 1000 ms.

Common-init defaults to three initial `GetEvkVersion` attempts. After total failure,
Windows suppresses fallback during D0Exit; otherwise it performs one `HardResetMcu`
and exactly one final attempt. DriverState has a separate retry/reset path and must not
be conflated with this fallback.


## Windows DriverState:Install ACK/retry/reset path

**CONFIRMED by disassembly and the generic ACK dispatcher:** DriverState:Install
is CHIP 9/3, packed command `0x96`. Its send path requests a 100 ms ACK timeout,
which the generic transport raises to an effective minimum of 1000 ms. B/0 ACK
messages carry the packed command being acknowledged in `payload[0]`, therefore
`payload[0] == 0x96` sets ACK(9,3).

The DriverState helper sends NOP and then makes up to two wrapper calls. Each
wrapper call may physically send the exact same Install packet twice: first
send, wait ACK; on timeout, one exact retransmission and a second ACK wait.
DriverState has no separate response-event phase here (`response_timeout=0`,
event index `-1`). Success in either wrapper call skips the DriverState reset.
Only after both wrapper calls fail does Windows invoke `HardResetMcu`, after
which its caller proceeds into `init_MCU`.

A fully silent path can therefore send at most four physical
DriverState:Install packets before the conditional reset. This supersedes the
earlier Linux research approximation of two Install writes separated by fixed
100 ms sleeps.

## RX classification closed by 1.1.141.36


The independently obtained Goodix FP `1.1.141.36` package has SHA-256
`74052a274239e17ac8fa95314e22d8db1770a3b9df28c90c9a9178231418f435`.
Its `gfspi.dll` SHA-256 is
`4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`.
The INF explicitly supports both `ACPI\GXFP51A0` and `ACPI\GXFP51A7`;
internal paths identify `MilanSpi` / `GF3658`.

For an outer A frame, Windows derives:

```text
cmd0 = packed >> 4
cmd1 = (packed & 0x0e) >> 1
```

B/0 is generic ACK bookkeeping: its first payload byte is the packed command
being acknowledged. The currently evidenced targets include:

```text
B/0 + payload[0] == 96  -> ACK for DriverState:Install; set ACK(9,3)
B/0 + payload[0] == A8  -> ACK for A/4; set ACK(A,4)
A/4 normal response     -> copy EVK payload; signal event 9
```

ACK and response are software-distinct frames and may be drained within one
IRQ-high window; two physical IRQ edges are not required. The 1.1.141.36
`GetEvkVersion` call site also passes two A/4 payload bytes from stack storage
not initialized in the visible function, matching 1.1.141.40. This does not
prove Windows sends zeroes.

## Linux transport implementation status


`research/` now contains:

- restricted NOP and A/4 packet builders;
- one-attempt `GetEvkVersion` state machine;
- spidev discovery without hardcoded `/dev/spidevN.M`;
- SPI mode 0 / 8-bit / 10-MHz configuration and explicit exact-length transfer primitives;
- level-oriented GPIO48 readiness logic;
- generic B/0 ACK parsing/matching plus A/4 EVK response classification;
- exact-length RX drain with terminal `FF FF FF FF`, cancellation and fail-closed behavior;
- Windows-faithful DriverState:Install ACK/retry/reset control: ACK target
  `0x96`, effective 1000 ms ACK waits, at most two sends per wrapper call, at
  most two wrapper calls, and conditional reset only after both fail;
- a single-purpose probe runtime plus independent supervisor and GPIO264-only
  restore helper.

The corrected 13-file DriverState patch passes the complete GCC and
Clang+ASan/UBSan suites, focused generic-ACK/DriverState tests, GCC
`-fanalyzer`, source-safety/privacy checks, and real target binary build/link
against libgpiod 2.3.1 without hardware execution.

## Passive hardware gate completed

**CONFIRMED on the target laptop:** temporary spidev binding produced `/dev/spidev1.0`.
The passive preflight read back SPI mode 0, 8 bits, 10 MHz, performed
`SPI_TRANSFER_COUNT=0`, read GPIO48 once at LOW, never requested GPIO264, then unbound
spidev, cleared the override, and restored the module to its previous unloaded state.
No protocol read/write or reset occurred.

## Previous active experiment and why it is low-value


**CONFIRMED on the target laptop:** the first independently supervised one-shot
probe completed without firmware activity. Its historical DriverState preamble
still used two Install writes separated by fixed 100 ms sleeps. It then ran one
`GetEvkVersion` logical attempt with the tested A/4 ACK state machine and its
single allowed A/4 retransmission.

The run submitted twelve physical SPI write transactions in total. GPIO48
remained LOW throughout all readiness windows, so the exact-length RX backend
performed zero SPI reads. No ACK was observed; the A/4 path ended in ACK timeout
after its single retransmission. Internal cleanup restored GPIO264 to LOW and
the external supervisor restored temporary spidev state.

This negative result does **not** isolate A/4 acceptance. Follow-up disassembly
showed that DriverState itself needed ACK(9,3), effective 1000 ms waits and the
nested retry/reset structure described above. Probe #2 therefore changes only
that preamble model; A/4 remains the deterministic Linux `00 00` fixture.

## Cross-machine evidence

The same `GXFP51A0` HID is reported on other Huawei/Honor laptops, including a Huawei
MateBook 14 2020. One public report from that exact HID extracted firmware string
`GF_ST411SEC_APP_14115` from Windows ETL. The 1.1.141.36 package supports both
GXFP51A0 and GXFP51A7, strengthening the use of those variants as static comparators.
See [docs/cross-machine-research.md](docs/cross-machine-research.md).

## Exact next engineering step


The corrected DriverState model is validated off-hardware on the target laptop
against libgpiod 2.3.1. The independent supervisor remains mandatory. For probe
#2 it requires `GXFP51A0_REVIEWED_PROBE_2`, owns temporary spidev bind/unbind,
runs the probe in a separate session under a 12-second wall-clock timeout, uses
TERM then KILL-after-2-seconds, requires both `CLEANUP_RESULT=0` and
`GPIO264_AFTER=0`, falls back to the separate GPIO264-only restore helper when
cleanup cannot be confirmed, and always restores spidev/module state.

**Probe #2 has not been executed.** Its final review must preserve exactly one
changed hypothesis relative to probe #1: the DriverState preamble now follows
ACK(9,3) with the generic transport retry/reset behavior. The rest stays fixed:
proven initial and cleanup reset, one `GetEvkVersion` logical attempt, A/4 Linux
fixture `00 00`, exact-length RX, at most one A/4 retransmission,
unconditional internal cleanup and the external fail-safe.

No firmware operation, three-attempt common-init fallback, enrollment or
libfprint integration is authorized in probe #2.
