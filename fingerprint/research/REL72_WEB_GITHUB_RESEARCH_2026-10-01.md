# rel72 research — GXFP51A0 / GF3658 ST411 — 2026-10-01

## Scope

Cross-check of the local rel38–71 forensic results against current public GitHub repositories, issue/comment threads and Goodix-family reverse engineering. Target is the Huawei MateBook 13 2021 ST411 / GXFP51A0 / GF3658 path.

## Target-specific sources

### GodsQuantum/huawei-matebook-13-linux
https://github.com/GodsQuantum/huawei-matebook-13-linux

- Reviewed Huawei MateBook 13-specific issue/comment traffic, including the long-running fingerprint runtime issues.
- Confirms that the useful target is GXFP51A0/GF3658/ST411 and that post-suspend behavior is sensitive to lifecycle state, not only matcher quality.
- The repo's own successful rel61 human result remains the strongest target-specific proof: deep S3 followed by a real first post-READY image scored 20/7.

### szlukabence/goodix-fingerprint-spi-linux
https://github.com/szlukabence/goodix-fingerprint-spi-linux

- Reviewed ST411 protocol notes, first-contact material, SPI/FDT structure and timing guidance.
- Confirms that the ST411 protocol has target-specific framing and timing; generic Goodix SPI assumptions must not replace the proven GXFP51A0 transport implementation.
- The repository is useful as a protocol sanity check, not as a drop-in driver architecture.

### tlambertz/goodix-fingerprint-reversing
https://github.com/tlambertz/goodix-fingerprint-reversing

- Reviewed Windows reverse-engineering material and logs around sensor deactivation.
- Important finding used by rel66 and rel72: Windows `FpMcuSwitchToSleepMode` sends command `0x60` with payload `01 00`, waits for its ACK, then the later power transition occurs.
- This is the strongest external evidence for the ST411 hardware park command.

## Similar Goodix/TLS sources

### Sigfrodr/libfprint-goodixtls
https://github.com/Sigfrodr/libfprint-goodixtls

- Reviewed lifecycle/handshake issue traffic, including reports of TLS/handshake exhaustion after repeated sessions.
- Useful conclusion: preserve healthy TLS/session state during ordinary warm operation; do not add unnecessary daemon/device restarts or repeated full handshakes.
- Recovery after a genuine power/lifecycle boundary must be explicit and bounded.
- This supports rel59/rel60/rel61's normal warm path and argues against rel62–64's aggressive in-place reconstruction.

### berkekbgz/libfprint-goodix-spi
https://github.com/berkekbgz/libfprint-goodix-spi

- Reviewed warm/background and transport sequencing patterns.
- Useful as an independent confirmation that background calibration and SPI timing are lifecycle-sensitive.
- Not copied blindly: ST411/GXFP51A0 behavior is target-specific and our measured 20/7 rel61 path is stronger evidence for Pegasus.

### lexakimov/goodix51c0_spi-reversing
https://github.com/lexakimov/goodix51c0_spi-reversing

- Reviewed only for family-level protocol/recovery clues.
- 51C0 is not ST411/GXFP51A0; commands and power behavior cannot be assumed equivalent.

### Rockytkg/goodix-linux-27c6-5125
https://github.com/Rockytkg/goodix-linux-27c6-5125

- Reviewed for another Goodix SPI family and matcher/transport lifecycle behavior.
- Useful as comparative evidence only; no target-specific command was imported into rel72 from this repo.

### PeshalaDilshan/OpenGoodixSPI
https://github.com/PeshalaDilshan/OpenGoodixSPI

- Reviewed issue/comment traffic around SPI Goodix behavior.
- Reinforces the need to distinguish transport recovery from sensor power-state recovery.

## Local empirical evidence reconciled with research

| Component | Best validated result | rel72 decision |
|---|---|---|
| Matcher | rel61 first real image 20/7 | Keep |
| Threshold | 7 | Keep; never lower |
| Same-press | rel59 | Keep |
| Between-pose MCU rearm | rel60 | Keep |
| Safe GET_IMAGE retry | rel48 | Keep exact rule |
| Warm TTL | rel50/60, 5 min | Keep |
| Indefinite warm | rel51 | Reject |
| Fast-resume in-place | rel62–64, 2–4/7 or 3–4/7 | Reject |
| PAM resume | rel61 | Keep |
| Stale PAM fail-delay optimization | rel62 | Keep |
| Windows 0x60 sleep | rel66 | Keep only at true S3 preparation |
| 0x60 on normal Close | rel68/69, normal scores 4/7,3/7,3/7 | Reject |
| stop fprintd before S3 | rel70/71 | Reject |
| fprintd open-before-suspend | rel72 | New candidate |

## rel72 hypothesis

The missing state transition is not a new matcher or a new TLS algorithm. It is:

`idle/closed fprintd -> real PrepareForSleep -> device must be open -> driver sends Windows 0x60/01 00 ACK -> transport is discarded -> S3 -> fresh post-resume Claim/Open`

This preserves the rel61 normal path while reproducing the hardware condition associated with the successful rel66 S3 test.

## Verification

- Full `fingerprint/research` test suite: PASS.
- rel72 source-safety tests: PASS.
- libfprint v1.94.100 build: PASS; no sensor I/O/GPIO/MMIO/firmware action during build.
- `libfprint-goodix51a0 1.94.100.goodix51a0-72` package built.
- `fprintd 1.94.5-72` custom package built from signed upstream source plus rel72 patch.
- Clean-path fprintd test suite: 35/36 PASS. One daemon test is unavailable because the build environment lacks the `gi.repository.FPrint` introspection namespace; all PAM tests pass on the clean path.
- The first fprintd test run from the canonical workspace failed PAM tests because `pam_wrapper` interpreted the workspace path containing spaces as a truncated module path. Re-running from `/tmp` removed that environmental false failure.

## Candidate package hashes

`fprintd-1.94.5-72-x86_64.pkg.tar.zst`
SHA256: `9f45604f88d28aaf014ff85940f783411a83d8c8ed635e6ba1b19ab6ed4321e0`

`libfprint-goodix51a0-1.94.100.goodix51a0-72-x86_64.pkg.tar.zst`
SHA256: `7adc8c66389a76c87c35960ede04f0adaf1108745d7ac1c0714554cea3fc5c01`

## Status

rel72 is a candidate only. It has not been installed on Pegasus and has not been human S3-tested.
