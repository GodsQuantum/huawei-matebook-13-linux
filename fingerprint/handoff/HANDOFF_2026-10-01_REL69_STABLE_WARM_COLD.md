# HANDOFF — rel69 stable warm/cold candidate

Machine: Pegasus only
Date: 2026-10-01
Branch: fingerprint-rel69-stable-warm-cold

## Decision

rel68 is rejected as a production design.

The exact failure observed after boot on rel68:
- boot 23:41:28
- automatic prewarm performed SLEEP 0x60
- first normal Claim woke the sleeping MCU and executed WARM_REBASE in ~1765 ms
- first press: score 4/7
- second press: score 3/7
- third image: score 3/7
- repeated GET_IMAGE ACK/TLS retries and FDT ACK retries.
This shows the MCU 0x60 sleep -> WakeupMCU -> warm-rebase path is not a reliable biometric path on this ST411, despite producing a valid SLEEP ACK.

Validated rel66 counterexample:
- deep S3 resume -> fresh cold boundary -> READY ~4.434 s
- first image score 7/7
- human unlock OK.
The rel61 biometric core also produced the historical 20/7 S3 result.

## rel69 architecture

rel69 restores the rel61-proven normal warm/cold driver lifecycle, while retaining the rel65 clean S3 suspend/resume handling:
- no MCU SLEEP 0x60 on normal libfprint close;
- valid production TLS/background/FDT context is stashed in RAM across fp_device close;
- next normal Claim validates the warm context;
- no WakeupMCU before warm validation;
- if warm validation fails, full GPIO cold reset + cold prepare;
- S3 is a hard boundary: parked action, warm state invalidated, resume completes first, then stale action cancelled, next Claim/Open performs cold initialization;
- automatic one-shot boot/upgrade prewarm remains enabled so the warm production context is initialized before the graphical login path;
- no periodic keepalive, no heartbeat, no system-sleep hook, no persistent timing file.

This is intentionally the combination of:
  rel61 normal warm/cold capture path
  + rel65 S3-clean parked-action lifecycle
  + rel68 automatic one-shot prewarm
with the rel66/67 0x60 normal-close experiment removed.

## Biometrics

Unchanged:
- GQ-SIGFM/template-v4
- threshold 7
- 3 existing enrollments
- no re-enrollment
- no score accumulation/fusion
- same preprocessing and matcher as the rel61 20/7 baseline.

## Software validation

PASS:
- full fingerprint research test suite
- boot binding
- lifecycle recovery
- native resume recovery
- dual auth
- KScreen/PAM integration
- warm handoff
- no external system-sleep hooks
- source manifest
- full Meson/Ninja build
- release artifact gates
- git diff --check.

Package:
libfprint-goodix51a0-1.94.100.goodix51a0-69-x86_64.pkg.tar.zst

Driver source SHA256:
7a12c63dd0dd33968700b5a878294c7a8a43affcbba55485e22ce0ff408085f2

## Live install

rel69 is installed on Pegasus:
libfprint-goodix51a0 1.94.100.goodix51a0-69
fprintd 1.94.5-2.1
kscreenlocker 6.7.5-1.5
plasma-login-manager 6.7.5-3.9

Package integrity:
39 files, 0 modified.

boot-prewarm:
enabled / inactive after one-shot.

At 00:10:35 boot-prewarm completed its Claim. No MCU SLEEP 0x60 trace is expected in rel69; the normal close path stashes warm state.

## Human gate

1. Normal fingerprint lock/unlock.
2. Inspect logs before any further code change.
3. If normal lock succeeds, perform deep S3.
4. S3 must preserve the rel66 gate: first usable image >=7 and unlock OK.
5. Only after both are validated may rel69 become the new baseline.

Next optimization target after validation:
- reduce warm-open latency below the current ~1.7 s WARM_REBASE where safely possible, without weakening background correctness or S3 recovery.
