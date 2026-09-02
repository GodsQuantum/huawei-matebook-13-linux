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

The corrected Windows-faithful common-init run is complete and remained fully
silent through all 34 expected SPI transfers.

The next software discriminator is DMA versus PIO on the PXA2xx/LPSS
controller.

A simple IDMA64 blacklist must not be assumed sufficient. The next experiment must first establish and prove a deterministic PXA2xx PIO-only state, using boot-time binding control or a minimal instrumented controller variant if necessary, and abort before sensor traffic unless PIO is proven.

No active experiment may be repeated on a consumed boot.

<!-- common-init-supervisor-2026-09-02 -->
## Next-run supervisor

- confirmation token: `GXFP51A0_REVIEWED_COMMON_INIT_20260902`
- wall-clock watchdog: 20 seconds
- deterministic silent-path budget: approximately 12389 ms
- one active execution maximum per fresh boot
- no automatic retry
- process-group termination and final GPIO264 LOW cleanup remain mandatory

<!-- common-init-live-closure-2026-09-02 -->
## Completed live common-init result

The reviewed one-shot run reached the complete expected silent bound:

- `PROBE_RESULT=ACK_TIMEOUT`;
- DriverState fallback reset: success;
- common-init fallback reset: success;
- 34 SPI transfers;
- 12 IRQ waits;
- 0 Goodix IRQ events;
- 0 reads;
- 0 EVK response bytes;
- 0 controller errors/timeouts;
- final GPIO264 LOW cleanup confirmed.

This rejects early termination at DriverState or an incomplete
`GetEvkVersionWithRetry` implementation as the explanation for the silence.

See `docs/dma-pio-reassessment-2026-09-02.md`.

<!-- pio-preflight-ready-2026-09-02 -->
## PIO experiment gate prepared

The repository contains a dedicated fail-closed PIO experiment gate:

- `research/linux/pio_preflight.sh`;
- `research/linux/pio_live_probe_supervisor.sh`.

The preflight changes no controller or fingerprint state. It only accepts a
fresh boot that already proves the PXA2xx controller selected its native PIO
fallback before any Goodix traffic.

The dedicated active confirmation token is:

`GXFP51A0_REVIEWED_PIO_20260902`

After this gate passes, the existing supervised Windows-faithful common-init
probe may run exactly once on that boot.

The next live experiment must also collect controller function tracing,
SPI statistics, IRQ counts and runtime-PM state so that a silent PIO result
still closes several hypotheses in one run.
