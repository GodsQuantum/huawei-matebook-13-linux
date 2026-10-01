# HANDOFF — rel71: rel61 functional driver reconstruction

Date: 2026-10-01 09:02 CEST
Machine: Pegasus uniquement
Branch: `fingerprint-rel71-rel61-driver-reconstruction`

## Decisive finding from the rel70 S3 test

The user's deep-S3 cycle was real and is visible in the journal:
- suspend entered S3 at 01:11:22;
- `gxfp51a0-fprintd-suspend.service` started BEFORE S3;
- fprintd was actually stopped at 01:11:22.676;
- systemd entered `PM: suspend entry (deep)`;
- resume happened at 08:49:52;
- the sleep unit's ExecStop then started a fresh fprintd process;
- new fprintd PID was 44964.

Therefore the rel70 daemon boundary worked exactly as designed. It did NOT fix the fingerprint failure.

Post-resume failure was inside the rel66/70 driver path:
- repeated target ACK no-IRQ retries;
- protocol timing escalated 100% -> 300%;
- accepted GET_IMAGE followed by TLS image timeout;
- full session recovery;
- FDT retry;
- WakeupMCU;
- READY;
- no usable match.

This definitively removes the long-lived fprintd/PAM lifecycle as the remaining root cause.

## Why rel61 is the correct reconstruction base

The last human-validated successful S3 was rel61:
- resume: 01:26:39.755;
- READY: 01:27:01.260;
- first true DETECTED: 01:27:01.744;
- first true image: **20/7**;
- unlock: successful.

Rel62 introduced the fast-resume optimization and changed the cold/S3 lifecycle. Rel62–64 subsequently produced 3–4/7 despite increasingly elaborate reset/A8/epoch/reconditioning logic. Rel66 then introduced the Windows deactivate `0x60/01 00` path. Rel70 proved that adding a daemon boundary around rel66 still does not restore the rel61 image quality.

The driver tree from commit `0e8a50a` is therefore restored verbatim. That commit is the rel61 KScreenLocker commit, but its Goodix driver is the rel60 driver that produced the successful rel61 S3 result.

Important restored semantics:
- no `sensor_sleeping` state;
- no Windows deactivate `0x60` command in the driver;
- no `driverstate_attempted` once-per-daemon optimization;
- no FAST_RESUME reset+A8 pre-TLS path;
- no rel66 parked-action / sensor-sleep lifecycle;
- normal `gx_dev_open()` performs the validated cold path;
- `gx_cold_prepare()` runs the Windows DriverState Install on every true cold preparation;
- GPIO reset + firmware/A8 + TLS + fresh background/FDT remain the known-good sequence;
- threshold 7, rel59 pacing and rel60 WakeupMCU between failed poses remain unchanged.

## rel71 additions that are intentionally outside the driver

1. Exact rel61/rel60 Goodix driver restored.
2. `gxfp51a0-fprintd-suspend.service` retained as the userspace S3 daemon boundary.
3. Boot-prewarm remains installed but is now explicitly disabled, matching the rel61 functional baseline.
4. Existing KScreenLocker / plasma-login-manager live versions remain unchanged:
   - kscreenlocker 6.7.5-1.5
   - plasma-login-manager 6.7.5-3.9
5. No enrollment/template change.

The systemd sleep hook follows the current documented `sleep.target` pattern: pre-sleep `ExecStart` and post-resume `ExecStop` with `Type=oneshot`, `Before=sleep.target`, `StopWhenUnneeded=yes`, and `RemainAfterExit=yes`.

A current 2026 CachyOS discussion independently documents the same fprintd stop-before-sleep/start-after-resume pattern for KDE fingerprint wake failures.

## Build / validation

- `make -C fingerprint/research test`: PASS
- `git diff --check`: PASS
- reproducible libfprint v1.94.100 build: PASS
- artifact gates: PASS
- package: `libfprint-goodix51a0 1.94.100.goodix51a0-71`
- package SHA256: `0b6ea6afd3966f453023b8aaaaee47ab119ec4b6b422af6da5cfb41cbc5d69f4`
- installed libfprint SHA256: `d7d4b1d7d56e33b1a2e8c33ada0fc11984229d2507c5ec797816d4b338d9c997`
- fprintd: `1.94.5-2.1`
- sleep boundary: enabled
- boot-prewarm: disabled
- fprintd: active
- no reboot
- no re-enrollment

## Human gate

Do exactly ONE manual deep S3 with the installed rel71.

Do not reboot and do not re-enroll.

After wake, use the already-enrolled finger normally.

The decisive pre/post sequence should be:
1. `gxfp51a0-fprintd-suspend.service` starts;
2. fprintd stops before S3;
3. PM enters deep S3;
4. resume;
5. sleep unit's ExecStop starts a fresh fprintd;
6. rel61 driver performs its normal cold `Open -> GPIO reset -> DriverState Install -> firmware/A8 -> TLS -> background/FDT` path;
7. READY;
8. first real DETECTED / image;
9. target is the rel61-quality path, ideally reproducing the known 20/7 first-image behavior.

If this fails, DO NOT patch blindly. Read the complete post-resume trace first and compare it directly with the stored rel61 successful trace before touching the driver again.
