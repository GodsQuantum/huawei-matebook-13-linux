# Goodix GXFP51A0 / GF3658 ST411 on Linux

Native experimental libfprint driver for the SPI Goodix GXFP51A0 found in the
Huawei MateBook 13 2021 family.

> Français: [README.FR.md](README.FR.md) · 简体中文: [README.ZH-CN.md](README.ZH-CN.md)

## Status — 2026-09-20

Hardware-validated target:

- ACPI HID: `GXFP51A0`
- Goodix GF3658 / ST411, chip ID `0x2504`
- validated firmware: `GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`, 1 MHz
- GPIO48 readiness/IRQ and GPIO264 MCU reset
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- 80×64 active fingerprint image
- libfprint base: `v1.94.100`

Production path:

```text
GXFP51A0 → libfprint → fprintd → KDE / GNOME / PAM / CLI
```

No device-specific desktop UI, PAM rewrite, firmware replacement or proprietary
Goodix runtime is required.

### What is validated

On the reference GXFP51A0/GF3658/ST411 unit:

- standard KDE/fprintd enrollment completes with **20 accepted presses**;
- FAST-9 + BRIEF-256 + rigid RANSAC matching runs entirely host-side in C;
- the acceptance threshold remains fixed at **7 RANSAC inliers**;
- successful verification returns immediately;
- a non-match may request up to **3 complete, independent presses** before a
  terminal rejection. The retry count is fixed and never depends on how close a
  score is to the threshold;
- `identify` remains single-capture;
- transient target/TLS desynchronisation uses bounded recovery and a persisted
  initialization timing scale;
- the image-capture recipe keeps its validated nominal 30 ms inter-command gap,
  independent of the slower initialization recovery scale;
- release builds contain no biometric dump writer.

The 3-press policy is deliberate for this very small partial-print sensor. It
reduces placement-related false rejections without lowering the biometric
threshold or combining weak scores across attempts.

## Install

### Download the packaged rel23 release

For the validated GXFP51A0 / GF3658 ST411 target, the easiest starting point is the [rel23 GitHub release](https://github.com/GodsQuantum/huawei-matebook-13-linux/releases/tag/fingerprint-gxfp51a0-rel23). It contains the native Arch/CachyOS package, a portable Linux source bundle, install instructions and SHA-256 checksums.

rel23 uses the native libfprint SPI path end-to-end. The generated udev rule accepts ACPI compatible-ID suffixes such as `acpi:GXFP51A0:GXFP51A0:` and binds the device to `spidev` without a GXFP-specific systemd binder. Standard fprintd starts as part of the graphical boot transaction with `--no-timeout`; libfprint `probe()` prewarms TLS, background and FDT state. A complete warm context survives fprintd Claim/Release while SPI/GPIO handles are closed, is hardware-revalidated on the next Claim, and falls back to the bounded cold path if the sensor state was lost. Existing template-v4 enrollments remain compatible.

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
5. reloads udev and restarts fprintd.

It **does not modify PAM, KDE or GNOME configuration**.

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

### Debian / Ubuntu / Fedora / other Linux

The portable source installer rebuilds the exact pinned libfprint candidate and
keeps the replacement isolated under `/usr/local`:

```bash
./fingerprint/install-linux.sh
```

It installs build dependencies on Arch/CachyOS, Debian/Ubuntu, Fedora and
openSUSE families. On Arch/CachyOS it delegates to the native pacman package.
On other supported families it installs a local libfprint build only for
fprintd through a systemd drop-in and records a rollback manifest.

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
