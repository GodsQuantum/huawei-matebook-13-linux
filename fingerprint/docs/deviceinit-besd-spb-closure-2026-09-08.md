# GXFP51A0 DeviceInit / BESD / first-contact SPB closure — 2026-09-08

## Executive result

The apparent missing operation between DriverState and `init_MCU` is closed.

Both reviewed Windows builds execute:

```text
_DeviceInit
  -> send_driver_install_to_MCU
  -> device_action(0x0F, &zero, 4)
  -> init_MCU
```

The earlier whole-dispatcher classifier marked `device_action` as `SENSOR_IO`
because other switch cases perform SPI. That classification does not apply to
the selected `0x0F` branch.

For action `0x0F`, both binaries only store zero in the Windows-driver-local
`besdenable` global and log the value. No SPI send, reset, wake, firmware
operation, target config or TLS operation occurs in the selected case.

## Exact differential anchors

```text
Goodix 1.1.141.36
  _DeviceInit              0x1800174c8
  intermediate callsite   0x1800175c0
  device_action           0x180043258
  case 0x0F               0x180043990
  besdenable global       0x1803aba38

Goodix 1.1.141.40
  _DeviceInit              0x180017fd8
  intermediate callsite   0x1800180d0
  device_action           0x180075b38
  case 0x0F               0x180076308
  besdenable global       0x180402518
```

Targeted xref/reachability closure:

```text
1.1.141.36 BESD xrefs: 3
1.1.141.40 BESD xrefs: 3
pre-ACK reachable external BESD consumers: 0
```

## 34-transfer reconciliation

The fully silent Windows-faithful common-init path is:

```text
DriverState
  NOP                                     1 logical frame
  maximum Install sends                   4 logical frames
  subtotal                                5 logical = 10 physical transfers

one maximally silent GetEvkVersion
  NOP + A8 + one identical A8 retry       3 logical = 6 physical transfers

three initial GetEvkVersion attempts      18 physical
one final post-reset attempt               6 physical

total                                     34 physical transfers
```

The DeviceInit `0x0F` operation adds no sensor transaction, so the previously
executed 34-transfer research harness is complete for this boundary.

## First-contact SPB closure

Exact GXFP51A0 runtime HardwareID differs internally by driver build:

```text
1.1.141.36 -> HardwareID 5
1.1.141.40 -> HardwareID 3
```

Both IDs select the Milan split-write family. The target write reaches the
simple SPB Read/Write WDF request path:

```text
outer 4 bytes
-> SPB write
-> approximately 2 ms
-> remaining bytes
-> SPB write
```

`SpbPeripheralExecuteSequence` exists but is a distinct path and is not used
for the GXFP51A0 first-contact split write.

Linux uses two separate `SPI_IOC_MESSAGE(1)` submissions with the same
approximately 2 ms boundary. This boundary is therefore
`MATCHED_HIGH_CONFIDENCE`.

## Candidate fidelity correction

The libfprint candidate is aligned with the already-tested research model:

- no unconditional reset before DriverState;
- DriverState sends NOP then waits 5 ms;
- maximum two wrapper calls with one retransmission each;
- after exhausted DriverState ACK retries, perform one reviewed reset and
  continue into `init_MCU` without replaying DriverState;
- GetEvkVersion sends NOP, waits 5 ms, sends A8, retries the identical A8 once
  after first ACK timeout, then treats ACK and response as separate phases;
- a response observed before its ACK can be retained within the same attempt.

These fixes improve candidate fidelity. They are not evidence of a new
hardware remedy because the separate research harness already exercised the
same 34-transfer model and remained silent.

## Current boundary

No additional borrowed protocol command is justified before a physical/platform
difference is demonstrated.

The next discriminating evidence is Windows-vs-Linux observability of:

```text
CS / SCLK / MOSI / MISO / GPIO48 IRQ
```

The first real success criterion remains the first sensor-side ACK.
