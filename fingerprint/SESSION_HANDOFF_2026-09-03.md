# Session handoff — 2026-09-03

This supersedes the 2026-09-02 operational boundary.

## Target

- Goodix GXFP51A0 / GF3658 Milan.
- ACPI `\_SB.PCI0.SPI1.SPBA`.
- SPI1 CS0, mode 0, 8-bit, 10 MHz, FourWire.
- readiness hardware IRQ 48, level-high.
- Linux virtual IRQ is dynamic and must never be hardcoded.
- reset/control GPIO264, AS_IS only.
- proven reset: HIGH 10 ms -> LOW 100 ms -> final LOW.

## Fixed Windows-faithful boundary

GXFP51A0 selects Goodix transport mode 5.

Each Milan packet is:

    synchronous SPB write: outer 4 bytes
    sleep 2 ms
    synchronous SPB write: inner bytes

The corrected startup flow continues after silent DriverState and reaches the
complete `GetEvkVersionWithRetry` boundary.

Maximum silent default path:

- 34 physical SPI transfers;
- 180 TX bytes;
- 12 readiness/ACK waits.

## Completed normal-path result

The complete Windows-faithful common-init has already executed on a fresh
ordinary boot and remained fully silent:

- 34 transfers;
- 12 waits;
- 0 Goodix IRQ events;
- 0 reads;
- 0 EVK bytes;
- both fallback resets successful;
- no SPI controller error/timeout;
- final GPIO264 LOW.

## Completed deterministic PIO discriminator

A dedicated one-shot boot blocked IDMA64 before the PXA2xx controller probed.

Pre-active proof:

- both IDMA64 blacklist forms present;
- IDMA64 module absent;
- IDMA64 devices unbound;
- target SPI statistics zero;
- matching PXA2xx controller active;
- exact kernel log `no DMA channels available, using PIO`.

Only after all gates passed did the unchanged common-init run once.

Result:

- 34 SPI transfers;
- 180 TX bytes;
- 12 waits;
- 0 Goodix IRQ events;
- 0 RX reads;
- 0 EVK bytes;
- DriverState fallback reset success;
- common-init fallback reset success;
- no SPI errors/timeouts;
- final GPIO264 LOW.

The PIO result is materially identical to the established DMA-silent result.
DMA versus PIO is therefore closed as the primary explanation.

Do not rerun the PIO experiment merely to reconfirm this result.

## Normal DMA / LPSS passive baseline

A later normal fresh boot was inspected without active sensor traffic.

Confirmed:

- IDMA64 module loaded;
- matching IDMA64 device bound;
- PXA2xx SPI controller bound;
- no PIO fallback log;
- GXFP51A0 target unbound;
- empty driver override;
- zero target SPI statistics before and after the audit;
- exactly two DMAengine channels associated with the LPSS parent.

The initial zero-channel result was a diagnostic bug: it matched only
descendants of the LPSS parent, while the relevant DMA channel devices resolve
to the parent itself.

## Linux v7.2 DMA confirmation

Upstream PXA2xx LPSS code confirms:

- DMA enabled by default on the platform path;
- burst size = 1 byte;
- TX/RX compatibility parameters point to the LPSS parent;
- the DMA filter matches `chan->device->dev` to that parent;
- separate TX and RX channels are requested;
- native PIO fallback is used when DMA setup fails;
- the short common-init transfers are DMA-eligible.

## Runtime-PM idle baseline

At idle on the normal boot:

- PXA2xx SPI controller runtime status: suspended;
- LPSS PCI parent runtime status: suspended;
- PXA2xx autosuspend delay: 50 ms.

This does not prove the state during transfer execution.

## Passive tracing capability audit

Still on a zero-activity boot:

- tracefs mounted;
- debugfs mounted;
- kernel has tracing, function tracer, function graph tracer and dynamic
  ftrace;
- kernel has kprobes, kprobe events and fprobe;
- BPF and BTF available;
- vmlinux BTF available;
- IDMA64 and Intel LPSS module BTF available;
- PXA2xx SPI module BTF not exposed;
- high-value PXA2xx/LPSS/IDMA symbols visible in kallsyms.

The passive audit's non-root readability check did not obtain
`available_events` or `available_filter_functions`. Recheck tracefs as root
before choosing the next instrumentation method.

## Current next step

Do not run another active fingerprint experiment yet.

First, on a fresh normal zero-activity boot:

1. enumerate tracefs as root;
2. identify available relevant tracepoints/functions;
3. choose the least invasive mechanism among ftrace, kprobe/fprobe or a
   read-only instrumentation module.

Then prepare exactly one active common-init run with instrumentation around:

- PXA2xx runtime resume/suspend;
- LPSS parent runtime state;
- `pxa2xx_spi_transfer_one`;
- DMA prepare/start/completion;
- `spi_set_cs`;
- transfer finalization;
- controller IRQ activity.

Keep the Goodix protocol unchanged.

## Safety locks

- no firmware flash/upload/erase;
- no speculative MMIO;
- no speculative pinmux;
- no generic wake guesses;
- no hardcoded virtual IRQ;
- no second active run on a consumed boot;
- mandatory final GPIO264 LOW.

Canonical technical boundary:

`docs/controller-boundary-2026-09-03.md`.
