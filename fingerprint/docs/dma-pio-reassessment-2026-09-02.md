# DMA / PIO reassessment — 2026-09-02

This document records only sanitized, generic conclusions. The raw local audit
is intentionally excluded from the public repository.

## Completed Windows-faithful common-init boundary

The corrected common-init path has now been executed to its complete silent
bound:

- 34 physical SPI transfers;
- 180 transmitted bytes;
- 12 readiness/ACK waits;
- 0 Goodix IRQ events;
- 0 RX reads;
- 0 EVK response bytes;
- DriverState fallback reset completed successfully;
- common-init fallback reset completed successfully;
- no SPI-controller error or timeout explained the silence;
- final GPIO264 LOW cleanup completed successfully.

This closes the hypothesis that Linux was merely terminating before Windows'
real common-init response boundary.

The sensor remains silent after the complete reconstructed Windows common-init
sequence.

## Passive DMA / PIO audit

A later audit on the already-consumed boot performed no active sensor action.

Sanitized topology:

- IDMA64 driver form: **loadable**;
- IDMA64 currently loaded: **YES**;
- IDMA64 platform-device count: **4**;
- PXA2xx SPI driver form: **loadable**;
- PXA2xx SPI currently loaded: **YES**;
- `pxa2xx_spi_dma_setup` visible: **no**;
- `pxa2xx_spi_can_dma` visible: **no**;
- explicit PXA2xx PIO fallback visible: **no**.

No raw machine-specific audit data is stored here.

## Next discriminator

Candidate: **deterministic PXA2xx PIO-only setup**.

A simple IDMA64 blacklist must not be assumed sufficient. The next experiment must first establish and prove a deterministic PXA2xx PIO-only state, using boot-time binding control or a minimal instrumented controller variant if necessary, and abort before sensor traffic unless PIO is proven.

The comparison must change only the controller datapath:

1. establish and prove PIO before sensor traffic;
2. keep mode 0, 8-bit words, 10 MHz, Milan packet splitting, waits and reset
   behavior unchanged;
3. execute exactly the same bounded Windows-faithful common-init sequence;
4. stop immediately on a real target response;
5. never repeat an active experiment on the same boot.

If PIO is also fully silent, the next layer is deeper LPSS/runtime-PM and
controller-state comparison, not speculative Goodix protocol commands.

## Safety

No firmware-management operation, speculative pinmux/MMIO write, raw DSM/PSK,
serial number, UUID, hostname, private address or local filesystem path belongs
in this result.

<!-- pio-proof-gate-2026-09-02 -->
## PIO proof gate

The upstream PXA2xx control flow provides a deterministic native PIO fallback:

1. DMA setup requests both TX and RX DMA channels;
2. failure to obtain the channels makes DMA setup fail;
3. the controller logs `no DMA channels available, using PIO`;
4. `enable_dma` is then cleared;
5. the Goodix protocol itself does not need to change.

The target kernel exposes IDMA64 as a loadable driver, so the first PIO
experiment does not require a speculative controller patch.

A dedicated fail-closed preflight now requires all of these facts before any
sensor traffic is authorized:

- IDMA64 was explicitly blocked from loading at boot;
- the `idma64` module is absent;
- enumerated `idma64.*` platform devices are unbound;
- the fingerprint SPI master is bound to `pxa2xx-spi`;
- that exact controller logged its native PIO fallback;
- the fingerprint target has zero previous SPI activity on the boot.

Failure of any gate aborts before active fingerprint traffic.

The PIO comparison keeps mode, speed, framing, waits, reset behavior and the
34-transfer Windows-faithful common-init control flow unchanged.
