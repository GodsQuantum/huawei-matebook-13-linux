# Current handoff — GXFP51A0 / GF3658 ST411

Updated: 2026-09-21.

## Current release candidate

- package revision: libfprint-goodix51a0 1.94.100.goodix51a0-23
- release tag: fingerprint-gxfp51a0-rel23
- libfprint base: v1.94.100
- fprintd validated line: 1.94.5
- exact validated target: GXFP51A0, GF3658/ST411, chip 0x2504
- validated firmware: GF_ST411SEC_APP_14115
- native path: sensor -> libfprint -> fprintd -> KDE/GNOME/PAM/CLI
- no device-specific desktop UI
- no firmware flash or replacement
- no GXFP-specific runtime daemon or systemd binder

## Native SPI and prewarm lifecycle

rel23 removes the rel22 `gxfp51a0-spidev-bind.service`. The generated
libfprint udev rule matches the real ACPI modalias, loads/binds `spidev` and
creates the standard SPI character device. Udev-only rebinding was validated
over repeated unbind/module-removal recovery cycles.

The standard fprintd service is started by the graphical boot transaction and
runs with `--no-timeout`. libfprint `probe()` opportunistically prepares TLS,
a clean background frame and the FDT baseline. Probe prewarm is bounded to two
attempts; every retry starts from a reviewed MCU reset boundary. fprintd has a
40 s start timeout so a rare second prewarm attempt is not killed midway.

A complete warm context remains only in the root fprintd process. On
`FpDevice::close`, SPI/GPIO handles are closed while TLS/background/FDT state
is retained. The next Claim reopens the handles and validates the hardware with
an FDT probe before reusing the context. If validation fails, the warm state is
discarded and the existing bounded cold recovery path is used.

There is deliberately no artificial warm-state TTL. Testing a 60 s expiry
showed that forcing a healthy sensor back through cold TLS/background setup can
turn a later login into a multi-second recovery. fprintd core dumps are disabled
(`LimitCORE=0`) and the state never leaves process memory.

Measured non-biometric Claim/Release tests on the reference machine:

- normal warm first Claim after fprintd startup: about 100–120 ms;
- repeated Claims in the same daemon: about 90–110 ms;
- after more than 65 s idle: first Claim remained about 113 ms;
- aggressive five-restart stress: all first Claims remained 112–113 ms; rare
  prewarm retries increased background service startup time but did not shift
  that delay onto the first Claim.

Existing template-v4 enrollments remain visible; rel23 does not require
re-enrollment.

## Matcher

Production matching is pure C FAST-9 + BRIEF-256 + cross-check + rigid RANSAC.
The acceptance threshold is fixed at 7 inliers. Enrollment stores 20 views.
Verification may request up to three complete independent presses after
no-match results; the retry budget is fixed and never depends on score
proximity. Identify remains single-capture.

The optional pixel/ZNCC scorer is diagnostic-only behind the explicit
GXFP_MATCH_DIAGNOSTICS environment flag and never changes authentication.
Rejected mosaic-star and adaptive-learning experiments are not in the
production authentication path.

## Transport and performance

Stable reply-bearing capture commands use bounded event-driven draining. NOP
has no ACK wait. Ambiguous image ordering keeps conservative retry handling.
Initialization/TLS may learn a 100–300 percent timing scale after real
synchronization failures. The validated fingerprint capture recipe is separate
and always keeps its nominal 30 ms inter-command gap.

After TLS establishment, cold/context preparation waits for GPIO48 to return to
the idle-low level and gives the MCU a short quiesce window before the first
background capture. This avoids racing the tail of the handshake. The normal
warm Claim path does not pay this delay.

## Template format

Driver template version 4 / SIGFM serialization version 3. Existing rel20/rel22
template-v4 enrollments remain compatible with rel23.

## Release validation

The rel23 software baseline passes the complete repository gate:

- shell/source regression tests;
- research unit and safety suite;
- source manifest;
- reproducible build from exact libfprint v1.94.100;
- compiled GXFP51A0 object and generated udev support;
- FAST/BRIEF/RANSAC and identify paths;
- release biometric dump hook absent.

Passive build validation performs no active sensor transfer, GPIO/MMIO write or
firmware action.

The Arch/CachyOS installer builds locally and does not modify PAM, KDE or GNOME.
It adds only the gpiochip access needed by the driver, uses the standard
fprintd daemon and the generated libfprint udev rule.

## Privacy and safety invariants

Never publish biometric captures/templates, PMK/PSK/key material, per-unit
fixtures, serial numbers, private machine identifiers, proprietary firmware or
Windows binaries. Runtime PMK/timing state under /var/lib/fprint is not part of
the repository or package.

GPIO112 must never be touched. GPIO264 is the MCU reset and must be left low
while the sensor is running. Hardware experiments remain bounded and explicit.

## Further work

No additional physical test battery is required for the rel23 public release.
Future matcher/security changes should be driven by ordinary-use reports and,
ideally, a larger consented cross-person validation corpus. Do not lower
threshold 7 or activate pixel-score acceptance without such validation.
