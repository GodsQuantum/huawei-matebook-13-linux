# Current handoff — GXFP51A0 / GF3658 ST411

Updated: 2026-09-20.

## Current release candidate

- package revision: libfprint-goodix51a0 1.94.100.goodix51a0-22
- libfprint base: v1.94.100
- fprintd validated line: 1.94.5
- exact validated target: GXFP51A0, GF3658/ST411, chip 0x2504
- validated firmware: GF_ST411SEC_APP_14115
- native path: sensor -> libfprint -> fprintd -> KDE/GNOME/PAM/CLI
- no device-specific desktop UI
- no firmware flash or replacement

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

## Template format

Driver template version 4 / SIGFM serialization version 3. Existing templates
from older development revisions must be deleted and enrolled once. Fresh
installs use normal KDE/fprintd enrollment.

## Release validation

The rel22 baseline and full libfprint build pass. Release gates verify the
source manifest, compiled GXFP51A0 object, FAST/BRIEF/RANSAC code, identify
path and absence of the biometric dump hook. Passive validation performs no
active sensor transfer, GPIO/MMIO write or firmware action.

The Arch/CachyOS installer builds locally and does not modify PAM, KDE or GNOME.
It adds only gpiochip access to the upstream fprintd sandbox. rel22 also fixes
cold-boot transport readiness: the generated udev rule matches ACPI
compatible-ID suffixes, and fprintd requires an idempotent systemd binder that
prepares GXFP51A0 -> spidev and verifies the character node before fprintd
starts. The binder never unbinds an unexpected kernel driver. Three transport
reset/recovery cycles were validated without a fingerprint press: D-Bus
activation of fprintd recreated spidev and rediscovered all enrolled fingers
each time.

## Privacy and safety invariants

Never publish biometric captures/templates, PMK/PSK/key material, per-unit
fixtures, serial numbers, private machine identifiers, proprietary firmware or
Windows binaries. Runtime PMK/timing state under /var/lib/fprint is not part of
the repository or package.

GPIO112 must never be touched. GPIO264 is the MCU reset and must be left low
while the sensor is running. Hardware experiments remain bounded and explicit.

## Further work

No additional physical test battery is required for the current public driver
push. Future work should be driven by ordinary-use reports and, ideally, a
larger consented cross-person validation corpus. Do not lower threshold 7 or
activate pixel-score acceptance without such validation.
