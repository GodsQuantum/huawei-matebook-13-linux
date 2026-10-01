# HANDOFF — GXFP51A0 / GF3658 ST411 — rel72 installation + S3 gate

Date: 2026-10-01
Machine: Pegasus only
RDC device: 8a6eeb21-0158-4e6d-b3ea-91d580f8a223
Workspace: /home/arezki/Projets/Workstations/Capteur Empreinte Huawei/
Repo: /home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/
GitHub: GodsQuantum/huawei-matebook-13-linux

## 1. EXACT STATE NOW

Current branch:
fingerprint-rel72-s3-hardware-park

HEAD:
547b75b — fix(fingerprint): rel72 hardware park before S3

Origin is synchronized and the worktree was clean at handoff creation.

LIVE Pegasus:
- libfprint-goodix51a0 1.94.100.goodix51a0-71
- fprintd 1.94.5-2.1
- 3 enrollments intact: right-index, left-index, right-middle
- fprintd active
- rel72 is NOT installed
- no reboot was performed

Important: rel72 package artifacts were cleaned from the repo after the build.
Recorded candidate SHA256 values remain authoritative; rebuild exact packages if
the .pkg.tar.zst files are not available.

Rel72 candidate hashes:
- fprintd-1.94.5-72-x86_64.pkg.tar.zst
  9f45604f88d28aaf014ff85940f783411a83d8c8ed635e6ba1b19ab6ed4321e0
- libfprint-goodix51a0-1.94.100.goodix51a0-72-x86_64.pkg.tar.zst
  7adc8c66389a76c87c35960ede04f0adaf1108745d7ac1c0714554cea3fc5c01

## 2. WHAT A GOOD DRIVER NOW MEANS

Hardware/transport facts already established:
- sensor: Goodix GXFP51A0 / GF3658 ST411
- chip ID: 0x2504 / ChicagoHS
- geometry: 80x64
- MCU firmware: GF_ST411SEC_APP_14115
- SPI mode 0, 8-bit, target max 10 MHz
- reset: GPIO264 logical line / pin189 pad, active-HIGH reset
- validated reset pulse: HIGH 300 ms -> LOW 600 ms
- IRQ: GPIO48
- normal runtime reset level: LOW
- Linux first-contact required SPI_CS_HIGH despite Windows/ACPI declaring active-low

Protocol facts:
- Milan SPI framing is target-specific and already implemented.
- writes use a separate 4-byte transport header then payload, with the required
  inter-transaction gap.
- inner commands use the Goodix Milan checksum/message format.
- TLS is TLS-PSK; no firmware flashing is required on this unit.
- accepted GET_IMAGE timeout must NEVER be blindly replayed after ACK/TLS evidence.

Biometric path that is already proven:
- SIGFM v3 / GQ-SIGFM matcher
- template v4
- production threshold = 7; DO NOT LOWER
- 20 enrollment views
- up to 3 images for the same physical press
- up to 3 physical poses
- images are scored independently; never merge scores
- rel59 retry-assisted capture pacing is retained
- rel60 MCU rearm after a usable-but-under-threshold pose is retained
- fresh background/FDT is required after a true cold lifecycle boundary
- a finger touching during calibration must invalidate/contaminate the background;
  it is not a matcher failure

Lifecycle rules:
- warm state may live for 5 minutes; indefinite warm was refuted
- no periodic heartbeat/keepalive
- no persistent timing-learning file
- no aggressive QML auth start
- no external system-sleep fingerprint hook in the final architecture
- password authentication remains immediately available in parallel
- rel61 KScreenLocker PAM resume restart is the proven KDE-side fix
- fprintd uses --no-timeout to preserve healthy warm state

## 3. HUMANALLY PROVEN BASELINE

rel48:
- cold login 23/7
- deep S3 11/7
- safe accepted-GET_IMAGE timeout rule validated

rel50:
- normal lock PASS
- same-press rescue validated

rel59:
- normal lock PASS, observed 5 -> 6 -> 7
- retry-assisted pacing was necessary and useful

rel60:
- normal lock PASS
- first real pose reached 9/7

rel61:
- deep S3 PASS
- KScreenLocker actually restarted the stale fingerprint PAM worker
- first genuine post-READY image scored 20/7
- touches before READY were correctly identified as calibration/background contamination
- remaining defect: resume -> READY was about 21.5 s

This proves that matcher, templates, threshold and normal capture quality are not
the current problem.

## 4. WHY REL62-71 WERE NOT THE FINAL ANSWER

rel62-64:
- tried to accelerate resume with in-place reconstruction
- could become pathological, with long TLS retry chains and/or 2-4/7 captures
- rejected as the final lifecycle architecture

rel66:
- provided important forensic evidence: a correctly parked sensor before S3 could
  survive the following deep sleep much better
- Windows-compatible SLEEP 0x60 / payload 01 00 is the relevant hardware park action

rel68-69:
- proved that sending SLEEP 0x60 during ordinary Close is BAD on this ST411
- observed weak normal captures around 4/7, 3/7, 3/7
- therefore 0x60 must NOT be used as a normal warm optimization

rel70-71:
- stopped fprintd before S3
- this removed the live libfprint suspend callback, so the sensor could not be
  parked through the validated driver lifecycle
- rel71 remained the live rollback baseline, but its S3 architecture is rejected

## 5. REL72 ARCHITECTURE

Rel72 keeps the proven rel60/61 biometric core.

The only new hardware lifecycle action is:
SLEEP command 0x60, payload 01 00, ACK required,
executed ONLY inside the real libfprint suspend callback.

Problem: fprintd normally has a closed/idle FpDevice, so libfprint's suspend
callback would otherwise not run.

Solution in custom fprintd 1.94.5-72:
1. receive logind PrepareForSleep(true)
2. if the exact driver name is goodix51a0 and the device is closed:
   open it temporarily
3. libfprint reaches gx_dev_suspend while transport is live
4. driver sends Windows-compatible 0x60/01 00 and requires ACK
5. driver closes stale TLS/transport state and marks the next Claim/Open cold
6. S3 occurs
7. on resume fprintd completes libfprint resume
8. fprintd closes the temporary sleep-opened device
9. rel61 KScreenLocker starts a fresh fingerprint PAM transaction
10. next Claim/Open performs a clean cold preparation
11. fresh background/FDT and TLS are built only after the real lifecycle boundary
12. first genuine finger is then captured and scored normally

The fprintd patch is restricted to driver name goodix51a0. Other fingerprint
devices retain native fprintd suspend behavior.

Normal gx_dev_close NEVER sends 0x60.

## 6. EXTERNAL RESEARCH CROSS-CHECK — 2026-10-01

Target-specific:
- GodsQuantum/huawei-matebook-13-linux: strongest target-specific runtime history
- szlukabence/goodix-fingerprint-spi-linux: ST411 protocol/transport/FDT reference
- tlambertz/goodix-fingerprint-reversing: Windows reverse engineering confirms
  FpMcuSwitchToSleepMode -> command 0x60 payload 01 00 with ACK before power transition

Sibling Goodix/TLS:
- Sigfrodr/libfprint-goodixtls: repeated TLS/session setup can make a Goodix MCU
  go silent while SPI transport remains healthy; cached sessions and explicit,
  bounded lifecycle recovery are preferable to unnecessary repeated handshakes
- berkekbgz/libfprint-goodix-spi: confirms lifecycle-sensitive background/FDT and
  SPI timing patterns; not copied blindly
- lexakimov/goodix51c0_spi-reversing: family-level protocol comparison only
- Rockytkg/goodix-linux-27c6-5125: family-level TLS/FDT/matcher comparison only
- PeshalaDilshan/OpenGoodixSPI: family-level SPI recovery comparison only

Important recent external finding:
GodsQuantum issue #6 / szlukabence testing showed that on another GXFP51A0,
deep S3 power loss is the upstream cause of the post-resume degradation; s2idle
kept the sensor rail alive and removed the failure. That is diagnostic evidence,
not a recommendation to switch Pegasus to s2idle.

The latest public ST411 repository still identifies the native rel23 driver as
the working Linux path and keeps GXFP51A0 protocol/research separate from sibling
drivers. No newer target-specific S3 fix superseded rel72 during this refresh.

## 7. SOFTWARE VALIDATION REL72

Already PASS before this handoff:
- full fingerprint/research test suite
- rel72 source-safety test
- libfprint v1.94.100 build
- fprintd 1.94.5-72 build
- package/source manifest gates
- no sensor I/O, GPIO writes, MMIO writes or firmware actions during build
- clean-path fprintd tests: 35/36 PASS
- only missing test is the upstream daemon test requiring gi.repository.FPrint,
  unavailable in this build environment
- PAM tests pass on the clean path
- canonical workspace PAM test false-failed only because pam_wrapper truncated the
  workspace path containing spaces; rerun from /tmp passed
- git diff --check / source safety passed
- repository was clean after rel72 work

The rel72 research record is:
fingerprint/research/REL72_WEB_GITHUB_RESEARCH_2026-10-01.md

## 8. INSTALL GATE — NEXT SESSION

Do NOT automatically reboot, suspend, lock, poweroff or touch the sensor.

First, verify:
- current branch/HEAD
- live package versions
- old rel71 sleep service state
- candidate package availability or rebuild requirements
- enrollments intact

If package artifacts are absent:
- rebuild exact rel72 libfprint package from the current branch
- rebuild exact fprintd-1.94.5-72 package from the checked-in PKGBUILD/patch
- verify hashes against the recorded candidate hashes
- if a hash differs, STOP and investigate before installation

Before installation, preserve the live rel71 state and capture its package versions.
Install rel72 only after source/package verification.

Rel72 installation must:
- install libfprint-goodix51a0-72
- install fprintd-1.94.5-72
- remove/disable the obsolete rel71 gxfp51a0-fprintd-suspend.service
- ensure no old system-sleep stop/start hook remains
- restart fprintd only when needed to load the new libraries
- do NOT reboot for the first runtime gate

## 9. FIRST HUMAN GATE

After installation:
1. perform ONE normal lock/unlock first
2. inspect logs before changing anything
3. only if normal lock works, perform ONE user-triggered deep S3
4. after resume, touch only when the fingerprint UI/READY state is actually ready
5. inspect the complete lifecycle before deciding success/failure

Expected S3 sequence:
PrepareForSleep
-> fprintd temporary Open
-> rel72 S3_PARK
-> SLEEP 0x60/01 00 ACK
-> transport/session close
-> deep S3
-> resume
-> libfprint resume
-> temporary Close
-> KScreenLocker rel61 PAM restart
-> fresh Claim/Open
-> clean cold preparation
-> READY
-> genuine DETECTED_HOLD
-> score >=7
-> unlock

## 10. EXACT DIAGNOSTIC DATA TO COLLECT AFTER S3

Use journal timestamps to measure:
- PM suspend entry/exit
- PrepareForSleep(true/false)
- fprintd temporary Open
- S3_PARK
- SLEEP ACK
- transport close
- KScreen resume hook
- stale fail-delay skip, if any
- fresh Claim/Open
- TLS attempts/failures
- cold preparation start/end
- READY
- DETECTED_HOLD
- same-press image scores
- MCU rearm, if any
- final PAM/UI unlock result

Do not count touches before READY as biometric rejections.

## 11. FAILURE DECISION TREE

A. No S3_PARK / fprintd never opens the device:
=> fprintd rel72 lifecycle patch is not reaching the Goodix driver.
Do not touch matcher, thresholds or templates.

B. fprintd opens, but S3_PARK is absent:
=> libfprint suspend callback/driver lifecycle issue.
Inspect suspend callback entry and device-open state.

C. S3_PARK exists but 0x60 has no ACK:
=> transport/sensor-state problem.
Inspect SPI/IRQ/transport/reset evidence before any architecture change.

D. 0x60 ACK succeeds, but resume never reaches fresh Claim/Open:
=> fprintd/KScreen/PAM lifecycle issue.
Do not modify biometric matching.

E. Fresh Claim/Open starts but TLS/prepare fails:
=> transport/session/cold-preparation problem.
Compare retry counts and recovery markers with rel61/rel62.
Do not add unbounded retries.

F. READY arrives but genuine images are 2-4/7:
=> capture/background/timing problem.
Check background contamination, FDT, capture pacing and same-press retries.
Do NOT re-enroll and do NOT lower threshold.

G. READY + genuine score >=7 but unlock fails:
=> PAM/UI/result propagation problem.
Inspect KScreenLocker/PAM and password parallelism.

H. Normal lock fails immediately after rel72 installation:
=> stop S3 testing.
Preserve logs, package integrity and live state; rebuild/restore the rel71
baseline only after evidence is recorded.

## 12. IF REL72 PASSES

Do not immediately declare final release after one lucky S3.

First:
- record exact resume->READY and resume->first-image times
- record score and number of real physical poses
- verify password remains immediately usable in parallel
- verify no background contamination was accepted
- run the full software/source-safety suite again
- package integrity check
- failed-unit check
- orphan-package check
- clean build/package/temp residues
- commit the human validation
- push branch and update handoff/current prompt

Then, with no automatic reboot:
- one second user-triggered deep S3 for repeatability
- only after repeatability, evaluate the next natural reboot/login gate
- decide whether boot-prewarm should remain disabled, be removed, or be reworked
  based on measured login latency, not assumption

## 13. IF REL72 FAILS

Do not improvise another sleep command.

Preserve:
- exact logs
- timestamps
- scores
- package versions
- Git commit
- service state

Classify the failure using section 11.

Then compare against:
- rel61: known S3 PASS, ~21.5 s to READY, 20/7
- rel62: ~5 s cold preparation in a non-S3 measurement
- rel71: live baseline, S3 architecture rejected because fprintd was stopped
- rel66: hardware-park evidence

Only then choose the smallest next change.

## 14. ABSOLUTELY DO NOT REINTRODUCE

- threshold <7
- re-enrollment as a diagnostic shortcut
- same-press cutoff <=4
- indefinite warm context
- stale pre-S3 background bootstrap
- SLEEP 0x60 during ordinary Close
- periodic heartbeat/keepalive
- aggressive QML Component.onCompleted auth
- external system-sleep fingerprint hooks
- accepted GET_IMAGE replay after ACK/TLS evidence
- persistent timing-learning files
- GPIO112/GPP_D16
- unproven LPSS/pxa2xx power-control changes
- old 10/100 ms reset timing
- rel62-64 aggressive in-place fast-resume architecture
- automatic reboot/suspend/lock/poweroff

Validated reset remains:
GPIO264 HIGH 300 ms -> LOW 600 ms.

## 15. RESTART COMMANDS / LOG FILTERS

Before installation, use the existing repo/build procedures; do not invent a new
installer until the checked-in PKGBUILD and current scripts have been inspected.

After the physical S3, inspect at minimum:
journalctl -b --since '-15 min' --no-pager -o short-precise

Filter terms:
PM: suspend entry
PM: suspend exit
PrepareForSleep
rel72
S3_PARK
SLEEP
opened Goodix GXFP51A0
closing Goodix GXFP51A0
Resume: rearming fingerprint PAM
stale fail-delay
Restarting PAM authenticator
fprintd
GXFP51A0
TLS
cold preparation
READY
DETECTED_HOLD
same-press image
score=
MCU rearmed
Authentication race
LoginCancelled

Then:
journalctl -b -u fprintd.service --since '-15 min' --no-pager -o short-precise

## 15A. CANONICAL REL72 REBUILD RECOVERY — 2026-10-01

Before the first live rel72 installation, the previously cleaned package artifacts
were reconstructed from the checked-in recipes and compared against the hashes
recorded in this handoff. No runtime package was installed during this recovery.

The raw Arch package hash is sensitive to makepkg's SOURCE_DATE_EPOCH and to the
installed-package inventory recorded in .BUILDINFO. The timestamps printed by
makepkg are one second later than the SOURCE_DATE_EPOCH captured at process
initialization in these two historical builds.

Exact canonical reconstruction:

- libfprint-goodix51a0 1.94.100.goodix51a0-72
  - canonical SOURCE_DATE_EPOCH: 1790840963 = 2026-10-01 09:49:23 +0200
  - the historical build occurred before fprintd makedepends were installed;
    .BUILDINFO therefore contains 1540 installed packages
  - the nine later packages absent from that inventory are:
    glib2-docs, gtk-doc, meson, ninja, pam_wrapper, python-dbusmock,
    python-lxml, python-pygments and python-tqdm
  - reconstructed SHA256:
    7adc8c66389a76c87c35960ede04f0adaf1108745d7ac1c0714554cea3fc5c01

- fprintd 1.94.5-72
  - canonical SOURCE_DATE_EPOCH: 1790841108 = 2026-10-01 09:51:48 +0200
  - all nine fprintd makedepends were already installed, matching the live
    package inventory used by the historical build
  - reconstructed SHA256:
    9f45604f88d28aaf014ff85940f783411a83d8c8ed635e6ba1b19ab6ed4321e0

Verification observations:
- libfprint source-safety test: PASS
- libfprint build gates: PASS
- ACTIVE_SENSOR_IO=NONE
- GPIO_WRITES=NONE
- MMIO_WRITES=NONE
- FIRMWARE_ACTIONS=NONE
- repackaging at the same epoch reproduces the same package hash bit-for-bit
- fprintd upstream signing key fingerprint verified:
  D4C501DA48EB797A081750939449C2F50996635F
- exact canonical copies staged only in /tmp/gxfp51a0-rel72-install for the
  installation gate; generated repo build trees were removed afterward
- live runtime at this point remains rel71 + fprintd 1.94.5-2.1; enrollments
  remain untouched

## 16. DOCUMENTATION / SYNC REQUIREMENT

Every meaningful test result, conclusion, package hash and decision must be
recorded in the repo before ending the session.

Canonical rel72 files:
- fingerprint/handoff/HANDOFF_2026-10-01_REL72_S3_HARDWARE_PARK.md
- fingerprint/research/REL72_WEB_GITHUB_RESEARCH_2026-10-01.md
- fingerprint/handoff/PROMPT_2026-10-01_REL72_INSTALL_CONTINUE.md

After each completed stage:
- update the handoff
- commit
- push origin
- keep worktree clean
- clean temporary build/package/log residues
- never expose PMK/PSK, raw fingerprint captures, templates or serials

The next session must start from this handoff and must not redo the historical
investigation unless a new result contradicts an established conclusion.

[executed on device: Pegasus (8a6eeb21-0158-4e6d-b3ea-91d580f8a223)]