# Current handoff — GXFP51A0 / GF3658 Milan

**Updated: 2026-09-19 23:55.**

Canonical detailed handoff:

`handoff/HANDOFF_2026-09-19_2355_GXFP51A0_NATIVE_FPRINTD_RELEASE.md`

Read that file in full before changing the driver.

## Current state

- installed on reference MateBook: `libfprint-goodix51a0 1.94.100.goodix51a0-7`;
- fprintd: `1.94.5-2.1`;
- native libfprint/fprintd integration; no device-specific desktop UI;
- right-index template remains enrolled;
- rel7 lifecycle/identify/privacy changes build and install successfully;
- complete software baseline and reproducible libfprint build PASS;
- release biometric dump writer absent from final library;
- standard libfprint identify path present in final library.

## Human interaction

Do not coordinate finger timing through chat.

Use:

```bash
./fingerprint/tools/gxfp51a0-verify-diagnostic.py
```

The harness follows fprintd's standard D-Bus `finger-needed` and
`finger-present` properties and gives local POSE/GARDE/RETIRE instructions.
The physical finger label is displayed in uppercase.

For score-distribution diagnostics, use:

```bash
./fingerprint/tools/gxfp51a0-compare-fingers.py
```

Default sequence: INDEX DROIT x3, then INDEX GAUCHE, MAJEUR GAUCHE and
MAJEUR DROIT against the enrolled right-index template. It writes one aggregate
JSON report under `~/.local/state/gxfp51a0/`.

## Latest live verify

Rel7 right-index attempts produced complete 10,573-byte images with genuine
scores observed at `0 / 15` and then `8 / 15`. The latest capture took about
1.54 s. Both terminal no-match decisions were emitted while the finger was
still present, so removal timing did not cause those failures.

Do not change matcher thresholds from isolated samples. The next step is the
six-scan multi-finger comparison above to measure genuine dispersion versus
negative-control scores before touching matcher logic.

## Publication

README EN/FR, provenance, native desktop integration, source-build installer,
Arch packaging, release privacy gates and CI checks have been prepared for the
public repository. Build/package artifacts are git-ignored.

See the detailed handoff for all invariants and resume instructions.
