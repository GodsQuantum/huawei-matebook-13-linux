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
