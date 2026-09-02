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


The first supervised one-shot probe used the proven initial reset, the
then-current historical DriverState preamble, and one reviewed
`GetEvkVersion` logical attempt with deterministic A/4 fixture `00 00` and one
allowed A/4 retransmission.

Twelve physical SPI write transactions were submitted. GPIO48 remained LOW
throughout the readiness windows, so the exact-length RX gate performed zero
SPI reads. No ACK was observed and A/4 ended in ACK timeout after its
retransmission. Internal cleanup restored GPIO264 LOW and the external
supervisor restored temporary spidev state. No firmware operation occurred.

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


## CONFIRMED DriverState:Install ACK/retry/reset behavior

DriverState:Install is logical CHIP 9/3, packed command `0x96`. Its wrapper
requests a 100 ms ACK timeout, which the same generic lower transport raises to
1000 ms minimum. B/0 ACK processing is generic: `payload[0]` is the packed
command being acknowledged, therefore `0x96` sets ACK(9,3).

Each DriverState wrapper call may send the exact Install packet twice: initial
send, ACK wait, then one exact retransmission after timeout and one second ACK
wait. The higher DriverState helper makes at most two such wrapper calls. There
is no separate response-event wait for this command. Success at any ACK wait
skips the DriverState reset; only two failed wrapper calls trigger the proven
`HardResetMcu`. A fully silent path therefore permits at most four Install
packet sends before that conditional reset.

This corrects the historical Linux preamble used by the first supervised probe,
which sent only two Install packets separated by fixed 100 ms sleeps.

## CONFIRMED receive classification from Goodix FP 1.1.141.36


Static analysis of Goodix FP `1.1.141.36` corroborates the transport state
machine. For an outer A frame, the inner body starts with the packed command and
Windows derives `cmd0 = packed >> 4` and `cmd1 = (packed & 0x0e) >> 1`.

`cmd0=B, cmd1=0` enters the generic message/ACK handler. Its first payload byte
is the packed command being acknowledged. `0x96` therefore sets ACK(9,3) for
DriverState:Install, while `0xA8` sets ACK(A,4) for `GetEvkVersion`.
`cmd0=A, cmd1=4` is the separate EVK response path: it clears/copies the
64-byte EVK buffer and signals event 9.

ACK and A/4 response may be processed from consecutive frames in the same
IRQ-high drain window; no second physical edge is implied. The 1.1.141.36
`GetEvkVersion` call site also passes a two-byte A/4 payload from uninitialized
visible stack storage, like 1.1.141.40. The deterministic Linux fixture remains
`00 00`; it is not a recovered vendor constant.

## INFERRED / open questions


The first supervised probe produced no IRQ-high readiness and therefore no RX
frame. The corrected DriverState control path removes one known mismatch before
the next experiment, but it still does not establish whether the remaining
silence is caused by device state, another missing initialization step, or A/4
acceptance. The two physical A/4 payload bytes remain unknown because the
visible Windows function does not initialize them. Probe #2 remains a
single-hypothesis experiment: correct DriverState only, with A/4 `00 00`
unchanged.

See also [Goodix FP 1.1.141.36 cross-check](windows-14136-crosscheck.md).
