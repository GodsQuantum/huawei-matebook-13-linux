# GXFP51A0 current boundary — 2026-09-07

This document supersedes earlier DMA/PIO/runtime-PM next-step guidance.
There is still no known working Linux fingerprint driver for GXFP51A0.

## Validated target boundary

- Goodix GXFP51A0 / GF3658 Milan, direct Intel LPSS/PXA2xx SPI.
- SPI mode 0, 8-bit, 10 MHz.
- Goodix FP 1.1.141.36 selects transport mode 5.
- One Milan packet: synchronous outer 4-byte write -> ~2 ms -> separate inner write.
- Readiness hardware IRQ 48, level-high; Linux virtual IRQ is dynamic.
- Reset GPIO264: HIGH 10 ms -> LOW 100 ms -> final LOW.
- No firmware flash/upload/erase belongs to the validated path.

## Complete common-init and controller closure

The Windows-faithful default common-init completed on Linux with 34 physical
SPI transfers, 180 TX bytes and 12 waits, but 0 Goodix IRQ events and 0 EVK bytes.
Both fallback resets completed and final GPIO264 was LOW.

DMA versus deterministic native PIO is closed: both produced the same silence.

A normal-DMA trace then proved the concrete target controller path:

- 34 target `spi_transfer_start` and 34 `spi_transfer_stop` events;
- 34 `pxa2xx_spi_dma_prepare` and 34 `pxa2xx_spi_dma_start` calls;
- 68 `idma64_issue_pending` calls;
- exactly 34 `irq=23 name=idma64.4` entries, all handled;
- 34 shared PXA2xx IRQ-action calls on IRQ23, all unhandled;
- 0 Goodix IRQ events and no trace loss.

The earlier `idma64_irq=10957` gate was a false positive: that ftrace symbol is
global across Intel iDMA instances. The concrete target IRQ count is 34.

## Runtime-PM closed

A separate one-shot run held the relevant LPSS parent and PXA2xx controller
runtime-active throughout the common-init. The active window contained zero
relevant runtime suspend/resume callbacks and the sensor remained silent.
Runtime-PM cycling is therefore strongly eliminated as the cause.

## Same-wire MISO observation

PXA2xx requires RX and TX, so the historical TX-only userspace writes were
already clocking RX into a dummy buffer. A one-shot observation retained those
same already-clocked bytes without adding a SPI message, MOSI byte or clock.

Validated result:

- 34 writes;
- 180 retained RX bytes;
- all 180 bytes were `0xFF`;
- exactly 34 target iDMA IRQ completions;
- 0 Goodix IRQ events;
- no trace loss.

`0xFF` cannot distinguish actively driven high from high-impedance plus pull-up,
but no informative MISO response was observed anywhere in the common-init.

## Can a neighbouring working driver simply be tried?

Not by force-binding it merely because it is another Goodix SPI/Milan device.

### GXFP3200

`bchapoton/goodix-gxfp3200-linux` is a working Milan SPI -> libfprint/fprintd/PAM
driver published 2026-09-02, with v0.2.0 on 2026-09-05. It is an important
reverse-engineering precedent, but it binds GXFP3200 and uses an F0/F1 register
protocol. Its startup resets LOW -> HIGH with final HIGH, writes target-specific
registers and sends `0xC0` before chip-ID probing. Those facts differ from the
already-proven GXFP51A0 mode-5 transport and final-LOW reset.

Source: https://github.com/bchapoton/goodix-gxfp3200-linux

### GXFP5187 and GDIX51C0

`Sigfrodr/libfprint-goodixtls` (GXFP5187) and
`berkekbgz/libfprint-goodix-spi` (GDIX51C0) are working architectural precedents.
Their startup/config/TLS/PSK behavior is device-specific and must not be forced
onto GXFP51A0 without same-device evidence.

Sources:
- https://github.com/Sigfrodr/libfprint-goodixtls
- https://github.com/berkekbgz/libfprint-goodix-spi

## Public-source status — 2026-09-07

No working GXFP51A0 Linux driver was found in the current GitHub/web reassessment.
OpenGoodixSPI registers GXFP51A0 but remains protocol-research infrastructure,
not a complete fingerprint implementation. `PopulusYang/GXFP51A0-driver-failed`
is useful static research but is also not a working driver.

The newly working sibling drivers substantially reduce downstream risk: once
GXFP51A0 communication is established, current open-source examples exist for
capture, image decoding, matching, libfprint, fprintd and PAM integration.

## Productive work without Windows or special hardware

Continue offline/static first:

1. audit Goodix FP 1.1.141.36 before the first accepted DriverState/GetEvkVersion
   traffic, including PnP/PrepareHardware/D0Entry;
2. compare exact GXFP51A0/GXFP51A7 paths with nearby working Goodix SPI drivers
   only where functions/data are demonstrably homologous;
3. reuse transport-independent libfprint/matcher architecture downstream;
4. keep firmware/provisioning paths static-only.

If this produces no target-specific missing state transition, a working-Windows
WDF/WPP/ETW/SPB trace or physical CS/SCLK/MOSI/MISO/IRQ capture becomes the
highest-value missing evidence.

## Active-test rule

No new active GXFP51A0 experiment unless same-device evidence identifies one
precise missing action. Do not force-bind sibling drivers as a blind test.

Safety locks remain: no firmware, no speculative MMIO/pinmux/wake, no hardcoded
virtual IRQ, no second active run on a consumed boot, final GPIO264 LOW mandatory.
