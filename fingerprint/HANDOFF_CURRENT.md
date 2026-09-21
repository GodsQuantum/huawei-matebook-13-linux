# Current handoff — GXFP51A0 / GF3658 ST411

Updated: 2026-09-21.

## Stable and candidate

- stable public release: `fingerprint-gxfp51a0-rel23`
- stable main before this candidate: `c99522c0a00245e30fed7d050b1314b678f04694`
- compatibility candidate: rel24-rc1 / package `libfprint-goodix51a0 1.94.100.goodix51a0-24`
- libfprint base: v1.94.100
- fprintd validated line: 1.94.5
- exact validated target: GXFP51A0, GF3658/ST411, chip 0x2504
- validated firmware: GF_ST411SEC_APP_14115

rel23 remains the stable/latest release until the MateBook 13 2020 reporter validates rel24-rc1. rel24-rc1 is installed on the 2021 Pegasus reference machine and keeps all existing template-v4 enrollments visible.

## Why rel24-rc1 exists

GitHub issue #6 provided the first confirmed MateBook 13 2020 WRTB-WXX9 ST411/14115 data point. rel23 authenticates correctly there (reported genuine score 27, impostor score 3 at fixed threshold 7), but capture is about 760 ms and the transport can enter repeated GET_IMAGE/FDT no-ACK states, causing multi-second PAM delays.

Pegasus also reproduced the related exhausted-retry signature where GET_IMAGE receives its cleartext ACK but the TLS image still never arrives.

## rel24 transport policy

Capture pacing is deliberately independent from the existing target/TLS timing scale.

- nominal capture step gap remains 30 ms / 100%;
- an exhausted GET_IMAGE transport failure raises capture pacing by 50 percentage points;
- capture pacing is clamped to 100–300% (30–90 ms);
- both `no ACK/TLS after retries` and `ACK but no TLS image after retry` mark transport desynchronisation;
- the next retry starts from a full MCU reset/session rebuild;
- a transport failure is not a biometric decision and does not increment the fixed verification attempt counter;
- learned capture pacing is persisted only after a complete successful finger capture;
- the separate TLS/init timing state cannot inflate capture pacing.

This preserves the 2021 fast path while allowing genuinely slow units to adapt.

## Boot/prewarm policy

Enumeration-time prewarm is an optimization, not a service-availability requirement.

rel24-rc1 therefore uses:

- one outer probe prewarm attempt;
- at most two cached-PMK TLS attempts during probe;
- no fresh-staging fallback during probe;
- normal fprintd availability even if prewarm fails;
- the full existing 5-attempt TLS + stale-cache/fresh-staging bounded recovery only on the real biometric/open path.

The Arch/CachyOS package restarts fprintd with `systemctl restart --no-block`, so package transactions no longer wait for sensor prewarm.

## Pegasus runtime validation

Final rel24 candidate installed on Pegasus without reboot.

Observed:

- package revision: `1.94.100.goodix51a0-24`;
- package integrity: 32 files, 0 altered;
- fprintd: active with `--no-timeout`;
- existing enrollments: left index, right middle, right index;
- persisted TLS timing on this machine: 300%;
- persisted capture timing: absent, proving TLS timing no longer contaminates the 30 ms capture default;
- five non-biometric list/Claim-style accesses: about 30–40 ms;
- degraded probe state: prewarm stopped after 2/2 cached-PMK TLS tries and fprintd still entered active state instead of hitting the 40 s systemd timeout;
- package reinstall transaction with asynchronous service restart: about 10–11 s.

No new manual fingerprint pose was required for this validation.

## Matcher and template invariants

Unchanged from rel23:

- production matcher: C FAST-9 + BRIEF-256 + cross-check + rigid RANSAC;
- fixed acceptance threshold: 7 inliers;
- enrollment: 20 views;
- verification: max three independent complete presses;
- no weak-score accumulation;
- pixel/ZNCC remains diagnostic-only;
- template v4 / SIGFM v3 remains compatible.

## Safety/privacy invariants

- never touch GPIO112/GPP_D16;
- GPIO264 is MCU reset and remains low during operation;
- no firmware flashing;
- no release biometric dump hook;
- never publish PMK/PSK, biometric captures/templates, machine IDs, serials, private fixtures, proprietary firmware or Windows binaries;
- no reboot without explicit user authorization.

## Release validation

The final candidate passes the complete software baseline:

- research/safety tests;
- first-contact and native SPI binding tests;
- new adaptive capture pacing/recovery tests;
- short-soft prewarm tests;
- source manifest;
- reproducible libfprint v1.94.100 build;
- generated udev support;
- FAST/BRIEF/RANSAC and identify gates;
- release biometric dump hook absent.

Final state: `SOFTWARE_BASELINE=PASS`.

## Publication status

- candidate branch pushed: `fingerprint-rel24-slow-transport`;
- tested code commit/tag: `ff515ad1c90903a315e6c8d3a0bc33f4628aad03` / `fingerprint-gxfp51a0-rel24-rc1`;
- GitHub prerelease published with Arch/CachyOS package, portable source bundle, INSTALL and SHA-256 manifest;
- GitHub `Quality` and `Fingerprint candidate build` workflows: SUCCESS on `ff515ad`;
- rel23 remains stable/Latest;
- issue #6 reply posted with the prerelease link and a request for only non-sensitive timing/log validation on the MateBook 13 2020.

Do not promote rel24 to stable/latest until the external 2020 validation is positive. If the reporter confirms the fix, re-run the complete gate on the final commit, promote the transport path to the next stable release, update the local OS & Drivers kit, then remove obsolete candidate-only artifacts.
