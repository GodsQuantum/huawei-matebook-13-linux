# Reassessment — 2026-09-01

This document records the privacy-safe engineering reassessment performed after commit `061923a8ed87f9ec214dbd0adb7c7695ab81d141`.

There is still **no functional Linux fingerprint driver** for GXFP51A0 / GF3658 Milan.

No proprietary Windows binary, raw disassembly, machine-specific `_DSM` data, PSK, local path, boot ID or private diagnostic dump is included here.

## Probe #4: native ACPI IRQ result

Probe #4 was executed once on a fresh boot. It changed exactly one experimental variable relative to Probe #3: readiness used the kernel-resolved ACPI `GpioInt[0]` instead of userspace GPIO48 polling.

The protocol bytes, DriverState retry model, conditional DriverState reset, `GetEvkVersion` fixture, SPI mode/word size/clock, supervisor and final cleanup remained unchanged.

Result:

```text
DRIVERSTATE_RESULT=ACK_TIMEOUT
DRIVERSTATE_RESET_PERFORMED=YES
SPI_TRANSFER_COUNT=16
IRQ_WAIT_COUNT=6
IRQ_EVENT_COUNT=0
EVK_RESPONSE_LEN=0
SPI reads=0
cleanup=successful
```

The Linux virtual IRQ was resolved dynamically and matched hardware GPIO IRQ 48 with `LEVEL_HIGH` semantics. It must never be hardcoded.

### Probe #4 conclusion

The hypothesis that userspace GPIO48 polling was missing a readiness transition is rejected. Native kernel IRQ waiting produced the same silence: no Goodix IRQ event, no RX and no ACK.

Do not rerun Probe #4.

## Linux controller postmortem

Passive inspection after Probe #4 showed:

- GXFP51A0 is attached below the Intel LPSS / PXA2xx SPI controller stack;
- controller interrupt accounting increased in step with the 16 submitted SPI transactions;
- the controller and PCI parent normally return to runtime-suspended/autosuspend state after the probe;
- current upstream `spi-pxa2xx` has the expected LPSS chip-select control path for the relevant SSP family.

This strengthens the statement that Linux is reaching the SPI controller software path. It still does **not** prove that valid CS/SCLK/MOSI waveforms reach the sensor or that the MCU accepts them.

Do not force runtime-PM state merely because the controller is suspended after an idle probe.

## Probe #5 / ftrace boundary

A planned Probe #5 attempted to instrument the existing Probe #4 path with SPI/ftrace observation only.

Several preflight/trace-configuration defects were found before any new sensor transaction was produced. One attempt loaded the native IRQ bridge and partially configured ftrace, but failed before SPI traffic. Cleanup returned the sensor binding and IRQ bridge to the passive state.

These attempts provide **no new sensor-side result** and must not be counted as hardware probes demonstrating protocol behavior.

Ftrace is currently deprioritized: even a perfect trace would mainly prove controller-side software calls, while the unresolved boundary is increasingly physical/platform reachability.

## Goodix FP 1.1.141.36 low-level transport cross-check

Static analysis of Goodix FP `1.1.141.36` `gfspi.dll` SHA-256:

`4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`

adds a lower-level transport proof.

`SpiSendDataToDevice` passes the complete framed buffer to helper `0x180007e60`. That helper dispatches on a global transport/hardware mode selector.

Visible branches:

```text
mode 0 or 1:
    transfer(buffer, full_length)

mode 2, 3 or 5:
    transfer(buffer, 4)
    Sleep(2 ms)
    transfer(buffer + 4, full_length - 4)

mode 6:
    separate special path
```

The two split-path transfer calls both go through `0x180008b68`, which delegates to the common SPB read/write helper `0x180009c34`.

This independently corroborates the existing Milan model:

```text
outer header (4 bytes)
wait 2 ms
inner packet
```

However, this newest audit has **not yet tied GXFP51A0's runtime hardware-mode value directly to one of `2`, `3` or `5`**, and it has not yet followed `0x180009c34` all the way to the final Windows/SPB write primitive. Those two points remain explicit static-analysis tasks rather than assumptions.

The same audit rejects a recently considered timing hypothesis: the visible `Sleep` calls in `SpiSendDataToDevice` are ACK/response polling delays, not a proven 1 ms pre-submit delay for GF3658.

## Public-source reassessment

Recent public Goodix SPI work provides useful corroboration for the Milan direction:

- <https://github.com/berkekbgz/libfprint-goodix-spi>

This is corroborating evidence, not a license to copy unrelated device initialization sequences.

Generic wake/chip-ID command suggestions from unrelated or weakly evidenced flows are **not** accepted as GXFP51A0 startup requirements. The same-device Windows startup path still places DriverState first and does not prove such a wake command before it.

The intended integration target remains libfprint/fprintd after transport acceptance is demonstrated.

## Updated hypothesis ranking

Leading unresolved classes:

1. physical SPI reachability: actual CS/SCLK/MOSI/MISO signaling between Intel LPSS and the sensor;
2. platform/controller electrical state not represented by already-validated main pinmux and ACPI resources;
3. exact runtime hardware-mode selection inside the Windows GF3658 transport;
4. the final Windows SPB leaf below `0x180009c34`;
5. only after those are closed, any remaining same-device protocol/startup difference.

Downgraded/rejected:

- unconditional reset before DriverState: rejected;
- userspace GPIO polling missing readiness: rejected by Probe #4;
- missing generic Goodix wake command: unsupported by same-device startup evidence;
- missing 1 ms pre-submit delay: not supported by the GF3658 `1.1.141.36` transport audit;
- forcing LPSS runtime PM on: not justified by observed controller behavior.

## Next engineering boundary

Do **not** add more Goodix commands or repeat Probe #3/#4.

Next work remains static/passive until one new discriminator is established:

1. map the GF3658 hardware-mode selector to the GXFP51A0 hardware-ID string/value;
2. follow `0x180008b68 -> 0x180009c34` to the final Windows SPB I/O primitive and confirm transaction/CS boundaries at that layer;
3. if the split-write path is fully closed for GXFP51A0, stop spending probes on protocol timing;
4. prefer read-only pinctrl/controller inspection or an external logic analyzer/oscilloscope to establish whether CS/SCLK/MOSI physically move and whether MISO responds;
5. after the first credible ACK/response, move the validated Milan state machine toward libfprint SPI helpers and then fprintd integration.

Any future active experiment still requires one reviewed hypothesis, a fresh state when relevant, bounded writes, exact-length RX, independent supervision and final GPIO264 LOW restoration.

## Safety boundary

No firmware flashing, UPFW, erase, bootloader programming, firmware-management flow, speculative pinmux write or unrelated USB Goodix firmware procedure is authorized.
