# GXFP51A0 controller boundary — 2026-09-03

This document is the current sanitized technical boundary for the Goodix
GXFP51A0 / GF3658 Milan research on the Huawei MateBook 13 2021.

There is still no working Linux fingerprint driver.

## Protocol boundary retained

The reconstructed Windows-faithful common-init remains the fixed protocol
boundary:

- 34 physical SPI transfers on the maximum silent path;
- 180 transmitted bytes;
- 12 readiness / ACK waits;
- SPI mode 0;
- 8-bit words;
- 10 MHz requested speed;
- mode-5 Milan split: outer 4-byte write, 2 ms delay, separate inner write;
- Windows-faithful DriverState retry/reset behavior;
- Windows-faithful `GetEvkVersionWithRetry`;
- deterministic Linux A/4 fixture `00 00`;
- mandatory final GPIO264 LOW cleanup.

No firmware-management operation belongs to this boundary.

## Deterministic native PIO proof

The PXA2xx PIO experiment executed once on a fresh boot.

Before active sensor traffic it proved:

- IDMA64 explicitly blocked at boot;
- `idma64` module absent;
- IDMA64 platform devices unbound;
- fingerprint SPI master bound to `pxa2xx-spi`;
- kernel log `no DMA channels available, using PIO`;
- fingerprint target statistics at zero.

Therefore the active comparison genuinely changed the controller datapath.

## PIO live result

The unchanged common-init completed with:

- 34 physical SPI transfers;
- 180 transmitted bytes;
- 12 IRQ/readiness waits;
- 0 Goodix IRQ events;
- 0 RX reads;
- 0 EVK response bytes;
- DriverState fallback reset succeeded;
- common-init fallback reset succeeded;
- no SPI controller error or timeout;
- final GPIO264 LOW.

This is materially identical to the earlier normal DMA result.

**Conclusion:** DMA versus PIO does not explain the current target silence and
is closed as the primary discriminator.

Do not repeat the PIO experiment without new evidence.

## Normal DMA / LPSS passive baseline

A separate normal boot was inspected without any GXFP51A0 SPI transaction.

Confirmed:

- IDMA64 module loaded;
- matching IDMA64 device bound;
- PXA2xx SPI controller bound normally;
- no PIO fallback log;
- two DMAengine channels associated with the same Intel LPSS PCI parent;
- GXFP51A0 target present and unbound;
- driver override empty;
- target SPI statistics remained zero throughout the passive inspection.

Idle runtime-PM state showed the PXA2xx SPI controller and its LPSS PCI parent
runtime-suspended. This is an idle-state baseline only and does not establish
their state during an SPI submission.

## DMAengine sysfs correction

An initial passive script reported zero matching DMA channels because it
accepted only channel device paths below the LPSS PCI parent.

That criterion was wrong for this driver. The relevant DMAengine channel
devices resolve to the LPSS parent itself. Equality matching identifies
exactly two channels.

## Linux v7.2 source cross-check

Upstream Linux v7.2 confirms the normal LPSS PXA2xx path:

- `pxa2xx_spi_init_pdata()` sets `enable_dma = true`;
- `dma_burst_size = 1`;
- TX/RX compatibility parameters use the parent device;
- the DMA filter accepts a channel when `chan->device->dev` matches that
  parent;
- `pxa2xx_spi_dma_setup()` requests separate TX and RX slave channels;
- failure to acquire them causes the controller's native PIO fallback;
- per-transfer DMA eligibility accepts transfers at least as large as the
  configured burst size.

The deterministic PIO boot and normal DMA baseline are therefore a valid
controller-datapath comparison.

## Tracing capability audit

A zero-activity normal boot was inspected passively.

Kernel configuration confirms:

- tracing and tracepoints;
- function and function-graph tracing;
- dynamic ftrace;
- kprobes and kprobe events;
- fprobe;
- BPF;
- BTF;
- debugfs;
- PXA2xx SPI;
- Intel IDMA64;
- Intel LPSS.

Additional observations:

- tracefs is mounted;
- debugfs is mounted;
- vmlinux BTF is available;
- IDMA64 and Intel LPSS module BTF are available;
- PXA2xx SPI module BTF was not exposed by the inspected kernel;
- high-value PXA2xx/LPSS/IDMA symbols are visible in kallsyms except one
  internal IDMA helper.

The passive audit's unprivileged readability test did not expose tracefs
event/function lists. Since tracefs is mounted and the kernel enables the
relevant facilities, root-privileged passive enumeration is the next gate.

## Next passive gate

On a fresh normal boot with zero fingerprint activity:

1. enumerate tracefs capabilities as root;
2. identify relevant tracepoints and filterable functions;
3. select the least invasive observation mechanism among existing tracepoints,
   ftrace, kprobe/fprobe or a minimal read-only instrumentation module.

No active fingerprint traffic is required for this gate.

## Next active experiment

Only after the passive tracing gate is complete:

- one fresh boot;
- one active common-init execution maximum;
- unchanged Goodix protocol bytes and timing;
- unchanged reset behavior;
- stop on first genuine target response;
- observe PXA2xx runtime resume/suspend;
- observe LPSS parent runtime transitions;
- observe `pxa2xx_spi_transfer_one`;
- observe DMA preparation/start/completion;
- observe chip-select and transfer finalization;
- correlate trace timestamps with SPI statistics and controller IRQ activity.

The purpose is to prove the exact Linux controller state around the first
submitted Milan packet, not to introduce a new Goodix command.

## If software instrumentation remains clean

If Linux demonstrably resumes the correct controller, executes the expected
transfers and chip-select path and reports no controller error while GXFP51A0
still provides no readiness IRQ or RX data, the highest-value next evidence is
a software trace from a working Windows GXFP51A0 system or external
CS/SCLK/MOSI/MISO/IRQ capture.

This is preferable to speculative wake commands, MMIO writes, pinmux changes
or firmware operations.

## Safety

Still prohibited without new reviewed evidence:

- firmware flash/upload/erase;
- generic Goodix wake sequences;
- speculative MMIO writes;
- speculative pinmux writes;
- hardcoded Linux virtual IRQ numbers;
- repeated active runs on a consumed boot.

GPIO264 final LOW remains mandatory after every future active experiment.
