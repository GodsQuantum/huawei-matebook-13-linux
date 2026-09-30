# HANDOFF — rel66 baseline restored after rel69 S3 regression

Date: 2026-10-01
Machine: Pegasus only
Source baseline: c149ac5
Live package: libfprint-goodix51a0 1.94.100.goodix51a0-66

## Finding

rel69 failed S3 because it removed the validated Windows deactivate-sleep boundary.

Observed rel69 failure:
- S3 entered 00:19:06.917 and exited 00:19:21.769.
- No GXFP51A0 S3_CLEAN suspend/resume callback trace appeared.
- Post-resume fprintd stayed in the same process/session.
- Authentication entered with WakeupMCU and produced scores 0–4/7.
- The session repeatedly hit GET_IMAGE/TLS misses and 300% capture pacing.
- Therefore rel69 did not establish the required fresh cold boundary before biometric capture.

This is consistent with the libfprint API: suspend/resume callbacks are tied to the device's interactive lifecycle; they cannot be the sole boundary mechanism when the device is already idle/closed. citeturn2search0turn2search1

## Correct baseline

rel66 is restored exactly from c149ac5:
- normal Close sends Windows 0x60 payload 01 00 and requires ACK;
- warm context is stashed only after successful sleep;
- next normal Open wakes the MCU and validates warm state;
- a real S3 is detected by the BOOTTIME/MONOTONIC sleep epoch;
- stale warm state is abandoned;
- GPIO reset + full cold preparation occurs before post-S3 authentication;
- threshold 7 and all enrolled templates remain unchanged;
- no keepalive, heartbeat, system-sleep hook, runtime-PM force-on, or re-enrollment.

## Live state

- rel66 package installed.
- fprintd active.
- gxfp51a0-boot-prewarm disabled and inactive.
- no process holds /dev/spidev1.0.
- no reboot performed.
- enrollment untouched.

## Validation

Exact rel66 source rebuilt successfully.
Research suite PASS.
Boot binding PASS.
Full Meson/Ninja build PASS.
Artifact gates PASS.

## Human gate

Perform one deep S3 test on this exact rel66 baseline.
Expected gate:
- fresh cold Open after resume;
- READY around the validated ~4.434 s range;
- first usable biometric image >=7/7;
- fingerprint unlock succeeds.

Do not modify the driver before reading the complete post-resume logs.
