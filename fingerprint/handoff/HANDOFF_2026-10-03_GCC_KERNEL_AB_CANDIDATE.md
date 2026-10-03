# HANDOFF — official CachyOS GCC kernel A/B candidate — 2026-10-03

## Do not disturb the validated runtime

Current running / human-validated control remains:
- kernel: linux-cachyos 7.2.8-1-cachyos
- libfprint-goodix51a0 1.94.100.goodix51a0-71
- libfprint SHA256:
  d7d4b1d7d56e33b1a2e8c33ada0fc11984229d2507c5ec797816d4b338d9c997
- fprintd 1.94.5-2.1
- fprintd SHA256:
  db4e909a968af7b19cff249b2b3546fefdc80f277c11afb7ee083e0878c2cb63
- normal-lock human PASS: first accepted image 7/7
- genuine deep-S3 human PASS: first accepted post-READY image 15/7,
  resume -> READY about 7.77 s
- no external GXFP sleep hook
- zero failed systemd units

Do NOT replace this control or create rel76 before the kernel A/B work is resolved.

## Why a GCC kernel candidate

The failing linux-cachyos 7.2.8-2 and working 7.2.8-1 have:
- the same kernel package source version 7.2.8
- the same spi-pxa2xx-core srcversion:
  8DDEB6F30DE40E68573678B
- materially different machine code in SPI-related modules

Build environments:
- working 7.2.8-1:
  Clang/LLVM/LLD 22.1.8 + ThinLTO
- failing 7.2.8-2:
  Clang/LLVM/LLD 23.1.1 + ThinLTO
- local config differences are primarily compiler-version-derived plus
  CONFIG_WARN_CONTEXT_ANALYSIS on the newer build

The exact same rel71 libfprint binary:
- fails/degrades to 3-4/7 on 7.2.8-2 even after validated GPIO264 + spidev recovery
- passes normal lock at 7/7 on 7.2.8-1
- passes deep S3 at 15/7 on 7.2.8-1

This strongly implicates the kernel build/runtime boundary, but does not prove a
specific LLVM23 miscompile.

A focused disassembly comparison of pxa2xx_spi_transfer_one found only a small
LLVM22->LLVM23 code-generation delta (load scheduling / branch offsets), not a
clear semantic source-level change. Do not claim one specific instruction is the
root cause.

## Rejected transport hypothesis

Do NOT remove the current <=4096-byte spidev image-body chunking.

Exact-target research already establishes:
- the image arrives as one ~10602-byte transport/TLS record
- Linux spidev default bufsiz is 4096
- the exact GXFP51A0 reference requires reading the 4-byte header, then the
  announced body in <=4096-byte chunks
- current live spidev bufsiz=4096
- current driver SPI speed is already conservative at 1 MHz

Therefore a one-transfer 10602-byte userspace SPI read is not the right fix under
the current spidev transport.

## Official GCC/no-LTO kernel installed side-by-side

Installed:
- linux-cachyos-gcc 7.2.8-1
- linux-cachyos-gcc-headers 7.2.8-1

Package SHA256:
- linux-cachyos-gcc:
  887857551c5dfaeada8516879f0ac329d14fb271a089af71f79d4415b556fade
- headers:
  87c779c720620dc5e0bd735c5801f8ac19af0e3bfb57bb7cd3785261060325d4

Package integrity:
- kernel: 7728 files, 0 modified
- headers: 21861 files, 0 modified

Build identity:
- GCC 16.2.1
- CONFIG_CC_IS_GCC=y
- CONFIG_GCC_VERSION=160201
- CONFIG_CLANG_VERSION=0
- CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3=y
- CONFIG_LTO_NONE=y

spi-pxa2xx-core:
- srcversion:
  8DDEB6F30DE40E68573678B
- vermagic:
  7.2.8-1-cachyos-gcc SMP preempt mod_unload
- executable .text SHA256:
  9936e27005c467c3395a08db4a0e75d599adf12810a2b1ad536f48488eea9f8f
- .text size: 10718 bytes

Comparison:
- LLVM22 working .text:
  5911c0ec474f6240202be32b08acf3f711e65289962ac71b3673c84afb366608
- LLVM23 failing .text:
  60a3a25de9138aa3ef587abdab7e0a96c598374b1336f64c71be7e206fe2660c
- GCC candidate .text:
  9936e27005c467c3395a08db4a0e75d599adf12810a2b1ad536f48488eea9f8f

This is the same PXA2xx source compiled three ways.

## Boot readiness

NVIDIA DKMS:
- 580.178.04 installed for 7.2.8-1-cachyos
- 580.178.04 installed for 7.2.8-1-cachyos-gcc
- 580.178.04 installed for 6.18.52-1-cachyos-lts

GCC boot artifacts:
- /boot/105601e6e894462db74efab9ce733189/linux-cachyos-gcc/vmlinuz
  SHA256 fe3521d40617ebd6636d7395c348dc876815e11a8183db5944a74e991388758f
- /boot/105601e6e894462db74efab9ce733189/linux-cachyos-gcc/initramfs
  SHA256 d36d45608c77748fbf452260af230d04fffdc0827d85179ee0be249a90f7245a

Limine tree:
- CachyOS
  - linux-cachyos
  - linux-cachyos-gcc
  - linux-cachyos-lts
  - Snapshots

Current runtime has NOT changed:
- uname -r = 7.2.8-1-cachyos
- rel71/fprintd hashes unchanged
- fprintd active
- zero failed units

Limine configuration still has:
- default_entry: 2
- remember_last_entry: yes

Do not remotely alter default_entry / remembered boot state.
There is no supported one-shot selection in the installed limine-entry-tool.
The GCC kernel must be selected explicitly by the user from the Limine menu for
the controlled test.

## Temporary package hold

Until the experiment is complete:
  IgnorePkg = linux-cachyos linux-cachyos-headers linux-cachyos-gcc linux-cachyos-gcc-headers

Backups:
- /etc/pacman.conf.gxfp-pretest-20261003
- /etc/pacman.conf.gxfp-gcc-pretest-20261003

Remove these holds after the final kernel decision.

## External-current research context

Current CachyOS documentation describes:
- main linux-cachyos: Clang + ThinLTO
- GCC/no-LTO alternatives are officially supported
- recent community measurements on the same 7.2.x family show meaningful runtime
  differences between stock Clang/ThinLTO and GCC/no-LTO builds, though that case
  concerns module loading, not Goodix/PXA2xx
- no current public report was found that directly identifies an LLVM23 PXA2xx
  or GXFP51A0 regression matching Pegasus

This supports testing the official GCC variant but is not proof of the cause.

## Next human gate

No reboot is required until the user chooses to run this experiment.

When ready:
1. user manually reboots
2. in Limine select:
   CachyOS -> linux-cachyos-gcc
3. after boot, verify:
   uname -r == 7.2.8-1-cachyos-gcc
4. verify exact rel71 + stock fprintd hashes are unchanged
5. BEFORE any suspend, user performs exactly one normal graphical lock
6. inspect ACK/TLS/READY/DETECTED_HOLD/GET_IMAGE/score/unlock
7. if normal lock PASS, user performs exactly one genuine deep S3
8. inspect resume->READY and first accepted score

Interpretation:
- GCC PASS on lock + S3:
  official GCC/no-LTO kernel is a practical current mitigation and strongly
  narrows the regression to the Clang/ThinLTO build path; keep working LLVM22
  baseline as fallback until newer Clang kernels are retested.
- GCC FAIL:
  compiler/LTO alone does not explain the boundary; keep 7.2.8-1 control and
  continue kernel-side isolation without touching rel71.
