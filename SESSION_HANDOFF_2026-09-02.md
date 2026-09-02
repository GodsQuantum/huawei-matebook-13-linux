# Session handoff — 2026-09-02

This supersedes the 2026-09-01 operational boundary.

## Target

- Goodix GXFP51A0 / GF3658 Milan.
- ACPI: `\_SB.PCI0.SPI1.SPBA`.
- SPI1 CS0, mode 0, 8-bit, 10 MHz, FourWire.
- readiness: hardware IRQ 48, level-high.
- Linux virtual IRQ is dynamic and must never be hardcoded.
- reset/control: GPIO264, AS_IS request only.
- proven reset sequence: HIGH 10 ms -> LOW 100 ms -> final LOW.

## Transport

Goodix FP 1.1.141.36 maps GXFP51A0 to mode 5.

Mode 5:

    write outer 4 bytes
    Sleep(2 ms)
    write inner bytes

These are separate synchronous SPB write requests. Linux matches the same
boundary.

## Controller trace

Fresh-boot Linux tracing confirmed:

    spi_set_cs
      -> pxa2xx_spi_set_cs
         -> lpss_ssp_cs_control

for the tested transfers.

No controller error explained the target silence. No sensor IRQ occurred.

## Corrected startup model

DriverState is not the fatal `_DeviceInit` gate.

`send_driver_install_to_MCU()` does not propagate the SetDriverState result.
Windows continues into `init_MCU()`.

`init_MCU()` reaches `GetEvkVersionWithRetry`.

Exact 1.1.141.36 behavior:

- `retry_count_for_common_init` compiled default = 3;
- GetEvkVersion #1;
- GetEvkVersion #2;
- GetEvkVersion #3;
- if all fail and D0Exit has not started: HardResetMcu;
- reset BOOL ignored by this wrapper;
- one final GetEvkVersion.

The Linux research harness now reproduces this control flow.

Maximum completely silent default path: 34 physical SPI transfers.

## Validation

Passed:

- TDD RED;
- TDD GREEN;
- full research tests;
- live runtime compile-only;
- ASAN/UBSAN;
- GCC fanalyzer;
- source safety;
- privacy and secret checks.

## Safety locks

- no firmware flash/upload/erase flow;
- no speculative MMIO/pinmux/power writes;
- no generic wake guesses;
- no hardcoded virtual IRQ;
- no second active probe on a consumed boot;
- GPIO264 final LOW cleanup remains mandatory.

## Next

Fresh boot only.

Run the corrected Windows-faithful bootstrap once, through the complete
GetEvkVersionWithRetry boundary.

If still silent, continue software-only with DMA-vs-PIO and deeper LPSS /
runtime-PM instrumentation.
