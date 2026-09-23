# GXFP51A0 rel34 — fresh validated warm handoff

Date: 2026-09-23
Branch: fingerprint-rel34-fresh-warm-handoff

## Trigger

rel33 added a boot prewarm and proved correct systemd ordering:
fprintd -> gxfp51a0-boot-prewarm -> Plasma Login Manager.

Human rel33 cold-boot test still failed:
- boot-prewarm completed: 11:27:12 CEST
- Plasma Login Manager started after prewarm
- PAM fingerprint started: 11:27:16
- fingerprint prompt: 11:27:17
- GET_IMAGE retry: 11:27:23
- PLM fingerprint recognition failure: 11:27:24

The remaining issue was not daemon readiness. Source review showed that the
first post-prewarm gx_dev_open still ran rel31 full warm validation. That
validation performs a background GET_IMAGE even when the prior Claim finished
only seconds earlier. The user can already have a finger on the reader during
that redundant validation.

## rel34 design

New driver state:
- warm_handoff_ready
- GX_WARM_HANDOFF_TTL_US = 10 seconds

Rules:
1. A healthy gx_dev_close that stashes a complete warm TLS/background/FDT
   context arms one fresh handoff unless capture recovery is pending.
2. gx_dev_open consumes the token exactly once.
3. If the token age is <=10 seconds and no sleep/idle/recovery boundary exists,
   the already validated context is reused without another background GET_IMAGE.
4. If the token is missing or expired, rel31 full warm validation remains
   mandatory.
5. gx_warm_abandon and driver initialization clear the token.
6. Sleep/idle/recovery handling still occurs before handoff reuse, so rel34 does
   not bypass stale-state protections.

The matcher, threshold 7, template v4, enrollment files, KDE rel32 integration,
rel33 boot-prewarm, resume-prewarm and keepalive are unchanged.

## Validation

Source:
- test_fresh_warm_handoff_source_safety: PASS
- test_lifecycle_recovery_source_safety: PASS
- test_boot_prewarm_source_safety: PASS
- full verify-software-baseline.sh: PASS
- SOURCE_MANIFEST: PASS
- reproducible libfprint 1.94.100 build: PASS
- ACTIVE_SENSOR_IO=NONE during software baseline
- GPIO_WRITES=NONE
- MMIO_WRITES=NONE
- FIRMWARE_ACTIONS=NONE

Runtime proof without a human finger:
1. temporary G_MESSAGES_DEBUG=all drop-in under /run only;
2. warm keepalive stopped;
3. fprintd restarted to force a cold context;
4. gxfp51a0-boot-prewarm completed;
5. immediate fprintd-verify launched and timed out before any finger press.

Observed logs:
- stashed native warm context across fp_device close with fresh one-shot handoff
- consuming fresh warm handoff at 88 ms; skipping redundant background GET_IMAGE
- reusing freshly validated native warm context
- reusing capture context prepared during device open
- FP_FINGER_STATUS_NEEDED
- wait-on polling immediately
- no GET_IMAGE in that fresh-handoff interval

Expiry proof:
- waited >10 seconds after the next stashed handoff;
- next keepalive Claim did not use fast handoff;
- log: GXFP51A0 warm context image-validated in 1177 ms;
- therefore rel31 full FDT + encrypted GET_IMAGE validation is preserved for
  older contexts.

Cleanup after runtime proof:
- temporary /run debug drop-in removed;
- fprintd restarted with no debug environment;
- boot-prewarm rerun successfully;
- keepalive timer restored active;
- no fprintd-verify process left running.

## Next human test

After final repo/kit cleanup:
1. reboot Pegasus manually;
2. wait for the first Plasma Login Manager screen;
3. do not use mouse or keyboard;
4. place the freshly enrolled right index immediately, without waiting for a
   visible fingerprint prompt;
5. report one-press success or failure.

If it still fails, inspect the exact rel34 boot journal before changing any
matcher or timing values.

Never reboot Pegasus automatically.
