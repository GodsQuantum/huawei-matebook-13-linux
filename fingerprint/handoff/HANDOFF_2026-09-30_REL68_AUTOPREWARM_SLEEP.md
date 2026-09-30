# HANDOFF — rel68 automatic prewarm/sleep

Date: 2026-09-30
Machine: Pegasus uniquement
Branch: fingerprint-rel68-autoprewarm-sleep
Base driver: rel67 (S3/capture path unchanged)

## Why rel67 human S3 failed

Observed rel67 test:
- fprintd had deactivated at 23:15:14
- PM suspend entry 23:18:16.523
- PM suspend exit 23:18:50.728
- there was NO REL67/REL66 SLEEP 0x60 ACK before that suspend
- post-resume scores remained 3–4/7.

Therefore rel67's 400 ms close-time quiesce was not involved before S3:
the sensor had not been opened/closed at all after package restart.

Contrast with the validated rel66 S3:
- a one-shot prewarm had previously completed
- SLEEP 0x60 ACK existed before S3
- deep S3 then unlocked on first image at 7/7
- resume->READY ~4.434 s.

Live proof before rel68 coding:
- manually running /usr/libexec/gxfp51a0-boot-prewarm
- produced REL67_TRACE SLEEP 0x60 ACK at 23:24:58.299
- helper completed at 23:24:58.305.

## rel68 change

No driver changes relative to rel67.
No matcher, threshold, templates, TLS, GPIO, S3 or KDE/PAM changes.

Packaging lifecycle only:
- gxfp51a0-boot-prewarm.service remains a Type=oneshot
- WantedBy=graphical.target
- package post_install/post_upgrade:
  1. systemctl enable gxfp51a0-boot-prewarm.service
  2. synchronous systemctl restart fprintd.service
  3. systemctl start gxfp51a0-boot-prewarm.service
- one-shot Claim then D-Bus client exit causes Release/Close
- Close uses rel67 Windows-style quiesce then SLEEP 0x60 ACK
- service exits; no periodic activity remains
- pre_remove disables the one-shot cleanly.

Important:
- no package-owned vendor wants symlink is installed;
- enablement is explicit under systemd so is-enabled is truthful;
- no system-sleep hook, heartbeat or periodic keepalive.

## Validation

PASS:
- full research suite
- boot binding
- boot-prewarm source safety
- sleep lifecycle safety
- native S3 lifecycle
- GQ-SIGFM
- dual auth / KScreen
- git diff --check
- full reproducible Meson/Ninja build
- source manifest
- artifact gates
- release biometric dump absent.

Package:
libfprint-goodix51a0-1.94.100.goodix51a0-68-x86_64.pkg.tar.zst
SHA256:
dc4e28f032d4dd2c5844ed49522bee56327bd473979bf8abc34e5fba3feac32e

Package .INSTALL verified to contain:
- enable boot-prewarm
- synchronous restart fprintd
- start boot-prewarm
- disable --now on removal.

## Human gate

After rel68 installation, package itself must leave a SLEEP ACK in journal.
Then a deep S3 can be tested directly, without first doing a fingerprint lock/unlock.
Expected outcome: preserve rel66 human baseline behavior, >=7 first usable match.
