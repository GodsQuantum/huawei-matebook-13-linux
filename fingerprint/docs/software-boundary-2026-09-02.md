# GXFP51A0 software boundary — 2026-09-02

This document is the current canonical technical boundary for the Goodix
GXFP51A0 / GF3658 Milan research on the Huawei MateBook 13 2021.

## Transport

Exact static analysis of Goodix FP 1.1.141.36 establishes:

- `ACPI\GXFP51A0` selects transport mode 5.
- Mode 5 sends each Milan packet as:
  - synchronous SPB write of the outer 4-byte header;
  - 2 ms delay;
  - separate synchronous SPB write of the inner bytes.
- The target mode-5 transmit path does not use the atomic SPB execute-sequence
  helper.
- Linux already matches this transaction boundary with two separate
  `SPI_IOC_MESSAGE(1)` requests and the same 2 ms gap.

## Linux controller path

A fresh-boot live trace observed the tested SPI traffic traversing:

    spi_set_cs
      -> pxa2xx_spi_set_cs
         -> lpss_ssp_cs_control

CS activation/deactivation occurred around the tested transfers. Controller
completion was clean and no SPI controller errors or timeouts explained the
silence.

The sensor itself generated no readiness IRQ.

This rejects the simple hypotheses that:

- Linux userspace GPIO polling was the root cause;
- native ACPI IRQ mapping was wrong;
- the main GSPI1 pads were not in native mode;
- Linux never executed the LPSS CS-control path;
- Windows required outer+inner to be one CS-held atomic sequence.

Short transfers were observed using the controller DMA path. DMA-vs-PIO
remains a possible later software discriminator, not a demonstrated cause.

## Corrected Windows startup model

The earlier Linux research probe incorrectly treated DriverState as the
effective startup gate.

Normal Windows startup enters:

    send_driver_install_to_MCU()
    device_action(...)
    init_MCU()

`send_driver_install_to_MCU()` calls `SetDriverState(Install)`, but does not
propagate the `SetDriverState()` result as the `_DeviceInit` gate.

Therefore a completely silent DriverState sequence may reach:

    NOP
    Install
    Install retry
    Install
    Install retry
    HardResetMcu

and Windows still continues into `init_MCU()`.

The first meaningful sensor-response gate is `GetEvkVersionWithRetry`.

For exact Goodix FP 1.1.141.36:

- configuration field `retry_count_for_common_init`;
- compiled default = 3;
- optional registry override is used only when valid;
- three initial `GetEvkVersion` attempts;
- after all three fail, if D0Exit has not begun:
  - `HardResetMcu`;
  - its BOOL result is not used to suppress continuation;
  - one final `GetEvkVersion`.

Each individual `GetEvkVersion` remains:

    NOP
    5 ms
    A/4
    wait for B/0 ACK identifying packed A/4 = 0xA8
    retransmit the exact A/4 once after ACK timeout
    wait for event 9 response

## Linux research harness

The harness now models:

- DriverState wrapper retries;
- DriverState fallback reset;
- the fact that Windows continues after the DriverState result;
- three default outer `GetEvkVersion` attempts;
- retry of Windows-style false GetEvkVersion outcomes;
- common-init `HardResetMcu`;
- one final GetEvkVersion;
- diagnostic recording of reset failures;
- mandatory final safe reset cleanup.

Linux-only cancellation/invalid states remain terminal safety conditions.

Maximum fully silent default path:

    DriverState NOP                 2 SPI transfers
    four DriverState packets        8
    three initial EVK attempts     18
    one final EVK attempt           6
    ---------------------------------
    total                          34

No firmware-management operation is part of this experiment.

## Validation

The corrected model was implemented TDD-first.

Validation passed:

- expected RED test;
- target GREEN;
- complete research test suite;
- live runtime compile-only test;
- ASAN/UBSAN;
- GCC `-fanalyzer`;
- source-safety tests;
- privacy audit;
- secret audit.

No active sensor I/O occurred while implementing or validating this patch.

## Rejected / strongly demoted directions

Do not return to these without new evidence:

- generic Goodix wake commands;
- `0xB0` as an assumed missing startup wake;
- speculative firmware upload/flash;
- hardcoded Linux virtual IRQ numbers;
- userspace GPIO48 polling as the root cause;
- speculative main pinmux writes;
- `FPEN` as an AML runtime power switch;
- hidden pre-DriverState SPI clock change;
- hidden pre-DriverState `device_action`;
- atomic outer+inner CS-held sequence.

## Next experiment

Software-only, one fresh boot, one active run maximum.

Execute the corrected Windows-faithful startup through the complete
`GetEvkVersionWithRetry` boundary.

Stop:

- immediately on the first real target response; or
- after the single bounded final GetEvkVersion attempt.

If that remains completely silent, continue software-only with:

1. DMA-vs-PIO comparison;
2. deeper LPSS register-state instrumentation;
3. runtime-PM/controller-state comparison;
4. software trace from a working Windows GXFP51A0 if obtainable.

Hardware teardown is not required to continue the investigation.


<!-- common-init-supervisor-2026-09-02 -->
## Reviewed supervisor bound

The corrected Windows-faithful common-init experiment uses confirmation token
`GXFP51A0_REVIEWED_COMMON_INIT_20260902` and a 20-second independent wall-clock watchdog.

The previous 12-second watchdog belonged to the older
single-GetEvkVersion probe and is too short for the corrected silent path.

The deterministic ACK/reset/Milan-gap budget is approximately 12389 ms
before scheduler and controller overhead. The 20-second watchdog
therefore remains bounded while leaving enough margin for the single final
GetEvkVersion attempt.

No automatic same-boot retry is permitted.

<!-- full-common-init-live-result-2026-09-02 -->
## Full common-init live result

The corrected Windows-faithful sequence was executed once on a fresh boot and
reached its complete silent bound exactly:

- 34 physical SPI transfers;
- 12 readiness/ACK waits;
- 0 Goodix IRQ events;
- 0 RX reads;
- 0 EVK response bytes;
- both fallback resets succeeded;
- no controller error/timeout explained the result;
- final GPIO264 LOW cleanup succeeded.

The common-init control-flow correction therefore does not restore
communication.

The next software-only discriminator is controller DMA versus PIO.

See `dma-pio-reassessment-2026-09-02.md`.
