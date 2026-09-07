# Session handoff — 2026-09-07

Canonical state: [`docs/current-boundary-2026-09-07.md`](docs/current-boundary-2026-09-07.md).

The complete 34-transfer common-init, deterministic PIO comparison, normal-DMA
controller trace, runtime-PM-held discriminator and same-wire MISO observation
are complete and must not be repeated merely to reconfirm silence.

Latest validated result: 34 target transfers, 34 concrete `idma64.4` IRQ
completions, 0 Goodix IRQ events, 180 retained RX bytes, all `0xFF`, no trace loss.
The historical `idma64_irq=10957` abort was a global-ftrace counting bug.

No new active Linux fingerprint CLI should be proposed without new same-device
evidence. Continue static/pre-first-command analysis first.

New 2026 working precedents:

- `bchapoton/goodix-gxfp3200-linux` — working Milan SPI driver;
- `Sigfrodr/libfprint-goodixtls` — working GXFP5187 driver;
- `berkekbgz/libfprint-goodix-spi` — working GDIX51C0 driver.

These are architecture/reverse-engineering references, not drop-in GXFP51A0
drivers. In particular GXFP3200 has F0/F1 I/O and LOW->HIGH/final-HIGH reset,
which differ from the proven GXFP51A0 path.

OpenGoodixSPI maintainer PeshalaDilshan has offered collaboration/maintainership;
this is useful organizationally but is not itself a technical breakthrough.
