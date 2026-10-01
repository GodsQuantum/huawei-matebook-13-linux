# HANDOFF — GXFP51A0 / GF3658 ST411 — rel72 S3 hardware-park candidate

Date: 2026-10-01
Canonical workspace: `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/`
Repo: `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/`
GitHub: `GodsQuantum/huawei-matebook-13-linux`
Branch: `fingerprint-rel72-s3-hardware-park`

## Current runtime safety

- rel72 is **NOT installed live**. Pegasus remains on `libfprint-goodix51a0 1.94.100.goodix51a0-71`, `fprintd 1.94.5-2.1`.
- The old rel71 `gxfp51a0-fprintd-suspend.service` is still present/enabled on the live system until the rel72 human gate is intentionally installed.
- No reboot was performed. No enrollment/template was changed.
- Physical tests are always triggered by Arezki.

## Why rel71 is rejected

rel71 stopped fprintd before S3. That prevented the rel61/rel66 driver suspend lifecycle from touching the ST411 while the transport was alive. The failing rel71 S3 showed post-resume readiness followed by genuine 3/7 images.

The historical rel66 7/7 S3 success was also found to depend on the sensor already being parked in Windows sleep `0x60 01 00` before the successful S3. A later clean rel66 attempt without that park reproduced the failure. Boot-prewarm alone was therefore insufficient.

## rel72 architecture

### Driver core

Rel72 deliberately keeps the proven rel60/61 biometric path:

- rel48 safe GET_IMAGE retry rule;
- rel59 retry-assisted same-press pacing;
- rel60 WakeupMCU between weak physical poses;
- warm TTL 5 min;
- fresh background/FDT after a real cold boundary;
- SIGFM v4 matcher; threshold 7;
- no rel47 early weak-score cutoff;
- no rel51 indefinite warm;
- no rel62-64 fast-resume in-place reconstruction.

### New S3 boundary

The only new driver hardware action is Windows-compatible MCU park during the actual libfprint suspend callback:

`0x60 payload 01 00 -> ACK`

The driver then closes stale TLS/transport state and marks the next Claim/Open as a cold boundary. **Normal `gx_dev_close()` does not send 0x60**, because rel68 proved that `SLEEP 0x60 -> WakeupMCU -> WARM_REBASE` is a bad normal-use path on this ST411 (4/7, 3/7, 3/7).

### fprintd integration

The idle-device problem is solved at the fprintd layer rather than by stopping the daemon:

- when `PrepareForSleep(true)` arrives and the exact driver is `goodix51a0`, fprintd opens the device if it was idle/closed;
- libfprint then reaches the driver suspend callback while SPI/TLS is live;
- the driver sends the Windows `0x60/01 00` park;
- after resume, fprintd resumes and closes the temporary sleep-opened device;
- rel61 KScreenLocker then starts a fresh fingerprint PAM authentication;
- the next Claim/Open performs a clean cold driver preparation.

The patch is intentionally restricted to `goodix51a0`; other fingerprint devices keep native fprintd suspend behavior.

Detailed source-by-source research is recorded in `fingerprint/research/REL72_WEB_GITHUB_RESEARCH_2026-10-01.md`.

Candidate package hashes:
- `fprintd-1.94.5-72-x86_64.pkg.tar.zst`: `9f45604f88d28aaf014ff85940f783411a83d8c8ed635e6ba1b19ab6ed4321e0`
- `libfprint-goodix51a0-1.94.100.goodix51a0-72-x86_64.pkg.tar.zst`: `7adc8c66389a76c87c35960ede04f0adaf1108745d7ac1c0714554cea3fc5c01`

## Research cross-check — 2026-10-01

Repositories/messages reviewed:

- `GodsQuantum/huawei-matebook-13-linux` — Huawei MateBook 13 / GXFP51A0-specific runtime reports.
- `szlukabence/goodix-fingerprint-spi-linux` — ST411/Goodix SPI protocol notes, FDT/transport timing and target-specific sequencing.
- `tlambertz/goodix-fingerprint-reversing` — Windows reverse engineering; confirms `FpMcuSwitchToSleepMode` / command `0x60`, payload `01 00`, with ACK before later power transition.
- `Sigfrodr/libfprint-goodixtls` — similar Goodix TLS lifecycle; handshake/session exhaustion reinforces keeping cached session state during normal use and using a clean lifecycle boundary after real power events.
- `berkekbgz/libfprint-goodix-spi` — warm/background and transport timing patterns; useful cross-check, not copied blindly because target-specific behavior differs.
- `lexakimov/goodix51c0_spi-reversing` and `Rockytkg/goodix-linux-27c6-5125` — similar Goodix SPI families; used only for protocol/lifecycle comparison, not as target-equivalent implementations.

Important conclusion: target-specific MCU lifecycle beats generic Goodix assumptions. The same `0x60` sleep sequence is correct for the Windows ST411 path but is **not** correct as a normal-use warm optimization.

## Build/verification results

- `make research`: PASS after rel72 safety tests were added.
- `make build`: PASS; libfprint v1.94.100 / goodix51a0 object compiled; artifact gates PASS; no sensor I/O, GPIO writes, MMIO writes or firmware actions during build.
- Arch package: `libfprint-goodix51a0 1.94.100.goodix51a0-72` built successfully.
- fprintd source: upstream/Arch `fprintd 1.94.5` + rel72 patch compiled successfully.
- clean-path fprintd tests: 35/36 PASS; the sole failure is the upstream daemon test because the local environment lacks the `gi.repository.FPrint` introspection namespace. PAM suite passed 100% on the space-free path.
- canonical-path fprintd test initially showed PAM failures caused by the workspace path containing spaces being truncated by `pam_wrapper`; this is an environment/path issue, not a rel72 patch failure.

## Human gate — NOT YET RUN

Do not install rel72 or reboot automatically. When intentionally testing:

1. install the rel72 libfprint package;
2. install the rel72 fprintd package;
3. remove/disable the obsolete rel71 stop/start sleep.target service;
4. restart fprintd only if needed; do not reboot unless the human test requires it;
5. perform one normal lock/unlock first;
6. then one deep S3;
7. after resume, touch only after the fingerprint UI is ready;
8. inspect for `S3_PARK`, `SLEEP 0x60/01 00 acknowledged`, fresh post-resume Claim/Open, READY and first biometric score.

Expected successful sequence:

`PrepareForSleep -> fprintd Open -> S3_PARK SLEEP ACK -> transport close -> S3 -> resume -> fprintd Resume -> temporary Close -> KScreenLocker rel61 PAM restart -> fresh Claim/Open -> READY -> >=7 score`

Do not lower threshold, change templates, reintroduce rel62-64 fast-resume, or add another sleep command before this gate is evaluated.
