[Reading 410 lines from start (total: 410 lines, 0 remaining)]

# Goodix GXFP51A0 / GF3658 ST411 on Linux

Native experimental libfprint driver for the SPI Goodix GXFP51A0 found in the
Huawei MateBook 13 2021 family.

> Français: [README.FR.md](README.FR.md) · 简体中文: [README.ZH-CN.md](README.ZH-CN.md)

## Status — 2026-09-24

Hardware-validated target:

- ACPI HID: `GXFP51A0`
- Goodix GF3658 / ST411, chip ID `0x2504`
- validated firmware: `GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`, 1 MHz
- GPIO48 readiness/IRQ and GPIO264 active-HIGH MCU reset
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- 80×64 active fingerprint image
- libfprint base: pinned `v1.94.100`

Production path:

```text
GXFP51A0 → libfprint → fprintd → desktop PAM / CLI
```

### Runtime-validated baseline: rel40

A real cold-boot graphical login on the MateBook 13 2021 reference unit succeeded
with the existing enrollment. Plasma Login Manager used libfprint `Identify`;
the first press produced scores `2/3/3`, and on the next press the first frame
failed the quality gate while the **second image from the same physical press
scored 7/7 and authenticated the session**.

rel40 therefore validates together:

- exact-target Windows `WakeupMCU`: raw SPI `0f 00 00 0e` + 5 ms;
- warm-context hardware validation and `WARM_REBASE`;
- both `Verify` and multi-print `Identify`;
- up to 3 independent images from one physical press via `RetryCaptureIMG`;
- fixed matcher threshold **7**, with no score addition/fusion;
- up to 3 physical presses before terminal rejection;
- 20-view enrollment and existing template-v4/SIGFM-v3 compatibility;
- bounded transport recovery, boot prewarm and deep-sleep resume prewarm;
- no periodic synthetic Claim keepalive;
- no biometric dump writer in release builds.

### rel42 candidate: fast session-local adaptation + portable Linux install

rel42 preserves the runtime-validated rel40 biometric path unchanged. It removes
the rel24–rel40 persistent timing files because lifecycle/prewarm failures could
ratchet them upward across boots. Timing now always begins at the validated
nominal 100% after a fresh lifecycle and adapts **only in RAM**:

- a lifecycle/prewarm failure never changes capture pacing;
- 3 consecutive successful captures that needed the GET_IMAGE retry raise
  capture pacing by one 50-point step for the current daemon only;
- 8 clean captures decay one step toward nominal;
- a true biometric transport desync may raise the current-session pacing and
  requests the existing full session recovery;
- protocol/TLS timing may also loosen in-session, but nothing is persisted.

The rel42 software suite and reproducible libfprint build pass. rel42 has not yet
replaced the human runtime validation of rel40 until it receives its own cold
boot test.

## Install

Recommended from a source checkout:

```bash
./fingerprint/install-linux.sh
```

The installer detects Arch/CachyOS, Debian/Ubuntu, Fedora/RHEL-family,
openSUSE and Alpine. Arch/CachyOS delegates to the native pacman package.
On systemd distributions the reviewed `/usr/local` libfprint is exposed
**only to fprintd** through a service-local `LD_LIBRARY_PATH`. On non-systemd
systems the same isolation is provided by a higher-priority D-Bus activation
wrapper under `/etc/dbus-1/system-services`; there is no global `ld.so.conf`
replacement. Meson's actual `libdir` is detected dynamically (Debian multiarch,
`lib64`, plain `lib`) and the distribution's own fprintd ABI is validated
against the staged candidate before any system file is changed.

Useful modes:

```bash
./fingerprint/install-linux.sh --build-only
./fingerprint/install-linux.sh --no-install-deps
./fingerprint/install-linux.sh --no-desktop-integration
```

Rollback for the portable install:

```bash
sudo /var/lib/gxfp51a0-local-install/uninstall.sh
```

Arch/CachyOS can also call the native path directly:

```bash
./fingerprint/install-arch.sh
```

The installer never deletes enrollments or the validated PMK cache. Upgrading to
rel42 removes only the obsolete non-secret timing integers left by rel24–rel40.

For Plasma Login Manager 6.7.5, this repository also carries the validated
fingerprint/password preemption compatibility package: password and fingerprint
remain separate authentication paths, so entering a password does not wait for
a fingerprint timeout. Other desktops retain their native fprintd/PAM behavior.

## Historical evolution

### rel24-rc1: slow-transport compatibility candidate

The first confirmed MateBook 13 2020 ST411/14115 report showed that rel23 can authenticate correctly on that revision while a degraded transport state makes GET_IMAGE/FDT retries very slow. rel24-rc1 keeps the validated 30 ms capture gap as the default but learns a separate 100–300% capture-only pacing value after an exhausted GET_IMAGE transport failure. That value is deliberately independent from the existing TLS/init timing scale and is persisted only after a complete successful finger capture. Both `no ACK/TLS` and `ACK but no TLS image after retry` trigger a full MCU/session recovery; such transport failures do not consume a biometric verify attempt.

Enumeration prewarm is also kept soft and short: one outer probe attempt, at most two cached-PMK TLS tries, and no fresh-staging fallback. If that optimization fails, fprintd still becomes available and the normal biometric open path retains the full bounded recovery. rel24-rc1 keeps template v4, SIGFM v3, threshold 7, 20 enrollment views and at most three independent verification presses unchanged.

### rel25-rc1: Plasma Login integration candidate

rel25 keeps the rel24 transport behavior and fixes the graphical-login integration found during cold-boot validation on Plasma Login Manager 6.7.4. The fprintd drop-in now has `Before=display-manager.service`, so the reader is fully enumerated before the greeter starts. For Plasma Login Manager 6.7.4, `fingerprint/integration/plasma-login-manager-6.7-pam-messages/` provides a package-managed compatibility build containing KDE upstream commits `8f6c2d32` and `db5e466d`, which display PAM authentication information in the greeter and keep active prompts visible. The same package carries the `pam_fprintd` rule, avoiding local `/etc/pam.d` overrides. Existing enrollments remain compatible and are not touched.

### rel26 candidate: Claim-time preparation and lifecycle recovery

A MateBook 13 2021 cold-boot regression exposed a bad boundary in rel24/25: libfprint `probe()` performed TLS plus a background `GET_IMAGE` before any biometric client had claimed the device. If that opportunistic capture lost its TLS image, the MCU could already be desynchronised when the login greeter asked for the first fingerprint.

rel26 makes enumeration passive: `probe()` verifies only that the host SPI/GPIO transport can be opened and closed. Sensor reset, TLS, background capture and FDT calibration now belong to the real libfprint `open()`/Claim path, which uses the bounded whole-session recovery path and reports a protocol error instead of falsely completing `open()` after failed preparation.

The candidate also implements native libfprint suspend/resume callbacks and invalidates a retained warm context across sleep. Because an idle libfprint device may not receive a driver suspend callback, the next Claim also compares `CLOCK_BOOTTIME` with `CLOCK_MONOTONIC`; a detected sleep boundary forces a clean MCU reset before reuse.

Matcher policy is unchanged: template v4 / SIGFM v3, threshold 7, 20 enrollment views and at most three independent verification presses. Existing rel23/24/25 enrollments remain format-compatible; do not re-enroll merely because transport preparation failed.

### rel27 candidate: first-S3 detection fix

A real idle suspend/resume on the 2021 reference machine exposed a rel26 bug in the
Claim-time sleep detector. Before the first suspend of a boot,
`CLOCK_BOOTTIME - CLOCK_MONOTONIC` is legitimately zero or slightly negative
because the clocks are sampled sequentially. rel26 incorrectly treated
`<= 0` as an invalid baseline, so the first S3 could reuse stale TLS/FDT state.

rel27 tracks clock validity separately from the numeric delta, so a zero or
negative pre-suspend baseline remains valid. When the delta advances by more
than 250 ms, the next Claim abandons stale TLS host-side, discards unpersisted
capture-pacing escalation, resets the MCU and rebuilds the full context.

The active-action suspend path is also aligned with the upstream libfprint
contract: because ST411 cannot safely continue a capture across S3, the driver
returns `FP_DEVICE_ERROR_NOT_SUPPORTED` from suspend. libfprint then cancels
the active action before sleep; the next Claim performs a cold reset.

No matcher/template/enrollment parameters changed.

### rel28 candidate: post-resume prewarm and reversible pacing

Two additional MateBook 13 2020 controls closed the remaining resume ambiguity.
With `deep` S3 the fingerprint rail drops and the MCU session is lost; with
`s2idle` the same driver and enrollment resume normally because the rail stays
powered. The failure is therefore a power-state lifecycle problem, not an
enrollment or matcher defect.

rel28 retains rel27 Claim-time recovery as a fallback, but no longer waits for
the user's first fingerprint attempt to rebuild background/FDT after sleep.
A package-owned `sleep.target` hook schedules an asynchronous worker on resume.
The worker performs a brief standard fprintd `Claim("")`; opening the device
rebuilds TLS/background/FDT while the sensor should still be untouched, and the
D-Bus owner disappearing immediately releases the device while retaining the
validated warm context. It never restarts fprintd and the sleep hook does not
wait for the potentially slow rebuild.

Capture pacing is also no longer a one-way persisted ratchet:
- a lifecycle/S3 recovery desync is explicitly excluded from pacing learning;
- a GET_IMAGE retry never counts as a clean capture;
- after 16 consecutive complete no-retry captures, an elevated pacing value
  decays by one 50-point step and the lower value is persisted.

The default remains 100% / 30 ms, the cap remains 300%, and matcher/template
policy is unchanged.

### rel29 candidate: stale warm-session expiry

A successful reference-machine lock test showed that template-v4 enrollments from
earlier releases remain valid. A separate failure after several hours without
system sleep proved that a retained TLS/background/FDT context can become stale
even when no suspend boundary is crossed.

rel29 records the last validated sensor activity and treats a warm context idle
for more than five minutes as a lifecycle boundary. The next Claim abandons that
host-side state and performs the normal bounded cold rebuild before capture.
This does not change the matcher, templates, enrollment count or threshold.

### rel31 candidate: image-ready lock screen

rel31 keeps the rel29 five-minute safety expiry and the rel30 three-minute
Claim keepalive, but fixes the false-ready condition exposed by the first rel30
lock test. A retained context is no longer accepted merely because FDT answers:
the warm-validation path must also complete one encrypted background-mode
GET_IMAGE/TLS frame. That frame is discarded immediately and never reaches the
matcher or template store. If image validation fails, the stale TLS state is
abandoned host-side and the driver performs the normal reset/cold rebuild before
Verify is allowed to continue. Validation failure is explicitly excluded from
capture-pacing learning.

rel31 originally made the lock UI visible directly from
Component.onCompleted. Human testing exposed a QML race: on some launches
Window.window was still null, so stock onUiVisibleChanged threw from
requestActivate() before authenticator.startAuthenticating() could run. Because
uiVisible was already true, later mouse motion could not retrigger the handler.

### rel32 candidate: window-ready KDE authentication

rel32 keeps the rel31 driver and biometric behavior unchanged and fixes only the
KDE integration. A short startup Timer waits until lockScreenRoot.Window.window
exists before setting uiVisible=true. Stock Plasma then runs requestActivate()
and authenticator.startAuthenticating() in its normal order, without the rel31
null-window exception.

rel32 also backports KDE plasma-desktop commit e5616c6a (2026-08-18) narrowly:
while the lock UI is visible, a 1-second heartbeat calls
authenticator.startAuthenticating(). Current Plasma master uses the same pattern
to keep the authentication backend alive. The backport is skipped automatically
if a future distro package already contains the upstream heartbeat.

The integration remains one-file, conditional on KDE, package-managed,
idempotent and reversible. Its migration/rollback tests prove that removing the
integration restores Plasma 6.7.5 LockScreenUi.qml byte-for-byte.

The KDE integration is conditional; non-Plasma desktops keep their native
greeter/PAM behavior.

Human reference-machine validation on 2026-09-23 confirmed the intended rel32
lock UX: lock the session, immediately place the enrolled right index before any
prompt is visible, and unlock succeeds on the first press with no mouse or
keyboard interaction.

### rel33 candidate: cold-boot prewarm

The first rel32 cold-boot test showed that service ordering alone was not
sufficient. On the reference machine fprintd became active at 10:27:45 CEST and
Plasma Login Manager at 10:27:49, but the first PAM fingerprint attempt at
10:27:52 triggered the first real sensor open. Cold TLS/background/FDT
preparation took about five seconds, so the fingerprint prompt appeared only at
10:27:57 and eventually timed out.

rel33 adds a package-owned gxfp51a0-boot-prewarm.service. It is pulled in by
graphical.target, Requires/After fprintd.service, and is ordered
Before=display-manager.service. Its bounded Claim performs the normal driver
open/close lifecycle before the greeter is allowed to start. Failure is logged
but never blocks password login indefinitely.

A controlled cold-state simulation (restart fprintd, then run boot prewarm)
completed in 4.703 seconds with Result=success and the log
"sensor ready before display manager". After that prewarm, fprintd-verify
immediately reached Verify started / Verifying without another cold preparation.

### rel34 candidate: fresh validated handoff

The first rel33 cold-boot test proved the boot prewarm itself was working:
gxfp51a0-boot-prewarm finished at 11:27:12 CEST and Plasma Login Manager started
after it. PAM fingerprint began at 11:27:16. However, the next device open still
ran rel31's full warm validation, including another background GET_IMAGE, while
the user had already placed a finger. That first login attempt later hit a
GET_IMAGE retry and Plasma Login Manager reported fingerprint recognition
failure.

rel34 adds a one-shot fresh-handoff token inside the driver. When a healthy
prepared device is closed, the next open may consume that token for at most 10
seconds and reuse the already validated TLS/background/FDT context without
issuing a redundant background GET_IMAGE. The token is consumed exactly once,
is cleared on lifecycle invalidation/recovery, and never bypasses sleep or
5-minute idle expiry handling. Older contexts continue through rel31's complete
FDT + encrypted GET_IMAGE validation.

Runtime validation on the reference machine proved both paths:
- cold restart -> boot-prewarm -> immediate Verify: token consumed at 88 ms,
  no background GET_IMAGE before FP_FINGER_STATUS_NEEDED;
- after waiting beyond 10 seconds, the next Claim returned to
  warm context image-validated with a real background capture.

### rel35 candidate: collision-free first login attempt

The rel33 human cold-boot failure also exposed two userspace problems beyond the
redundant warm validation fixed by rel34. The periodic keepalive still had
OnBootSec=20s, so it claimed the sensor while Plasma Login Manager was beginning
its first PAM transaction. In that same transaction, the compatibility PAM rule
used max-tries=1, making one placement false-rejection terminal.

rel35 keeps rel34's fresh one-shot handoff unchanged. The keepalive timer now
uses OnActiveSec=3min plus OnUnitActiveSec=3min and has no OnBootSec trigger, so
boot-prewarm owns initial readiness without a second Claim racing the greeter.
The Plasma Login Manager compatibility package moves to 6.7.5-3.3 and uses
pam_fprintd max-tries=3 timeout=12. This restores the normal three-attempt
pam_fprintd policy while retaining the bounded 12-second login window.

No biometric threshold, enrollment format, matcher or capture recipe changes in
rel35.

### Arch / CachyOS

From the repository root:

```bash
./fingerprint/install-arch.sh
```

The installer:

1. refuses to run if the `GXFP51A0` SPI/ACPI device is absent;
2. builds the reviewed libfprint patch locally;
3. installs `libfprint-goodix51a0` and `fprintd`;
4. grants fprintd only the additional gpiochip device access needed by this
   driver;
5. installs an early cold-boot prewarm ordered before the display manager;
6. installs the package-owned post-resume prewarm hook/worker;
7. deliberately installs no periodic synthetic Claim keepalive;
8. when KDE Plasma 6.7.5 is present, installs the reversible window-ready
   lock-screen integration and its pacman reapply hook;
9. when Plasma Login Manager 6.7.5 is installed, builds/installs the
   package-managed password/fingerprint preemption compatibility package;
10. removes obsolete rel24–rel40 timing integers, reloads udev and restarts
    fprintd without touching enrollments or the PMK cache.

Non-KDE desktops are left unchanged. On KDE, one package-owned
LockScreenUi.qml file is intentionally patched by the integration helper and
restored on driver removal.

Then enroll through your desktop settings or standard fprintd:

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
fprintd-list "$USER"
```

The driver requests 20 enrollment presses. Move the finger slightly between
presses so the small 80×64 sensor sees different parts of the fingertip.

### Existing development templates

The current on-disk template format is driver template v4 / SIGFM feature format
v3. Users coming from older development revisions of this repository may need
to delete and re-enroll old prints once:

```bash
fprintd-delete "$USER"
```

Fresh installations do not need this step.

### Debian / Ubuntu / Fedora / openSUSE / Alpine / other Linux

The portable source installer rebuilds the exact pinned libfprint candidate and
keeps the replacement isolated under `/usr/local`:

```bash
./fingerprint/install-linux.sh
```

It installs build dependencies on Arch/CachyOS, Debian/Ubuntu, Fedora,
openSUSE and Alpine. Arch/CachyOS delegates to the native pacman package.
Elsewhere it stages the candidate, validates the distro fprintd ABI, then
isolates the local libfprint to fprintd via a systemd drop-in or D-Bus
activation wrapper. A rollback manifest is recorded.

Rollback after a source installation:

```bash
sudo /var/lib/gxfp51a0-local-install/uninstall.sh
```

Use `./fingerprint/install-linux.sh --build-only` to validate compilation
without installing anything.

## Matcher

The production matcher uses:

- adaptive background subtraction for the exact target sensor;
- percentile normalization + unsharp enhancement;
- two-level multi-scale FAST-9 keypoints;
- unsteered BRIEF-256 descriptors;
- mutual-best cross-check + Lowe ratio filtering;
- 200-iteration rigid RANSAC with 2 px inlier tolerance;
- least-squares rigid refinement;
- best score across 20 enrolled views.

The driver does **not** lower the threshold after a failed attempt, sum weak
scores across attempts, or learn from failed/low-confidence verification.

A pixel-overlap/ZNCC scorer remains available only behind the explicit
`GXFP_MATCH_DIAGNOSTICS` research environment flag. It is not part of the
authentication decision.

## Contributor validation

```bash
make -C fingerprint verify
```

This runs the deterministic research/safety suite, validates the source
manifest, fetches exact libfprint `v1.94.100`, builds the candidate and checks
the resulting artifacts.

Release gates include:

```text
SOURCE_MANIFEST=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_FASTBRIEF_RANSAC_IN_LIBRARY=YES
GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES
RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT
SOFTWARE_BUILD_READY=YES
ACTIVE_SENSOR_IO=NONE
GPIO_WRITES=NONE
MMIO_WRITES=NONE
FIRMWARE_ACTIONS=NONE
```

The validation target performs no active sensor transfer, GPIO/MMIO write or
firmware action.

Optional local diagnostics for maintainers are under `fingerprint/tools/`.
Normal users do not need them.

## Safety and privacy

Never commit or publish:

- fingerprint captures or enrolled templates;
- PMK/PSK/key material or per-unit fixtures;
- proprietary Goodix/Huawei binaries or firmware;
- serial numbers or private machine identifiers.

The PMK cache and learned timing value are runtime state under
`/var/lib/fprint/`; neither is shipped in the package or repository.

The v4 local fprintd template is biometric data. It includes normalized
per-view information used by the matcher/research diagnostics and should be
protected like any other fingerprint template.

The driver does not flash sensor firmware.

## Support scope

The proven target is the exact GXFP51A0 / GF3658 / ST411 combination above.
Another machine with the same ACPI HID may still have different GPIO wiring,
firmware or board integration. The installer therefore detects the HID, while
the runtime also validates the expected target behavior.

This remains reverse-engineered, experimental biometric software. Validation so
far is strongest on the reference unit and same-user cross-finger negative
controls; it is not a substitute for a large cross-person biometric
certification corpus. Do not treat fingerprint alone as a high-assurance
security factor.

See:

- [native desktop integration](docs/native-desktop-integration.md)
- [provenance](PROVENANCE.md)
- [driver source](driver/goodix51a0/)
- [research log](docs/research-log.md)
- [current handoff](HANDOFF_CURRENT.md)

The production driver subtree is `LGPL-2.1-or-later`; see per-file SPDX
notices and [provenance](PROVENANCE.md).

[executed on device: Pegasus (8a6eeb21-0158-4e6d-b3ea-91d580f8a223)]