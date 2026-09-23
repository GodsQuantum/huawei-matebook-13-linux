# GXFP51A0 rel35 — collision-free first login press

Date: 2026-09-23
Branch: fingerprint-rel35-login-first-press

## Trigger

The rel33 cold-boot human test failed even though boot-prewarm had completed.
Exact boot evidence:
- boot-prewarm completed successfully: 11:27:12.775 CEST;
- Plasma Login Manager started immediately after it;
- periodic warm keepalive started: 11:27:15.420;
- fingerprint PAM started: 11:27:16.110;
- keepalive Claim completed only at: 11:27:16.647;
- fingerprint cue appeared: 11:27:17.920;
- GET_IMAGE retried: 11:27:23.108;
- PLM reported fingerprint recognition failure: 11:27:24.049.

Two independent issues remained after rel34 fresh-handoff work.
## rel34 base retained

A concurrent rel34 commit f6f2ebf added a one-shot fresh warm handoff.
It was already installed on Pegasus before rel35 work:
- libfprint-goodix51a0 1.94.100.goodix51a0-34;
- immediate post-prewarm Verify reused the validated context at 88 ms;
- no redundant background GET_IMAGE occurred in the handoff interval;
- the normal full warm image validation still returns after the 10-second token expires.

rel35 does not change matcher, threshold, templates, capture recipe or the rel34
fresh-handoff driver logic.

## rel35 change 1 — no keepalive at greeter startup

Old timer:
- OnBootSec=20s
- OnUnitActiveSec=3min

New timer:
- OnActiveSec=3min
- OnUnitActiveSec=3min
- no OnBootSec

Boot-prewarm is now the only GXFP51A0 Claim before initial graphical login.
## rel35 change 2 — bounded three-try PAM

The old Plasma Login Manager PAM rule used:
  pam_fprintd.so max-tries=1 timeout=12

That made one placement false-rejection terminal.

Plasma Login Manager compatibility package 6.7.5-3.3 now uses:
  pam_fprintd.so max-tries=3 timeout=12

pam_fprintd documents three tries as its default. The 12-second overall login
window remains bounded; password fallback is not made indefinite.

## Validation before next reboot

Source/build:
- targeted rel34 fresh-handoff test: PASS
- boot-prewarm test: PASS
- warm-keepalive test: PASS
- KDE lockscreen integration test: PASS
- boot/login package regression test: PASS
- full verify-software-baseline.sh: PASS
- reproducible libfprint v1.94.100 build: PASS
- ACTIVE_SENSOR_IO/GPIO_WRITES/MMIO_WRITES/FIRMWARE_ACTIONS: NONE
Installed:
- libfprint-goodix51a0 1.94.100.goodix51a0-35
- plasma-login-manager 6.7.5-3.3
- driver package SHA256: b08d03e8da61cd798868ede1c92f466a2d47739467cff039acd8189785fa49c6
- PLM 3.3 package SHA256: b19c5c38381295aade25c5092902ecc97af0c1b52da3395cff1bf821f127a0fb
- fprintd 1.94.5-2.1
- /usr/lib/pam.d/plasmalogin contains max-tries=3 timeout=12
- installed keepalive timer has OnActiveSec=3min and no OnBootSec
- libfprint package integrity: 0 modified files
- Plasma Login Manager package integrity: 0 modified files
- all three enrollments remain present
- fprintd and keepalive timer active
- temporary PLM build dependencies removed after package creation

## Next human validation

Do not re-enroll.
Do not reboot automatically.

Arezki should manually reboot Pegasus, then at the first Plasma Login Manager
screen place the fresh right index immediately without mouse/keyboard input.
If the first placement is rejected, keep using the fingerprint window: rel35 now
allows up to three PAM attempts within the bounded 12-second transaction.
