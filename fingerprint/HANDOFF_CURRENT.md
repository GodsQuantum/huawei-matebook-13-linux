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

## Latest live verify

A rel7 right-index attempt on 2026-09-19 produced a complete 10,573-byte image
and a terminal score of `0 / threshold 15`. The verdict was emitted while the
finger was still present, so removal timing did not cause that no-match.

Do not change matcher thresholds from this single sample. Next step is repeated
guided genuine-finger sampling and rel6/rel7 input comparison if the near-zero
scores reproduce.

## Publication

README EN/FR, provenance, native desktop integration, source-build installer,
Arch packaging, release privacy gates and CI checks have been prepared for the
public repository. Build/package artifacts are git-ignored.

See the detailed handoff for all invariants and resume instructions.
