# State of research — 2026-08-31

This document is the current public, privacy-safe research snapshot for the Goodix `GXFP51A0` / GF3658 Milan fingerprint sensor used in the Huawei MateBook 13 2021 hardware family.

There is **no functional Linux fingerprint driver yet**.

The repository deliberately excludes local usernames, private filesystem paths, machine nicknames, boot IDs, IP addresses, raw per-machine `_DSM` data, PSKs, proprietary Windows binaries, firmware images and raw disassembly.

## Confirmed hardware

- ACPI HID: `GXFP51A0`
- Goodix family: GF3658 / Milan
- ACPI object: `\_SB.PCI0.SPI1.SPBA`
- SPI1 CS0
- mode 0
- 8-bit
- 10 MHz
- four-wire
- GPIO48: level-triggered ActiveHigh readiness / IRQ input
- GPIO264: reset/control output

Do not confuse the ACPI GPIO number with a Linux virtual IRQ number.

## Proven reset behavior

The relevant Windows HardwareID-3 path performs:

```text
GPIO264 HIGH
wait 10 ms
GPIO264 LOW
wait 100 ms
final LOW
```

This replaces older LOW-to-HIGH assumptions from unrelated Goodix implementations.

## Milan SPI framing

A Windows Milan write uses two physical SPI transactions with separate chip-select cycles:

```text
outer frame
wait 2 ms
inner frame
```

Confirmed vectors:

```text
NOP outer:                 A0 08 00 A8
NOP inner:                 00 05 00 00 00 00 00 A5

DriverState:Install outer: A0 06 00 A6
DriverState:Install inner: 96 03 00 01 00 10

A/4 Linux fixture outer:   A0 06 00 A6
A/4 Linux fixture inner:   A8 03 00 00 00 FF
```

The A/4 payload `00 00` is a deterministic Linux research fixture, not a recovered Windows constant.

## RX contract

The restricted Linux RX model follows the Windows evidence:

1. wait for readiness;
2. read exactly the four-byte outer header;
3. validate it;
4. read exactly the announced body length;
5. classify the logical frame.

`FF FF FF FF` is terminal for that read attempt.

Generic B/0 ACK frames carry the packed acknowledged command in `payload[0]`.

```text
B/0 payload[0] == 0x96 -> ACK for DriverState:Install / logical (9,3)
B/0 payload[0] == 0xA8 -> ACK for A/4
A/4 normal response    -> EVK response / logical event 9
```

ACK and response are software-distinct but may be drained during one continuous IRQ-high window.

## DriverState

`DriverState:Install` is logical CHIP 9 / command 3, packed as `0x96`.

The Windows transport requests a 100 ms ACK timeout but clamps positive values below 1000 ms to an effective 1000 ms. A transport call may retransmit the same Install packet once after the first ACK timeout.

The DriverState helper can make two wrapper calls. A totally silent path can therefore submit at most four identical Install packets before the helper performs its conditional `HardResetMcu`.

DriverState has no separate response-event phase.

## GetEvkVersion

The Windows attempt is:

```text
send NOP
wait 5 ms
send OTHER A/4 with a two-byte payload
wait ACK(A,4)
if first ACK timeout:
    retransmit the identical A/4 once
if ACK succeeds:
    wait separately for logical response event 9
```

Requested ACK and response timeouts are 100 ms and 500 ms respectively, but the generic transport raises positive sub-1000-ms values to at least 1000 ms.

The exact Windows A/4 payload remains unresolved. In the visible Windows function it comes from stack storage not initialized in that visible scope.

## Probe #3

Probe #3 changed one hypothesis relative to the previous experiment: the unproven unconditional reset before DriverState was removed.

It retained the Windows-faithful DriverState ACK/retry path, conditional DriverState reset, one `GetEvkVersion` logical attempt, deterministic Linux A/4 fixture `00 00`, exact-length RX, one A/4 retransmission maximum, unconditional final reset cleanup and the independent supervisor.

Fresh-boot result:

```text
INITIAL_RESET=NO
DRIVERSTATE_RESULT=ACK_TIMEOUT
DRIVERSTATE_RESET_PERFORMED=YES
PROBE_RESULT=ACK_TIMEOUT
SPI_TRANSFER_COUNT=16
GPIO48 remained LOW
EVK_RESPONSE_LEN=0
cleanup succeeded
temporary spidev state restored
```

No RX transaction occurred because readiness never became true.

A successful SPI controller submission does not prove that the sensor MCU accepted or observed the transaction.

### Probe #3 conclusion

Removing the initial reset did not restore communication. The hypothesis that the earlier silence was caused solely by an unnecessary pre-DriverState reset is rejected.

Do not repeat probe #3.

## ACPI findings

The active SPBA object contains an 0x800-byte `HWFP` operation-region field named `FPDT`.

No target-local conventional `_PR0`, `_PR3`, `_PS0`, `_PS3`, `_PSC`, `_RST`, `_DEP` or `PowerResource` object was found.

SPBA `_INI` calls:

```text
SHPO(0x04010010, One)
SHPO(0x04020008, One)
```

Static helper analysis shows `SHPO` manipulates Intel `HOSTSW_OWN` ownership bits. It is ownership configuration, not a Goodix wake/power command. For a present ACPI device Linux/ACPICA normally evaluates `_INI` during namespace initialization, so manually invoking `_INI` is not justified.

## Goodix `_DSM`

SPBA exposes UUID:

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

Function 0 returns capability bitmap `0x03`, so functions 0 and 1 are supported. Function 1 returns the 0x800-byte / 2048-byte `FPDT` buffer.

Static Windows analysis found strings including:

```text
ACPI_HWFP firmware table not found
GetPSKFromDSMMethod
to get psk data from DSM method
ProductionReadPSKDataFromBios
GetHostOriginalPSKData
tlsapp_get_psk_data
```

A minimal Linux module safely evaluated revision 0 / function 1 exactly once on a fresh boot. It performed no SPI bind/transfer, GPIO operation, reset or firmware action and returned exactly 2048 bytes of non-empty data.

The raw buffer is private. Windows identifies the DSM path as a PSK source, so the raw payload and derived key material must never be committed.

The important public result is that Linux can successfully retrieve the Goodix ACPI platform data.

## Windows startup path

Static analysis of Goodix FP 1.1.141.36 (`gfspi.dll` SHA-256 `4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`) establishes:

```text
MilanEvtDeviceD0Entry
  -> needupdate_engine_base bookkeeping
  -> _StartInitThread
      -> create thread(entry = InitThread)
          -> InitThread
              -> _DeviceInit
                  -> send_driver_install_to_MCU
                      -> SetDriverState(9,3 / packed 0x96)
                  -> intermediate operation
                  -> init_MCU
                      -> GetEvkVersionWithRetry
                      -> hardware-family / firmware-version decisions
              -> later SGX / TLS / PSK / FDT work
```

Important consequences:

1. DriverState genuinely precedes `GetEvkVersion`.
2. The ACPI PSK/TLS branch is not a prerequisite for the first DriverState send.
3. `WakeupMCU` exists as a named Windows function but current call-graph evidence does not place it on the first `_DeviceInit -> DriverState -> init_MCU` path.
4. Generic Goodix wake commands must not be prepended without same-device evidence.

## Remaining hypotheses

The main unresolved classes are:

1. physical SPI reachability / chip-select / electrical signaling;
2. readiness / interrupt equivalence;
3. platform/controller preparation before `InitThread`;
4. the unresolved intermediate `_DeviceInit` operation between DriverState and `init_MCU`.

## Next engineering work

Probe #4 is complete and must not be repeated.

The next boundary is static/passive:

1. tie the GF3658 Windows transport-mode selector to GXFP51A0's exact runtime hardware mode;
2. follow `0x180008b68 -> 0x180009c34` to the final Windows/SPB I/O primitive;
3. reconcile that final transaction boundary with the existing Linux 4-byte outer + 2 ms + inner implementation;
4. if those boundaries match, move to direct physical SPI observability rather than adding protocol commands;
5. after the first credible ACK/response, move the validated state machine toward libfprint/fprintd.

Do not force runtime PM, remux firmware-locked pads or prepend generic Goodix wake commands without same-device evidence.

## Safety boundary

Never perform as part of this research state:

- firmware flashing or UPFW;
- firmware erase;
- bootloader programming;
- vendor full-device firmware management;
- unreviewed OpenGoodixSPI or goodix-fp-dump full flows;
- unrelated USB `27c6:5110` / `5117` firmware procedures.

Every future active test must use one hypothesis, minimum writes, exact-length RX, explicit stop conditions, independent supervision and final GPIO264 LOW restoration.


## Probe #4 native-IRQ result

Passive Linux validation proved that ACPI `GpioInt[0]` resolves to hardware IRQ 48 with `LEVEL_HIGH` semantics through the Intel GPIO irqdomain. The Linux virtual IRQ is dynamic and must never be treated as a protocol constant.

Probe #4 then executed once on a fresh boot, changing only readiness from userspace GPIO48 polling to the native kernel ACPI IRQ wait.

Result:

```text
DRIVERSTATE_RESULT=ACK_TIMEOUT
DRIVERSTATE_RESET_PERFORMED=YES
SPI_TRANSFER_COUNT=16
IRQ_WAIT_COUNT=6
IRQ_EVENT_COUNT=0
SPI reads=0
EVK_RESPONSE_LEN=0
cleanup=successful
```

The native IRQ path saw no readiness event. This rejects the userspace-polling hypothesis. Do not rerun Probe #4.

Passive controller postmortem correlated the submitted work with the Intel LPSS / PXA2xx controller stack, but this remains controller-side evidence rather than proof of physical CS/SCLK/MOSI/MISO signaling.

## 2026-09-01 transport reassessment

Goodix FP `1.1.141.36` independently exposes a GF3658 split-write path:

```text
transfer first 4 bytes
wait 2 ms
transfer remaining bytes
```

for transport modes `2`, `3` and `5`. The calls flow through `0x180008b68 -> 0x180009c34`.

This corroborates the existing Milan outer/inner transport model. The exact GXFP51A0 runtime mode and the final SPB I/O leaf below `0x180009c34` remain open.

A proposed missing 1 ms pre-submit delay is not supported by this GF3658 path.

See [Reassessment — 2026-09-01](reassessment-2026-09-01.md).
