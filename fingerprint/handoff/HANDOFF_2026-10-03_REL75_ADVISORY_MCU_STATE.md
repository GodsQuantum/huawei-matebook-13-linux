# HANDOFF — GXFP51A0 rel75 advisory MCU-state capture — 2026-10-03

## Trigger

rel74 normal graphical lock failed on kernel 7.2.8-2-cachyos:
- strong touch detection: touch=0x3f, 6 zones, mean=235, drop=117
- clean-looking FDT baseline: floor=329 (~idle 353)
- immediately before GET_IMAGE, command 0xae/GetMcuState received 0/2 replies
- rel73 generalized transport policy replayed the whole 0xae command
- GET_IMAGE then needed its bounded no-evidence retry
- SIGFM scores were 3/7, 4/7, 3/7

Raw evidence and SHA are preserved in the rel74 handoff.

## Exact-target research

The local Windows GXFP51A0 / GF_ST411SEC_APP_14115 WBDI transcript confirms:
- GetMcuState 0xae has two replies when used: B0 ACK, then AE state data
- real finger GET_IMAGE uses command 0x20
- the real finger capture transcript around FDT-down -> image does not show a
  fresh 0xae replay immediately before image

Do NOT port GDIX51C0 initial-image 0x22 to this target.

Human-validated rel40 through rel61 already used the historical recipe containing
0xae, so rel75 does NOT delete GetMcuState. The narrower regression is transport
policy:
- rel61 expected two AE responses
- rel61 did not replay a non-image capture command if those responses were missed
- rel73 generalized whole-command replay to AE
- rel74 failure exercised that new replay directly before the low-score image

## rel75 delta over rel74

Only 0xae/GetMcuState behavior inside gx_send_plain_drain changes:
- still expects 2 replies when available
- no-reply window restored to 120 ms for this observational query
- attempts is forced to 1 for 0xae
- 0/2 or 1/2 is logged as an advisory incomplete observation
- capture continues without replaying 0xae

Unchanged:
- GET_IMAGE retries and accepted-command no-replay safety
- 80 ms image readout SPI-quiet window
- 1-second target/FDT transport windows
- FDT retry behavior
- same-press capture and pacing
- between-pose WakeupMCU rearm
- SIGFM matcher and threshold 7
- templates/enrollments
- OTP-derived calibration/DAC
- GPIO policy
- fprintd S3 pre-open boundary
- Windows SLEEP 0x60 only at real PrepareForSleep
- no ordinary-Close SLEEP
- no keepalive, persistent timing or external system-sleep hook

## Gates

New gate:
- test_mcu_state_advisory_source_safety: PASS

Full:
- make -C fingerprint/research test: PASS
- SOURCE_MANIFEST=PASS
- LIBFPRINT_PATCH=PASS
- MESON_CONFIGURE=PASS
- LIBFPRINT_BUILD=PASS
- release biometric dump hook absent
- active sensor I/O during build: NONE
- GPIO writes during build: NONE
- MMIO writes during build: NONE
- firmware actions during build: NONE

Package:
- libfprint-goodix51a0 1.94.100.goodix51a0-75
- package SHA256:
  71fd52a19ddc6567e95d544a7ee7f4d509bc1534a88eff15f8262a9476f32540
- payload libfprint-2.so.2.0.0 SHA256:
  001d022a997e04755240856d19b2b69a2875eeaa59b7b7c7d07057ff236c1469

Portability:
- rel75 changes only standard C control flow in the same driver source
- rel74 exact source already passed CachyOS/Arch, Debian, Fedora, openSUSE and Alpine/musl
- portable/source gates remain PASS

## Next physical gate

No reboot. No S3 first.
After install + fprintd restart:
1. one user-triggered normal graphical lock
2. one normal enrolled-finger attempt
3. inspect logs before any further code change
4. key discriminator:
   - if AE is missed, log must say advisory incomplete and MUST NOT say
     official-policy whole-command retry for cmd=ae
   - compare finger-detect -> GET_IMAGE latency and genuine scores with rel74
5. only a normal-lock PASS may proceed to deep S3.

## Live installation — 2026-10-03 14:36 CEST

Installed without reboot:
- running kernel: 7.2.8-2-cachyos
- libfprint-goodix51a0 1.94.100.goodix51a0-75
- live lib SHA256:
  001d022a997e04755240856d19b2b69a2875eeaa59b7b7c7d07057ff236c1469
- fprintd 1.94.5-73 unchanged
- live fprintd SHA256:
  3145f89a59127e96fec6a64f4330ee0470f8959a3a8b9ba3dabcff1293064b10
- fprintd restarted only; PID 315948
- three enrollments intact
- package integrity: zero modified files
- D-Bus idle after restart
- zero failed systemd units
- live library contains rel75 advisory-MCU-state marker

No lock, suspend, reboot, enrollment or threshold change was triggered by the assistant.

## Human gate — rel75 normal lock FAIL / no finger reaction — 2026-10-03 14:53-14:55 CEST

User result:
- rel75 lock échoué
- UI appeared not to react at all when the enrolled finger was placed repeatedly.

Exact evidence:
- rel75 live SHA remained 001d022a997e04755240856d19b2b69a2875eeaa59b7b7c7d07057ff236c1469
- fprintd-73 live SHA remained 3145f89a59127e96fec6a64f4330ee0470f8959a3a8b9ba3dabcff1293064b10
- first preparation: TLS miss 100 -> 150%, initial clear mean=201 below floor 340, accepted background GET_IMAGE then TLS image timeout, full session recovery requested
- retry preparation: TLS miss 150 -> 200%, FDT ACK miss 200 -> 250%, WakeupMCU completed
- Identify reached physical press 1/3 READY at 14:54:23.696998
- after READY there was no DETECTED_HOLD, no finger GET_IMAGE and no biometric score despite repeated physical placements
- therefore this failure occurred before the rel75-specific AE/GetMcuState behavior can execute

Raw evidence:
- fingerprint/handoff/evidence/REL75_LOCK_FAIL_NO_FINGER_DETECTION_2026-10-03_145359.log
- SHA256 fe51255ec762b7745fce01019831692bd8245b96803fc4c6ddc8025505e3d6a9

## External live hardware recovery — 2026-10-03 15:00 CEST

The already validated Pegasus live recovery primitive was executed before any code change:
1. D-Bus idle verified: finger-needed=false, finger-present=false
2. stopped fprintd
3. exact current-driver GPIO264 long reset only: HIGH 300 ms, LOW 600 ms, final LOW, PASS
4. unbound only spi-GXFP51A0:00 from spidev
5. rebound the same device to spidev
6. verified /dev/spidev1.0 recreated
7. restarted fprintd
8. deleted temporary minimal reset helper source/binary

No GPIO112, firmware action, PXA2xx host-controller rebind, reboot, suspend, template change, enrollment or matcher/threshold change occurred.

Post-recovery:
- kernel 7.2.8-2-cachyos unchanged
- libfprint-goodix51a0 rel75 unchanged
- live lib SHA unchanged: 001d022a997e04755240856d19b2b69a2875eeaa59b7b7c7d07057ff236c1469
- fprintd 1.94.5-73 unchanged
- new fprintd PID 319582
- spidev binding present
- zero failed systemd units

Next gate:
- exactly one normal lock on unchanged rel75 before any S3
- this must be the first real Claim/Open after external recovery
- if finger detection returns, compare transport and scores with rel74 and rel59-61
- if UI is still inert/no DETECTED_HOLD, inspect live FDT polling/baseline before any new release
