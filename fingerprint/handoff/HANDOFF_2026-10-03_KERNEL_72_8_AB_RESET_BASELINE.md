# HANDOFF — GXFP51A0 kernel 7.2.8 A/B reset to known-good baseline — 2026-10-03

## Why this reset was necessary

The October 3 rel73-rel75 experiments were not sufficiently isolated.

Human-success chronology:
- rel59 normal lock PASS: READY ~6.1 s, 5 -> 6 -> 7
- rel59 deep S3 PASS: resume -> READY ~7.8 s, 8/7
- rel60 normal lock PASS: READY ~6.84 s, first genuine image 9/7
- rel61 deep S3 PASS: resume -> READY ~21.5 s, first genuine image 20/7
- rel66 conditional S3 PASS when the sensor was genuinely parked: READY +4.434 s, 7/7

All of those successes predate installation of linux-cachyos 7.2.8-2.

Package history:
- linux-cachyos 7.2.8-1 was the installed kernel during the validated rel59/60/61 period.
- 7.2.8-2 was first installed on 2026-10-02 21:27.
- current 2026-10-03 boot is the first fingerprint-validation boot on 7.2.8-2.
- an exact rel71/rel61 libfprint binary, SHA
  d7d4b1d7d56e33b1a2e8c33ada0fc11984229d2507c5ec797816d4b338d9c997,
  produced only 3-4/7 under 7.2.8-2 even after external GPIO264/spidev recovery.
- therefore matcher/templates/userspace code alone cannot explain the regression.

A kernel A/B was prepared at 12:29 by downgrading to 7.2.8-1, but at 13:02:56
another root shell on TTY pts/1 ran:
  pacman --color always -Syu
and re-upgraded linux-cachyos / headers from 7.2.8-1 to 7.2.8-2 at 13:03.

CachyOS then ran cachyos-reboot-required.hook and explicitly reported:
  Reboot is recommended due to the upgrade of core system package(s).

Therefore rel73, rel74 and rel75 were all tested on the suspected 7.2.8-2 runtime.
Those userspace experiments are useful evidence, but they did not isolate the
strongest environmental variable.

## Kernel build difference

Local package BUILDINFO:
- 7.2.8-1: clang/llvm/lld 22.1.8; glibc 2.44+r24
- 7.2.8-2: clang/llvm/lld 23.1.1; glibc 2.44+r50

Earlier binary analysis on the same machine established:
- spi-pxa2xx-platform executable text: effectively unchanged
- spi-pxa2xx-core has the same source srcversion but different machine-code .text
- normalized differences include pxa2xx_spi_transfer_one()
- spi-dw machine code also differs

This does NOT prove a compiler/kernel regression, but it makes kernel/toolchain a
first-class variable. It must be A/B tested before more libfprint tuning.

## rel75 recovery-lock evidence

After a long GPIO264 reset + spidev rebind on unchanged rel75:
- finger detection returned immediately:
  touch=0x3f, 6 zones, mean=215, drop=137
- GET_IMAGE still needed retry
- first genuine score was 3/7
- same-press FDT then saw release and stopped
- therefore external hardware recovery restores sensor reactivity but does not
  restore good image quality on 7.2.8-2.

This reinforces the transport/runtime hypothesis.

## Controlled next-boot baseline prepared

On disk now:
- linux-cachyos 7.2.8-1
- linux-cachyos-headers 7.2.8-1
- NVIDIA 580.178.04 DKMS installed for 7.2.8-1
- exact reconstructed rel71 / rel61 driver:
  libfprint-goodix51a0 1.94.100.goodix51a0-71
  live SHA d7d4b1d7d56e33b1a2e8c33ada0fc11984229d2507c5ec797816d4b338d9c997
- stock fprintd 1.94.5-2.1
  live SHA db4e909a968af7b19cff249b2b3546fefdc80f277c11afb7ee083e0878c2cb63
- kscreenlocker 6.7.5-1.5 retained
- plasma-login-manager 6.7.5-3.9 retained
- gxfp51a0-fprintd-suspend.service DISABLED
- sleep.target fingerprint Wants empty
- no external system-sleep GXFP hook
- zero failed systemd units

The currently running kernel remains 7.2.8-2 until the USER manually reboots.

Temporary pacman hold:
- /etc/pacman.conf contains:
  # GXFP51A0 TEMP HOLD 2026-10-03
  IgnorePkg = linux-cachyos linux-cachyos-headers
- backup: /etc/pacman.conf.gxfp-pretest-20261003
- purpose: prevent another unrelated pacman -Syu from invalidating the A/B before testing.
- MUST be removed after the controlled validation / final kernel decision.

## Required next gate

Do not make rel76. Do not change matcher, threshold, enrollment, timing, S3 lifecycle
or fprintd before this gate.

After user-initiated reboot:
1. verify uname -r == 7.2.8-1-cachyos
2. verify exact rel71 + stock fprintd hashes above
3. before any suspend/S3, perform ONE normal graphical lock fingerprint attempt
4. collect complete logs
5. if normal lock PASS, then perform exactly ONE user-triggered deep S3 test
6. if normal lock FAIL, diagnose that cold-boot trace before any new release

Interpretation:
- PASS on -1 with exact rel71 strongly implicates the -2 kernel/toolchain/runtime boundary.
- FAIL on -1 means the kernel difference is insufficient and another changed
  environmental/hardware-state variable must be identified.

## A/B RESULT — NORMAL LOCK PASS — 2026-10-03 17:34 CEST

User report:
- rebooted Pegasus
- locked the session
- placed enrolled finger
- session unlocked successfully

Verified runtime after reboot:
- kernel: 7.2.8-1-cachyos
- boot ID: a707242c-0601-4222-8ea8-f2886e382f50
- libfprint-goodix51a0 1.94.100.goodix51a0-71
- libfprint SHA:
  d7d4b1d7d56e33b1a2e8c33ada0fc11984229d2507c5ec797816d4b338d9c997
- fprintd 1.94.5-2.1
- fprintd SHA:
  db4e909a968af7b19cff249b2b3546fefdc80f277c11afb7ee083e0878c2cb63
- kscreenlocker 6.7.5-1.5
- plasma-login-manager 6.7.5-3.9
- external gxfp51a0 suspend service disabled
- sleep.target Wants empty

Normal-lock trace:
- KScreenLocker lock started ~17:34:45
- one FDT ACK retry occurred
- warm rebase was safely discarded because the finger landed during background capture
- READY: 17:34:48.216458
- DETECTED_HOLD: 17:34:48.411998
  - touch=0x3f
  - zones=6
  - mean=204
  - drop=151
- first GET_IMAGE needed the existing safe no-evidence retry
- rel59 retry-assisted pacing rose from 250% to 300% (90 ms)
- first genuine biometric image:
  score=7 threshold=7 candidate=0
- completed with best=7/7
- user confirms actual unlock

Evidence:
- fingerprint/handoff/evidence/REL71_KERNEL72_8_1_NORMAL_LOCK_PASS_2026-10-03_173445.log
- SHA256:
  f023d3e7b652df8929fa3e42d1556f1d255256337907edad5562e441a2e0e7e1

A/B conclusion:
- the exact same rel71/rel61 runtime binary that scored only 3-4/7 on
  linux-cachyos 7.2.8-2 now reaches the acceptance threshold and unlocks on
  linux-cachyos 7.2.8-1 after a clean reboot.
- this is strong evidence that the 7.2.8-2 kernel/build/runtime boundary is a
  material cause of the regression.
- it does NOT yet prove whether the root cause is Clang/LLVM 23.1.1, LTO/code
  generation, another packaging/config difference, or a kernel-side runtime
  interaction. Do not overstate the exact mechanism without a narrower kernel
  build test.
- no further rel73/74/75-style userspace tuning should be layered onto the
  currently working baseline before the S3 gate.

## A/B RESULT — DEEP S3 PASS — 2026-10-03 17:46 CEST

User result:
- deep S3 succeeded
- fingerprint unlock succeeded on what the user experienced as the second pose

Verified sleep:
- PM: suspend entry (deep): 17:46:01.517790
- ACPI S3 entry occurred
- PM: suspend exit: 17:46:05.782939
- no external GXFP system-sleep hook
- fprintd remained the same PID 740 across S3

Post-resume authentication:
- first transport activity: 17:46:09.035295
- READY: 17:46:13.550420
- resume -> READY: about 7.77 s
- DETECTED_HOLD: 17:46:13.745602
  - touch=0x3f
  - zones=6
  - mean=225
  - drop=128
- GET_IMAGE used the existing safe no-evidence retry
- retry-assisted pacing applied: 250% -> 300%, 90 ms
- first biometric image captured after READY:
  score=15 threshold=7 candidate=0
- best=15/7
- user confirms successful unlock

The user's perceived “second pose” is consistent with the first physical placement
landing during post-resume transport/calibration before READY. The first pose that
the driver actually accepted after READY was successful immediately at 15/7.

Evidence:
- fingerprint/handoff/evidence/REL71_KERNEL72_8_1_DEEP_S3_PASS_2026-10-03_174601.log
- SHA256:
  284eb7b85dfb9ae79639b38a591fc4a0046c00ac5a8b1cabdac1f17cd9419e4f

## Stable-today decision

The validated runtime for Pegasus is now:
- linux-cachyos 7.2.8-1
- exact rel71/rel61 libfprint binary
- stock fprintd 1.94.5-2.1
- kscreenlocker 6.7.5-1.5
- plasma-login-manager 6.7.5-3.9
- SIGFM threshold 7
- no external fingerprint sleep hook
- no heartbeat/keepalive
- no persistent timing-learning file
- no re-enrollment

Human gates passed on this exact baseline:
1. normal graphical lock -> fingerprint unlock PASS, first accepted image 7/7
2. genuine deep S3 -> fingerprint unlock PASS, first accepted post-READY image 15/7

Therefore:
- do not create rel76 today
- do not layer rel73/74/75 changes onto the working runtime
- keep the temporary linux-cachyos / headers hold so unrelated system updates do
  not silently reinstall 7.2.8-2 before the kernel regression is resolved
- normal package updates remain possible; only these two kernel packages are held
- future engineering should reproduce/fix the 7.2.8-2 SPI/kernel-build regression
  separately, with the stable 7.2.8-1 + rel71 runtime preserved as the control
- do not market or tag a “universal/perfect” driver yet: distro portability is
  already strong, but kernel-build portability is not solved until the -2
  regression is understood or compensated without harming this baseline
