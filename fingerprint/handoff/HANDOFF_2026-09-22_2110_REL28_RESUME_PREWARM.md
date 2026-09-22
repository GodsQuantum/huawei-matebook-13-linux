# Handoff — rel28 post-resume prewarm / reversible pacing

Updated: 2026-09-22 21:10 CEST.

## New external evidence incorporated

Issue #6 received two new reports from szlukabence after rel27 was built.

Comment 5781765140 showed that rel24 pacing was a one-way persisted ratchet:
each deep-resume session loss could step capture pacing 100 -> 150 -> 200 even
though capture gap cannot prevent a power-loss session reset. It also showed a
second UX failure: rebuilding background/FDT on the user's first post-resume
Claim can calibrate with the finger already on the sensor.

Comment 5781990416 provided the clean control: switching the 2020 machine from
deep S3 to s2idle makes all post-resume failures disappear with the same driver
and enrollments. This isolates the root event to fingerprint-rail power loss in
deep S3. s2idle is diagnostic evidence, not a general fix because of its power
cost on that CometLake platform.
GitHub references:
- https://github.com/GodsQuantum/huawei-matebook-13-linux/issues/6#issuecomment-5781765140
- https://github.com/GodsQuantum/huawei-matebook-13-linux/issues/6#issuecomment-5781990416

## rel28 architecture

Branch: fingerprint-rel28-resume-prewarm

rel27 Claim-time sleep detection remains as a defensive fallback. rel28 adds a
package-owned post-resume prewarm path that does NOT restart fprintd.

The sleep hook is pulled by sleep.target and ordered Before=sleep.target.
Before sleep it becomes active. When sleep.target is stopped after wake,
ExecStop immediately schedules a separate worker with:
  systemctl --no-block start gxfp51a0-resume-prewarm-worker.service

The hook itself therefore does not wait for sensor recovery. A simulated
start/stop returned in 99 ms even while the worker subsequently spent about
15 s rebuilding the currently degraded reference sensor.
The worker runs /usr/libexec/gxfp51a0-resume-prewarm. The helper:
- exits on non-GXFP51A0 machines;
- requires the standard fprintd service to be active;
- gets the default device through the standard fprintd D-Bus Manager API;
- performs only Device.Claim("");
- performs no VerifyStart, EnrollStart or template lookup;
- never restarts fprintd;
- releases automatically when busctl exits;
- has a bounded 45 s client timeout; the worker has TimeoutStartSec=50s.

A successful Claim executes the normal libfprint open/close lifecycle and
leaves the validated TLS/background/FDT context stashed for the lock screen.

The helper was tested directly and through the final async worker. The final
worker completed successfully and logged:
  post-resume fprintd Claim completed; sensor context prewarmed
## Pacing changes

rel28 distinguishes steady-state transport evidence from lifecycle loss.

New state:
- capture_retry_seen
- capture_clean_streak
- capture_pacing_suppressed

Rules:
- GET_IMAGE/TLS retries mark the current frame non-clean.
- A lifecycle/S3 rebuild suppresses pacing escalation; a session destroyed by
  power loss is not evidence that the 30 ms capture gap is too short.
- Normal non-lifecycle exhausted transport loss may still step pacing upward by
  50%, capped at 300%.
- Upward values are still persisted only after a complete successful finger
  capture.
- An elevated value decays by 50% only after 16 consecutive complete finger
  captures with no GET_IMAGE/TLS retry, then the lower value is persisted.
- The 2020 unit's reported ~93% first-attempt failure rate should therefore
  prevent inappropriate decay there, while a stable faster unit can recover
  from an old elevated value.
Biometric policy is unchanged:
- template v4 / SIGFM v3;
- threshold 7;
- 20 enrollment views;
- at most three verify presses;
- no firmware flashing;
- no GPIO112 / GPP_D16 access.

Existing enrollments remain compatible and must not be deleted for this issue.

## Validation completed

Targeted lifecycle/pacing/resume tests PASS.
systemd-analyze verify passes for both resume units.
Portable install-linux.sh syntax and rollback manifest tests PASS.
Complete software baseline PASS against libfprint v1.94.100:
- research/unit/source-safety suite;
- source manifest;
- reproducible libfprint build;
- no active sensor I/O/GPIO/MMIO/firmware action during software gate.
Final package:
  libfprint-goodix51a0 1.94.100.goodix51a0-28

Final SHA-256:
  977ec07f877a35a81dfc67a2d3a738b8dd17647631c049f6df4e8ace848b91b0

Final package contains:
- /usr/libexec/gxfp51a0-resume-prewarm
- /usr/lib/systemd/system/gxfp51a0-resume-prewarm.service
- /usr/lib/systemd/system/gxfp51a0-resume-prewarm-worker.service
- /usr/lib/systemd/system/sleep.target.wants/gxfp51a0-resume-prewarm.service

The final package was reinstalled over the first rel28 prototype. The prototype
had directly run Claim in ExecStop and was rejected after a manual test proved
that a slow TLS rebuild could hit systemd's stop timeout. The installed final
design schedules the worker asynchronously and does not have this defect.
## Required next human validation

Do not re-enroll.

1. First validate normal lock/logout with the existing right-index template.
2. Then allow a real deep S3 suspend/resume.
3. On wake, try the enrolled right-index normally.
4. Immediately inspect:
   - gxfp51a0-resume-prewarm logs;
   - gxfp51a0-resume-prewarm-worker status;
   - fprintd journal around resume and first fingerprint.
5. Do not restart fprintd before collecting those logs.
6. For the strongest first-S3 proof later:
   manual reboot -> one successful fingerprint use -> first deep S3 -> wake ->
   fingerprint unlock.
7. The assistant must never reboot Pegasus itself.

Only consider re-enrollment if transport is healthy, a real fingerprint frame
reaches the matcher, and genuine old templates consistently score below
threshold. Nothing observed so far meets that condition.
