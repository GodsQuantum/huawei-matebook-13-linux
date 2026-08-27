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

## RX classification closed by 1.1.141.36

The independently obtained Goodix FP `1.1.141.36` package has SHA-256
`74052a274239e17ac8fa95314e22d8db1770a3b9df28c90c9a9178231418f435`.
Its `gfspi.dll` SHA-256 is
`4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`.
The INF explicitly supports both `ACPI\GXFP51A0` and `ACPI\GXFP51A7`; internal paths
identify `MilanSpi` / `GF3658`, and the binary carries firmware string
`GF_ST411SEC_APP_14114`.

For an outer A frame, the body starts with the packed command byte and a little-endian
inner length. Windows derives:

```text
cmd0 = packed >> 4
cmd1 = (packed & 0x0e) >> 1
```

For `GetEvkVersion`:

```text
B/0 message + payload[0] == A8  -> ACK for A/4; set ACK(A,4)
A/4 normal response             -> copy EVK payload; signal event 9
```

Therefore ACK and response are software-distinct frames and may be drained within one
IRQ-high window; two physical IRQ edges are not required.

The 1.1.141.36 `GetEvkVersion` call site also passes two A/4 payload bytes from stack
storage not initialized in the visible function, matching 1.1.141.40. This makes a
mandatory fixed vendor payload unlikely but still does not prove Windows sends zeroes.

See [docs/protocol.md](docs/protocol.md) and
[docs/windows-14136-crosscheck.md](docs/windows-14136-crosscheck.md).

## Linux transport implementation status

`research/` now contains:

- restricted NOP and A/4 packet builders;
- one-attempt `GetEvkVersion` state machine;
- spidev discovery without hardcoded `/dev/spidevN.M`;
- SPI mode 0 / 8-bit / 10-MHz configuration and explicit exact-length transfer primitives;
- level-oriented IRQ wait logic;
- passive libgpiod 2.x GPIO48 reader;
- restricted RX parser for `FF FF FF FF`, B/0 ACK(A8), and A/4 EVK response;
- off-hardware exact-length RX drain/state adapter that composes readiness,
  exact header/body reads, ACK/response classification, response caching,
  one-retransmission generation invalidation, cancellation, and terminal
  fail-closed behavior.

All current unit tests pass with GCC and with Clang + ASan/UBSan. The RX drain
also passes GCC `-fanalyzer`; a regression test covers build directories
containing spaces.

## Passive hardware gate completed

**CONFIRMED on the target laptop:** temporary spidev binding produced `/dev/spidev1.0`.
The passive preflight read back SPI mode 0, 8 bits, 10 MHz, performed
`SPI_TRANSFER_COUNT=0`, read GPIO48 once at LOW, never requested GPIO264, then unbound
spidev, cleared the override, and restored the module to its previous unloaded state.
No protocol read/write or reset occurred.

## Previous active experiment and why it is low-value

The older Linux sequence used Windows reset, NOP, DriverState:Install retry, NOP, A/4
fixture `00 00`, one ~500 ms IRQ observation, and one 4-byte read. All SPI submissions
returned controller success, GPIO48 did not transition, and the only read was
`FF FF FF FF`. Later Windows analysis proved that this probe omitted the true ACK flag
processing, 1000 ms effective ACK window, one A/4 retransmission, and separate response
phase. Treat its negative result as low diagnostic value.

## Cross-machine evidence

The same `GXFP51A0` HID is reported on other Huawei/Honor laptops, including a Huawei
MateBook 14 2020. One public report from that exact HID extracted firmware string
`GF_ST411SEC_APP_14115` from Windows ETL. The 1.1.141.36 package supports both
GXFP51A0 and GXFP51A7, strengthening the use of those variants as static comparators.
See [docs/cross-machine-research.md](docs/cross-machine-research.md).

## Exact next engineering step

The single-purpose live-probe harness is now implemented and validated
off-hardware on the target laptop. The real binary links against libgpiod 2.3.1
but has not been executed.

Its scope is deliberately fixed:

1. GPIO264 must already be a free active-high OUTPUT; it is requested `AS_IS`,
   never reconfigured;
2. initial reset is HIGH 10 ms -> LOW 100 ms -> final LOW;
3. the historical Linux DriverState preamble is kept constant:
   NOP -> 5 ms -> Install -> 100 ms -> Install -> 100 ms;
4. exactly one `GetEvkVersion` logical attempt is executed;
5. A/4 uses the explicitly labelled deterministic Linux fixture `00 00`;
6. exact-length RX, terminal `FF FF FF FF`, effective 1000 ms ACK/response
   windows and at most one A/4 retransmission are preserved;
7. the proven HIGH 10 ms -> LOW 100 ms reset runs unconditionally as cleanup.

**Do not execute the live probe yet.** The next and final safety gate before one
hardware attempt is an external supervisor independent of the probe process.
It must own the temporary spidev bind, enforce a hard timeout, verify the probe's
cleanup markers, invoke a separate GPIO264 restore helper if the probe
crashes/hangs or cannot confirm final LOW, then unbind spidev and clear
`driver_override` on every exit path. The external helper must contain no SPI or
protocol logic.

That supervisor can protect against probe-process crashes, hangs and ordinary
terminal signals. No userspace design can guarantee cleanup after power loss or
SIGKILL of the supervisor itself; this limitation must remain explicit.

Only after the supervisor and restore helper pass fake/off-hardware tests and
compile against the target's real libgpiod may one live probe be authorized.
