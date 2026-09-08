# Current handoff — GXFP51A0 / GF3658 Milan

**Updated: 2026-09-08 after contributor-tooling consolidation.**

This is the shortest canonical resume point. For the complete technical
checkpoint, read [FINAL_HANDOFF_2026-09-08.md](FINAL_HANDOFF_2026-09-08.md).

## Current state

```text
candidate libfprint v1.94.100 build       PASS
first-contact source regression           PASS
research unit/safety suite                PASS
Windows .36/.40 first-contact diff         CLOSED
DeviceInit/BESD intermediate action        CLOSED_NO_SENSOR_IO
SPB first-contact split-write boundary     MATCHED_HIGH_CONFIDENCE
34-transfer model                          RECONCILED
first real sensor ACK under Linux          NOT OBSERVED
A8/EVK                                     NOT OBSERVED
```

The public candidate includes the latest fidelity corrections:

- no unconditional reset before DriverState;
- DriverState NOP + 5 ms restored;
- no DriverState replay after fallback reset;
- one exact same-attempt A8 retransmission.

## Reproduce the software baseline

A new contributor should begin with exactly:

```bash
make -C fingerprint verify
```

This runs all software-only tests and builds the candidate against the exact
validated libfprint tag.

Contributor tooling is documented in
[docs/contributor-validation-2026-09-08.md](docs/contributor-validation-2026-09-08.md).

## Current hardware boundary

The already-tested Linux common-init remains:

```text
34 SPI transfers
180 TX bytes
12 IRQ waits
0 Goodix IRQ
180 retained RX bytes
180/180 RX = 0xFF
controller completions proven
no controller error
final GPIO264 LOW
```

Do not repeat it unchanged.

## What changed after the previous handoff

The repository now publishes:

- one-shot software validation/build scripts;
- an exact libfprint v1.94.100 build script with pinned Meson/Ninja;
- a passive Linux platform-observability script;
- an optional Windows WDF observability script for external contributors;
- a dedicated GitHub Actions workflow that builds the candidate;
- synchronized EN/FR current-status README files.

The primary development installation has **no Windows boot**, so a working
Windows trace cannot currently be collected locally.

## Next useful evidence

Preferred order:

1. `make -C fingerprint passive-audit` on Linux target hardware;
2. external contributor Windows WDF/SpbCx trace if available;
3. logic-analyzer/oscilloscope comparison of CS/SCLK/MOSI/MISO/GPIO48;
4. only after a concrete new exact-device prerequisite is identified, one
   bounded Linux experiment changing exactly that prerequisite.

First success criterion: **a real sensor-side ACK**.

Only after that proceed to A8/EVK -> exact target config -> DSM/TLS/PSK ->
image -> enroll -> verify -> fprintd/PAM.

## Do not reopen without new evidence

- DMA/PIO;
- runtime PM;
- Linux IRQ mapping;
- userspace polling vs native IRQ wait;
- mode-5 split timing;
- simple SPB split-write semantics;
- GPIO112/GPP_D16;
- hidden LPSS switch;
- DeviceInit `besdenable`;
- fixed 48-byte target PSK;
- unchanged 34-transfer common-init.

## Canonical files

1. `HANDOFF_CURRENT.md`
2. `FINAL_HANDOFF_2026-09-08.md`
3. `docs/contributor-validation-2026-09-08.md`
4. `docs/current-boundary-2026-09-08.md`
5. `docs/deviceinit-besd-spb-closure-2026-09-08.md`
6. `docs/windows-14136-14140-differential-2026-09-08.md`
7. `driver/goodix51a0/README.md`
8. `scripts/README.md`
9. `docs/research-log.md`
10. `docs/safety.md`

## Public-repository locks

No proprietary binaries/firmware, raw DSM material, PSK/derived keys, private
machine identifiers or bulk proprietary disassembly.

No firmware, PSK, speculative MMIO/pinmux or GPIO112 write without new
exact-device evidence.
