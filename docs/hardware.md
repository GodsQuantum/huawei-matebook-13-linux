# Hardware evidence

Technical claims are **CONFIRMED**, **INFERRED**, or **HYPOTHESIS**.

## CONFIRMED

Target machine: Huawei MateBook 13 2021; DMI `WRTB-WXX9`, version `M1020`; board `WRTB-WXX9-PCB`; BIOS Huawei `1.26`; CachyOS; last tested kernel `7.2.0-1-cachyos`.

The ACPI device is `\_SB.PCI0.SPI1.SPBA`, `_HID`/`_CID` `GXFP51A0`, `_UID=1`: SPI1 CS0, mode 0, 8-bit, 10 MHz, four-wire. It is Goodix GXFP51A0 / GF3658 Milan. GPIO48 is the level-triggered active-high IRQ; GPIO264 is the output-only reset/control line. A virtual Linux IRQ number is **not** GPIO48; it must never be treated as the GPIO identity. `_INI`/`SHPO` grants host ownership / GPIO-pad mode and does not drive a pad high.

```text
GXFP5197 -> 1
GXFP51A7 -> 2
GXFP51A0 -> 3
```

HardwareID 3 reset:

```text
GPIO264 HIGH; wait 10 ms; GPIO264 LOW; wait 100 ms; final state LOW.
```

The GPIO48 IRQ line/pad showed an electrical response to this pulse. This is not generalized into protocol acceptance; a virtual Linux IRQ number remains a separately assigned, changeable number.

## INFERRED

Host pad ownership makes reset control possible, but does not establish the sensor state machine or a packet-acceptance condition.

## Open questions

- Which state and timing precede the first accepted Milan command?

## CONFIRMED Windows fallback relationship

Windows permits the GPIO264 hard-reset fallback only while D0 exit has not
started. Its `g_d0exit_start` flag is cleared on D0Entry and normally set on
D0Exit; a set flag causes `GetEvkVersionWithRetry` to return without reset.
See [windows-fallback.md](windows-fallback.md).

## CONFIRMED Linux exposure on target laptop (2026-08-27)

The CachyOS `7.2.0-1-cachyos` kernel exposes the sensor as the unbound SPI
device `spi-GXFP51A0:00` below the `pxa2xx-spi.4` controller. `spidev.ko` is
provided by the kernel (`CONFIG_SPI_SPIDEV=m`) but `GXFP51A0` is not a native
spidev ACPI alias. A temporary `driver_override=spidev` bind created
`/dev/spidev1.0`; unbind, clearing the override, and unloading spidev restored
the original state. No SPI device was opened and no SPI transfer or GPIO
operation occurred during that bind test.

`/dev/gpiochip0` is the `INT34BB:00` Cannon Lake pinctrl GPIO character device
and exposes 312 GPIO offsets. Pinctrl debug data maps GPIO offset 48 to Intel
pin 41 (`GSPI0_CLK`) and GPIO offset 264 to Intel pin 189 (`UART0_RXD`). The
only line shown as consumed in the GPIO debug snapshot was offset 35 for the
touchpad; offsets 48 and 264 were unclaimed at that time. These offset-to-pin
mappings must not be replaced with raw Intel pin numbers in userspace code.
