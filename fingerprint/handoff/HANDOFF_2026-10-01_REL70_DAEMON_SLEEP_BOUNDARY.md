# HANDOFF — rel70 daemon sleep boundary

Date: 2026-10-01
Machine: Pegasus only
Base: exact rel66 source baseline c149ac5
Package: libfprint-goodix51a0 1.94.100.goodix51a0-70

## Root cause after the second rel66 S3 failure

The rel66 driver source itself was unchanged and the Windows 0x60 sleep path was confirmed.
The failure was a lifecycle boundary problem: a long-lived fprintd process was reused across S3.
The boot-prewarm service is NOT a per-S3 boundary; enabling it cannot replace stopping fprintd before every sleep.
The failed 00:53:59 S3 had the same rel66 driver but the daemon survived the suspend/resume cycle.
Post-resume capture then showed repeated GET_IMAGE/TLS misses and scores only 3–4/7.

## Reconstruction

Keep the exact rel66 driver; add one systemd sleep.target boundary around fprintd:
- Before sleep.target: stop fprintd.service.
- Because rel66 Close sends Windows SLEEP 0x60/01 00 and requires ACK, this guarantees the validated device Close boundary before S3.
- After sleep.target is released on resume: start a fresh fprintd.service process.
- The fresh process performs a new libfprint probe/open lifecycle instead of carrying any stale action/session state across S3.
- No kernel parameter, runtime-PM force-on, GPIO policy, firmware action, matcher threshold, or enrollment changed.

## External research

- systemd.special(7) explicitly documents sleep.target as the hook point for commands before/after system sleep; combined oneshot units use Before=sleep.target, StopWhenUnneeded=yes and RemainAfterExit=yes with ExecStart/ExecStop.
- CachyOS Forum, Aug 2026: an exact fprintd suspend/resume workaround uses this same pattern, stopping fprintd before sleep and starting it after resume, for KDE/CachyOS fingerprint wake races.
- Additional 2026 community reports independently use the same daemon restart strategy for fingerprint devices after suspend.

## rel70 implementation

New: fingerprint/integration/systemd/gxfp51a0-fprintd-suspend.service
Installed by PKGBUILD and enabled by libfprint-goodix51a0.install.
Boot-prewarm remains enabled for boot readiness; it is no longer treated as the S3 mechanism.
Source safety test now gates the service wiring and the rel66 Windows sleep implementation.

## Verification

- git diff --check: PASS
- test_sleep_lifecycle_source_safety.sh: PASS
- systemd-analyze verify: PASS
- reproducible libfprint v1.94.100 build: PASS
- all artifact gates: PASS
- installed package: 1.94.100.goodix51a0-70
- installed fprintd: 1.94.5-2.1
- rel70 package SHA256: af756911bb1f4f209df65f818b99c8cf9b9a73adf5918ecf03f872d81d86ed6a
- installed libfprint SHA256: ca4f987310656c4e96733132fccfbe0ea0410b9ec8e1d2295b3a42df00fe7410
- sleep hook enabled: yes
- boot-prewarm enabled: yes
- fprintd active after installation: yes
- no reboot
- no re-enrollment

## Human gate

Do one manual deep S3 on this installed rel70.
Do not reboot and do not re-enroll.
After resume, use the existing enrolled finger normally.
Expected decisive log sequence:
1. gxfp51a0-fprintd-suspend service starts before sleep
2. fprintd stops
3. REL66_TRACE Windows deactivate SLEEP 0x60/01 00 acknowledged
4. PM suspend entry/exit
5. sleep hook stops / ExecStop starts fprintd after resume
6. new fprintd PID/probe
7. READY -> DETECTED_HOLD -> usable image >=7
8. fingerprint unlock.
Read the complete log before any further code change.
