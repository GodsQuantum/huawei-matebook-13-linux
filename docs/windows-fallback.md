# Windows common-init fallback

This note records the focused static analysis of Goodix FP `1.1.141.40`
`gfspi.dll`. The analyzed DLL has SHA-256
`36033fbf507620776d9fb686ecfe7847ff41fcbdee6e2afad119e28c6f81ca04`;
the source CAB has SHA-256
`20da727ec91df771a0cb2fa7c92939b5853c5004855333e9943cd06b4a080805`.
Neither proprietary artifact nor the raw disassembly belongs in this repository.

All conclusions below are **CONFIRMED by disassembly** unless explicitly
qualified. Virtual addresses identify evidence in that exact DLL build.

## Retry-count provenance

The configuration getter at `0x180002828` returns the configuration object at
`0x1803af0a0`. Its byte at offset `+0x45e` is
`retry_count_for_common_init`; the compiled default is `3`.

Initialization reads an optional registry value from:

```text
HKEY_LOCAL_MACHINE\Software\Goodix\FP\
RetryCountForComminInit
```

`Commin` is the exact spelling used by the driver. The first returned byte
replaces the default only when it is at least `1`; a zero value leaves the
default unchanged. A diagnostic string confirms both names:

```text
CONFIG DATA: reg value %d, retry_count_for_common_init %d
```

The initialization call with its boolean argument enabled is at
`0x180082187`; ordinary getter calls pass it disabled. Four observed callers
of `GetEvkVersionWithRetry` load the retry byte from `+0x45e`, at
`0x1800183a7`, `0x18007b4af`, `0x18007b6e1`, and `0x180080c1f`.

## Meaning of `0x18041a80c`

The global at `0x18041a80c` is `g_d0exit_start`: a D0 power-exit lifecycle
flag, not a generic permission to use the fallback.

- `MilanEvtDeviceD0Entry` clears it to `0` at `0x18000f5be`.
- `MilanEvtDeviceD0Exit` normally sets it to `1` at `0x18000fc7d`.
- The special S0-idle exit path returns before that store, so it does not set
  the flag.
- `SpiSendDataToDeviceLock` checks the flag both before sending and while
  waiting. Its diagnostics include `timeout, g_d0exit_start = %d` and
  `D0exit happen, Cmd0-Cmd1: %x-%x`.
- The same transport path states that during D0Exit it can send only NOP and
  PC-state traffic. Initialization and AEMS paths also use the flag to abort
  work during power exit.

Consequently, `GetEvkVersionWithRetry` suppresses a hard reset when D0 exit
has started. **INFERRED:** the purpose is to avoid resetting the MCU while
Windows is removing power from the device.

## Decoded fallback strings

| Virtual address | Text |
|---|---|
| `0x18036ecb8` | `Get Evk Version...` |
| `0x18036ece0` | `GetEvkVersionWithRetry` |
| `0x18036ed10` | `!!get evk version failed, Hard reset mcu and try again` |
| `0x18036ed80` | `D0Exit start, not hardResetMCU` |
| `0x18036edc0` | `Get MCU Version Failed` |

## Exact control flow at `0x180070808`

The function behaves as follows; a nonzero `GetEvkVersion` result is success:

```text
GetEvkVersionWithRetry(context, output, retry_count):
    if context == NULL or output == NULL or retry_count == 0:
        log "!!!!wrong input parameter"
        return 0

    result = 0
    for attempt in range(retry_count):
        memset(output, 0, 64)
        result = GetEvkVersion(output, timeout_ms=500)
        if result != 0:
            break

    if result != 0:
        return 1

    log "!!get evk version failed, Hard reset mcu and try again"

    if g_d0exit_start != 0:
        log "D0Exit start, not hardResetMCU"
        return 0

    HardResetMcu(context->member_at_0x10)  # return value ignored
    result = GetEvkVersion(output, timeout_ms=500)

    if result != 0:
        return 1

    log "Get MCU Version Failed"
    perform failure bookkeeping
    return 0
```

With the compiled default, Windows therefore makes at most three initial
`GetEvkVersion` attempts. It stops immediately on the first success. If all
three fail and `g_d0exit_start == 0`, it performs exactly one hard reset and
exactly one final `GetEvkVersion` attempt. The `500 ms` value passed here is
the requested response timeout; the lower transport raises it to a 1000 ms
minimum in this driver build.

There is no second `memset` before the final query and no additional delay in
this caller between `HardResetMcu` and that query. Reset timing belongs to
`HardResetMcu` itself: GPIO264 HIGH for 10 ms, then LOW, followed by 100 ms,
ending LOW. If `g_d0exit_start != 0`, neither the reset nor the final query is
performed.

## Exact contents of one `GetEvkVersion` attempt

Function `0x180070308` is identified by the `GetEvkVersion` diagnostic. It
first calls `SendNopCmd` at `0x18007295c`. That function sends the confirmed
NOP with its four zero payload bytes, waits 5 ms, and returns. It then sends
OTHER A/4 with a two-byte payload and checksum enabled. The call site requests
a 100 ms ACK timeout and receives the caller-supplied 500 ms response timeout.
Those requested values are subsequently clamped by the transport, as described
below.

The A/4 call site at `0x1800703fe` points at two stack bytes that have not been
initialized in the visible function. Therefore the physical Windows payload
values remain unknown. The deterministic `00 00` payload and resulting
`A8 03 00 00 00 FF` packet remain a controlled Linux fixture only.

## Effective ACK and response state machine

`SpiSendDataToDevice` at `0x180073108` treats a positive ACK timeout below
`0x3e8` as `0x3e8` milliseconds. The wrapper at `0x1800736ec` independently
does the same to the response timeout. Therefore the A/4 arguments requested
by `GetEvkVersion` become, in this build:

```text
requested ACK timeout:       100 ms
transport ACK timeout:      1000 ms minimum
requested response timeout:  500 ms
transport response timeout: 1000 ms minimum
```

ACK state is tracked by command pair. Helper `0x1800730d0` indexes a table by
the two logical command nibbles and sets its ACK flag. The receive path calls
that helper after parsing an ACK. For logical OTHER A/4 it also recognizes the
`0xA4` command pair. This is software ACK state, not evidence for a dedicated
GPIO edge.

The send path polls ACK state in approximately 15 ms slices. On the first ACK
timeout it logs `!!!!wait for ack timeout, try again`, retransmits the same
packet once, and performs a second ACK wait. A second timeout logs
`!!!!ack timeout second time` and fails the send.

After ACK success, the wrapper enters a separate response phase. For
`GetEvkVersion`, the call site selects logical event index 9. The response
receive path copies the response data into its buffer and signals event 9;
the waiter uses `WaitForSingleObject` in 50 ms slices under the independently
clamped response timeout.

One `GetEvkVersion` attempt is consequently:

```text
NOP outer
wait 2 ms
NOP inner
wait 5 ms
A/4 outer
wait 2 ms
A/4 inner
wait ACK (effective limit >= 1000 ms)
  timeout -> retransmit the same A/4 once -> wait ACK again
ACK success -> wait response event 9 (effective limit >= 1000 ms)
```

This two-phase model corrects the previous Linux probe, which waited roughly
500 ms once and then made one four-byte read. That probe did not reproduce the
Windows ACK flag, A/4 retransmission, or separate response-event phase.

## Separate DriverState fallback


This is distinct from `GetEvkVersionWithRetry`. `send_driver_install_to_MCU` at
`0x1800811ac` calls `0x180072dcc`, which first sends NOP and then uses the
generic send/wait wrapper for DriverState:Install (`CHIP 9/3`, packed `0x96`).

The wrapper requests an ACK timeout of 100 ms. `SpiSendDataToDevice` raises that
positive value to an effective minimum of 1000 ms and uses generic per-command
ACK bookkeeping. A B/0 ACK with `payload[0] == 0x96` sets ACK(9,3). This
DriverState call has no separate response phase: `response_timeout=0` and event
index `-1`.

Each wrapper call may send the exact same Install packet at most twice. After
the first ACK timeout the lower transport retransmits once and waits again; a
second ACK timeout fails that wrapper call. `0x180072dcc` makes at most two such
wrapper calls. Success in either returns without a DriverState reset. Only after
both fail does it invoke `HardResetMcu`; its caller then continues into
`init_MCU`.

A completely silent device can therefore receive at most four physical
DriverState:Install packet sends before the conditional reset. The first
supervised Linux probe still used the older research approximation of two
Install writes separated by fixed 100 ms sleeps; that approximation is now
superseded.

## Boundary for the next experiment


The first supervised one-shot Linux probe has now been executed. Its A/4 path
used the reviewed ACK/retransmission logic, but its preceding DriverState
sequence still used the older two-write/fixed-100-ms research approximation.
GPIO48 remained LOW and no RX read occurred, so that run cannot isolate A/4
acceptance from the incomplete DriverState preamble.

The corrected DriverState ACK/retry/reset model is validated off-hardware and
probe #2 must change only that one hypothesis. It remains limited to one
`GetEvkVersion` logical attempt with the explicitly labeled Linux A/4 `00 00`
fixture, exact-length reads, the reviewed supervisor, unconditional final reset
restoration and no full common-init or firmware flow.
