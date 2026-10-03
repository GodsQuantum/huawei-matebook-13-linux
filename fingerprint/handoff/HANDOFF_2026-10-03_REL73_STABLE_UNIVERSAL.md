# HANDOFF — GXFP51A0 rel73 stable-universal candidate — 2026-10-03

## Status

rel73 is a runtime candidate, installed on Pegasus for human validation.
It is NOT yet declared stable and must not be tagged/released until normal-lock
and deep-S3 gates pass.

Runtime gate environment:
- Huawei MateBook 13 2021 / Goodix GXFP51A0 / GF3658 ST411
- running kernel: linux-cachyos 7.2.8-2-cachyos
- libfprint-goodix51a0: 1.94.100.goodix51a0-73
- installed libfprint SHA256:
  02843f600205d97e70a9c053d663575abe4d6b0f1a9d6e0bc59ba4da70683ed2
- package SHA256:
  646b867399cb133d85a6a0b5331ef54c97f8569e5202b5b1b64dfcec4dfd4f0a
- fprintd remains distribution stock 1.94.5-2.1 for Gate 1 isolation
- fprintd SHA256:
  db4e909a968af7b19cff249b2b3546fefdc80f277c11afb7ee083e0878c2cb63
- three enrollments preserved
- SIGFM threshold remains 7
- no re-enrollment
- no heartbeat / keepalive
- no persistent timing-learning file
- no external system-sleep fingerprint hook
- boot-prewarm disabled

## Human-validated lineage retained

The candidate is reconstructed from pieces with real human success rather than
from the most recent release number.

- rel48: cold login 23/7; deep S3 11/7; accepted GET_IMAGE timeout never blindly replayed.
- rel50: normal lock PASS; same-press rescue validated.
- rel59: normal lock PASS; 5/7 -> 6/7 -> 7/7; 90 ms retry-assisted pacing useful.
- rel60: normal lock PASS; first genuine pose 9/7; MCU rearm after failed full pose and lift.
- rel61: deep S3 PASS; first genuine post-READY image 20/7; unlock PASS; fresh cold
  GPIO reset -> firmware/A8 -> TLS -> background/FDT is the quality baseline;
  KScreenLocker PAM restart fixed the stale worker; resume -> READY ~21.5 s.
- rel66: one deep-S3 PASS, first usable image 7/7; Windows deactivate 0x60/01 00 ACK viable.
- rel68/69: negative proof: 0x60 on ordinary Close damages normal capture quality.
- rel71: reconstructs the functional rel61 driver core; rel73 base.
- rel72: proved the idle/closed PrepareForSleep opening problem, but normal-lock regression
  existed independently of its S3 fprintd patch.

## 2026-10-03 external research conclusions

- berkekbgz/libfprint-goodix-spi, GDIX51C0 / ChicagoHS:
  Windows gfspi uses a 1 ms pre-submit guard, 1000 ms ACK window, one retry after
  missing ACK, bounded long response windows, and cold-boundary image/FDT rebuild.
- Sbenazar/goodix-5f10-libfprint, ST411SEC sibling:
  per-sensor OTP analog/timing calibration materially changes image quality.
- szlukabence/goodix-fingerprint-spi-linux:
  same GXFP51A0/ST411 family; the GF_ST411SEC_APP_14115 Windows transcript confirms
  FDT-down -> SLEEP 0x60 / 01 00 -> ACK -> D0Exit/D3, with 1000 ms ACK deadline.

The GXFP51A0 driver already derives OTP tcode, fdt_delta and DAC values from the live
unit, so rel73 does not copy sibling-sensor calibration constants.

## rel73 delta

- target ACK IRQ deadline: 100 ms -> 1000 ms
- FDT manual ACK/response deadline: 100 ms -> 1000 ms
- response-bearing capture commands: bounded 1000 ms no-reply window
- 1 ms pre-submit guard matching gfspi
- one whole-command retry only when required ACK/response was never observed
- GET_IMAGE retains rel48 safety: never replay an already-accepted command
- fast path is not delayed by 1 s bounds because IRQ wait returns immediately
- rel59 same-press pacing and rel60 MCU rearm retained
- session-local timing only; nothing persisted
- SIGFM threshold remains 7
- obsolete external gxfp51a0-fprintd-suspend.service explicitly disabled

## Software gates

make -C fingerprint/research test: PASS, including transport, TLS, OTP, FDT,
capture recovery, same-press, MCU rearm, session-local timing, native resume,
dual auth, SIGFM fp_eval and new Windows transport parity gate.

Canonical package build:
- SOURCE_MANIFEST=PASS
- LIBFPRINT_PATCH=PASS
- MESON_CONFIGURE=PASS
- LIBFPRINT_BUILD=PASS
- release biometric dump hook absent
- ACTIVE_SENSOR_IO=NONE
- GPIO_WRITES=NONE
- MMIO_WRITES=NONE
- FIRMWARE_ACTIONS=NONE

## Next gates

Gate 1: one normal lock on running 7.2.8-2; require score >=7 and unlock, then
inspect ACK retries, timing scale, GET_IMAGE retries and READY latency.

Gate 2 only after Gate 1 passes: install native fprintd PrepareForSleep open boundary,
then one deep-S3 test; require 0x60 ACK before D3, fresh post-resume Claim/Open,
READY, score >=7, unlock, and password fallback.

Prepared but NOT installed fprintd S3 package:
- fprintd 1.94.5-73
- SHA256: 62b66445da23cb0e49287bc9bbf3f5516ab77c116d14c109bf999dfb05561f86
- source-safety gate: PASS
- compile/package: PASS
- upstream PAM test suite is path-sensitive and fails because pam_wrapper splits the canonical project path at the spaces in 'Capteur Empreinte Huawei'; the failure is environmental, before any hardware I/O and unrelated to the S3 patch. Package was therefore produced with --nocheck after source gates and successful compilation.
- temporary build dependencies were removed afterward; no new pacman orphans remain.

Only repeatable human success can promote rel73 to stable. Portability is a target;
do not claim every distribution is validated before actual cross-distro testing.
