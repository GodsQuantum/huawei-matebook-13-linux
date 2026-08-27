# Milan protocol evidence

Technical claims are **CONFIRMED**, **INFERRED**, or **HYPOTHESIS**. Multi-byte fields are byte streams unless stated otherwise; response length is little-endian.

## CONFIRMED write flow

A Windows physical write is two separate SPI transactions: outer header, wait 2 ms, inner packet, with separate chip-select cycles.

```text
outer_A_checksum = (byte0 + byte1 + byte2) & 0xff
cmd = (cmd0 << 4) | (cmd1 << 1)
len = payload_len + 1
inner_checksum = (0xAA - cmd - len_lo - len_hi - sum(payload)) & 0xff
```

```text
NOP outer: A0 08 00 A8
NOP inner: 00 05 00 00 00 00 00 A5
DriverState:Install outer: A0 06 00 A6
DriverState:Install inner: 96 03 00 01 00 10
A/4 deterministic test outer: A0 06 00 A6
A/4 deterministic test inner: A8 03 00 00 00 FF
```

Outer B exists; `B0` is not a generic Wake command. The final two zero bytes of the A/4 vector are only a controlled Linux test fixture: the Windows call site declares a two-byte payload but does not visibly initialize it. They are not an official payload.

## CONFIRMED exact-length read flow

Wait for IRQ; make one read of exactly four bytes; validate header and little-endian length; then make one read of exactly that length. An over-read is prohibited. After `FF FF FF FF`, a second read is prohibited.

## CONFIRMED latest controlled test

Windows hard reset; NOP; DriverState:Install; wait 100 ms; retry DriverState:Install; wait 100 ms; NOP; OTHER A/4 with deterministic fixture payload `00 00`; monitor IRQ for 500 ms; read exactly four bytes.

Every Linux SPI submission returned zero, GPIO48 did not transition, IRQ remained low, and the four-byte read was `FF FF FF FF`. No second read or firmware operation occurred. A zero Linux SPI return proves controller submission only, not MCU acceptance.

## CONFIRMED Windows `GetEvkVersion` transport behavior

The compiled common-init retry default is three. Windows clears the 64-byte
output before each initial `GetEvkVersion` attempt and stops at the first
success. One attempt sends NOP, waits 5 ms, then sends A/4.

The A/4 call site requests a 100 ms ACK timeout and the caller supplies a
500 ms response timeout. Those are API-level arguments, not the effective
waits in Goodix FP `1.1.141.40`: the lower transport independently raises each
positive value below 1000 ms to 1000 ms.

ACK and response are distinct protocol/control phases:

- ACK state is stored per `(cmd0, cmd1)` command pair. The ACK wait polls in
  approximately 15 ms slices. If the first A/4 send reaches the ACK timeout,
  Windows retransmits the same A/4 once and waits for ACK a second time.
- Only after ACK success does the wrapper wait for the command response. For
  `GetEvkVersion`, the response path uses logical event index 9 and waits in
  50 ms slices, under the independently clamped response timeout.
- This proves separate ACK and response handling in software. It does **not**
  prove that Linux should wait for two GPIO IRQ edges.

After three failed `GetEvkVersion` attempts, Windows suppresses the fallback
when D0Exit has started; otherwise it performs the proven hard reset and one
final attempt. The caller adds no delay beyond `HardResetMcu` and does not
clear the output again. See [windows-fallback.md](windows-fallback.md).

## CONFIRMED receive classification from Goodix FP 1.1.141.36

Static analysis of the independently obtained Goodix FP `1.1.141.36` package
(`gfspi.dll` SHA-256
`4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`)
corroborates the `1.1.141.40` state machine and closes the ACK-vs-response
classification for the GetEvkVersion path. The package INF supports both
`ACPI\GXFP51A0` and `ACPI\GXFP51A7`, and its internal build path identifies
Milan/GF3658.

For an outer A frame, Windows passes exactly the outer little-endian body length
to its inner parser. The inner body begins with the packed command byte, followed
by a little-endian inner length. Windows derives `cmd0 = packed >> 4` and
`cmd1 = (packed & 0x0e) >> 1`. The inner length includes the trailing checksum,
so payload length is `inner_len - 1`.

For this path:

- `cmd0=B, cmd1=0` enters the message/ACK handler. Its first payload byte is the
  packed command being acknowledged. An ACK for A/4 therefore targets `0xA8`;
  Windows then sets the per-command ACK flag for `(A,4)`.
- `cmd0=A, cmd1=4` enters the normal OTHER response dispatcher, which clears the
  64-byte EVK response buffer, copies the response payload, and signals logical
  event 9.

ACK and A/4 response can consequently be processed from consecutive frames in
the same IRQ-high drain window; no second physical edge is implied. The Linux
research parser is deliberately restricted to this evidenced path and rejects
fragmented frames rather than guessing their semantics.

The `1.1.141.36` GetEvkVersion call site also passes a two-byte A/4 payload from
uninitialized stack storage, just like `1.1.141.40`. This makes a mandatory fixed
Windows payload value unlikely, but still does not prove Windows sends zeroes.
The deterministic Linux fixture remains `00 00`; it is a reproducible choice, not
a recovered vendor constant.

## INFERRED / open questions

The known framing and transport state machine now explain more of the Windows
ordering, but still do not establish why the MCU did not accept the previous
Linux traffic. The two physical A/4 payload bytes remain unknown because the
visible Windows function does not initialize them. No new live command is
authorized until a one-attempt experiment is simulated, written, and reviewed.


See also [Goodix FP 1.1.141.36 cross-check](windows-14136-crosscheck.md).
