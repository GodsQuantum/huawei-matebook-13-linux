# GXFP51A0 native fprintd release handoff — 2026-09-19 23:55

## Canonical workspace

Repository root: the checkout containing this file.

Fingerprint project: `fingerprint/`.

Use repository-relative paths in public documentation. Local checkout paths
belong in the operator's private notes, not in this repository.

## Current production state

Installed on reference MateBook:

```text
libfprint-goodix51a0 1.94.100.goodix51a0-7
fprintd 1.94.5-2.1
device /net/reactivated/Fprint/Device/0
enrolled right-index-finger
```

The driver is a native libfprint/fprintd device. No GXFP51A0-specific KDE/GNOME
UI or protocol layer is wanted.

## What changed in rel7

- hardware `open` no longer fails solely because opportunistic
  TLS/background/FDT prewarm times out;
- actual enroll/verify/identify performs a bounded whole-session retry from a
  reset/A8 firmware boundary;
- standard libfprint `identify` is implemented for fprintd multi-finger
  `VerifyStart("any")`;
- verify/identify report terminal biometric results immediately after scoring;
  finger-lift is cleanup, not login latency;
- release builds compile out the biometric capture-dump writer;
- artifact gates verify identify presence and dump-writer absence under LTO.

Important: do not reduce the match threshold or add score-conditioned recapture.
A usable biometric image produces one decision.

## Validation

Final source-tree validation:

```text
SOFTWARE_BASELINE=PASS
SOURCE_MANIFEST=PASS
LIBFPRINT_PATCH=PASS
MESON_CONFIGURE=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES
RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT
SOFTWARE_BUILD_READY=YES
```

## Live rel7 observations

On 2026-09-19 rel7 installed cleanly without reboot.

fprintd discovery and stored print listing succeed. During a live right-index
verify:

- open/TLS/config/prewarm succeeded;
- fprintd reported `finger-needed=true`;
- the finger was detected;
- GET_IMAGE produced a complete 10,573-byte image;
- capture timing was about 1.51 s;
- matcher result was `0 / threshold 15`;
- early `verify-no-match` was reported while the finger was still present;
- later VerifyStop cancellation was treated as post-result cleanup.

This proves the user's removal timing was not the cause of that specific
no-match. Do not infer matcher regression from one sample; repeat with the
guided harness and collect score distribution.

## Human-interaction rule

Never coordinate PRESS/HOLD/REMOVE through chat timing.

Use:

```bash
./fingerprint/tools/gxfp51a0-verify-diagnostic.py
```

The harness is synchronized to fprintd's standard D-Bus
`finger-needed`/`finger-present` properties, not chat and not GXFP debug
logging. It gives a local 3-2-1 countdown and explicit POSE/GARDE/RETIRE orders.
Logs go to `~/.local/state/gxfp51a0/`.

Official fprintd intentionally exposes one extra enrollment stage when
`FP_DEVICE_FEATURE_IDENTIFY` is available. The driver still requests 15
biometric enrollment captures; fprintd may expose 16 frontend stages.

## Publication work

Added/updated:

- `fingerprint/README.md`
- `fingerprint/README.FR.md`
- `fingerprint/PROVENANCE.md`
- `fingerprint/docs/native-desktop-integration.md`
- `fingerprint/install-arch.sh`
- `fingerprint/tools/gxfp51a0-verify-diagnostic.py`
- Arch/CachyOS `PKGBUILD` + minimal fprintd gpiochip sandbox drop-in
- explicit LGPL-2.1-or-later boundary/COPYING for production driver subtree
- CI gates for public-tree privacy and guided diagnostic syntax
- package/build outputs ignored from git.

Public installer builds from source locally and does not edit PAM.

## Next live boundary

Run several guided genuine right-index verifies before changing matcher logic.
Record score distribution and capture timing. If genuine captures repeatedly
score near zero while previously validated rel6 genuine captures matched,
compare rel6/rel7 matcher inputs and template loading before changing any
threshold.

Then test `VerifyStart("any")` with at least two enrolled fingers to exercise
the new identify path through fprintd.

## Safety / release locks

- no firmware flashing;
- no speculative PMK/PSK publication;
- no biometric raw capture in release artifacts;
- no PAM edits from the public installer;
- no personal paths, private IPs or machine identifiers in the public tree;
- build/package directories remain untracked.

## Resume order

1. read this file in full;
2. read `../HANDOFF_CURRENT.md`;
3. inspect `git status` and current GitHub CI;
4. use the guided diagnostic for any human finger interaction;
5. diagnose repeated genuine-score failures before modifying matcher thresholds.
