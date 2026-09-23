# GXFP51A0 rel33 — cold-boot prewarm

Date: 2026-09-23
Branch: fingerprint-rel33-coldboot-prewarm

## Trigger

rel32 passed direct lock authentication with one immediate right-index press.
The first rel32 cold-boot login test failed and required the password.

The boot journal proved the display-manager ordering itself was already correct:
- fprintd active: 10:27:45 CEST
- Plasma Login Manager active: 10:27:49 CEST
- greeter auto-login request/PAM start: 10:27:52 CEST
- first fingerprint prompt: 10:27:57 CEST
- fingerprint timeout: 10:28:09 CEST

Therefore the ~5 second delay was the sensor's first real Claim/open/TLS/
background/FDT preparation happening inside the first PAM attempt, not fprintd
starting too late and not a missing PAM rule.

## rel33 architecture

rel33 leaves rel32 driver, matcher, enrollments, lockscreen integration and
Plasma Login Manager compatibility package unchanged.

New package-owned components:
- /usr/libexec/gxfp51a0-boot-prewarm
- /usr/lib/systemd/system/gxfp51a0-boot-prewarm.service
- graphical.target.wants/gxfp51a0-boot-prewarm.service

Unit ordering:
- Requires=fprintd.service
- After=fprintd.service
- Before=display-manager.service
- WantedBy=graphical.target

The helper:
- confirms GXFP51A0 hardware is present;
- waits at most 5 seconds for fprintd GetDefaultDevice;
- performs only a bounded Claim (45s max);
- never calls VerifyStart or EnrollStart;
- logs failure but returns success so a broken fingerprint reader can never
  block password login indefinitely.

## Validation before next reboot

Source/safety:
- test_boot_prewarm_source_safety: PASS
- full verify-software-baseline.sh: PASS
- reproducible libfprint v1.94.100 build: PASS
- active sensor I/O during software baseline: NONE
- GPIO/MMIO writes during software baseline: NONE
- firmware actions during software baseline: NONE

Installed system:
- libfprint-goodix51a0 1.94.100.goodix51a0-33 installed without reboot
- graphical.target wants boot-prewarm
- systemctl show boot-prewarm reports Before=plasmalogin.service
- systemctl show plasmalogin reports After=gxfp51a0-boot-prewarm.service
- no dependency cycle was found; systemd-analyze verify's only nonzero output
  was inability to render plasmalogin man pages.

Controlled cold-state simulation:
1. stopped warm-keepalive timer;
2. restarted fprintd to discard in-process warm state;
3. started gxfp51a0-boot-prewarm.service;
4. completed in 4703 ms;
5. service Result=success;
6. journal: "cold-boot fprintd Claim completed; sensor ready before display manager";
7. warm-keepalive timer restored active;
8. a following fprintd-verify immediately reached "Verify started!" /
   "Verifying: right-index-finger" and waited for the finger.

## Next human test

Cold reboot only after rel33 repo/kit cleanup is complete:
- reboot Pegasus manually;
- at the first Plasma Login Manager screen, do not type a password;
- place the freshly enrolled right index immediately, without waiting for the
  fingerprint prompt and without mouse/keyboard activity;
- report whether login succeeds on one press.

Never reboot Pegasus automatically.
