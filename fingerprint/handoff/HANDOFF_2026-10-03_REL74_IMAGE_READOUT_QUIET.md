# HANDOFF — GXFP51A0 rel74 image-readout quiet candidate — 2026-10-03

## Why rel74 exists

rel73 made transport deadlines Windows-tolerant but did not yet receive a
human post-READY biometric gate. During review against 2026 hardware-validated
Goodix SPI work, a more fundamental capture hazard was found.

The current GXFP51A0 synchronous GET_IMAGE path could:
1. receive the cleartext GET_IMAGE ACK;
2. wait only 5 ms;
3. clock SPI again while looking for the TLS image.

Recent Chicago/ST411 work proves that after image-setmode ACK the sensor spends
about 73 ms reading the analog array into its buffer. Windows remains silent on
SPI during that window. Repeated SPI reads while IRQ is asserted but the packet
is not ready can truncate/corrupt the image (documented row-cliff failure).

This maps directly to Pegasus symptoms:
- strong FDT/touch detection
- valid TLS images
- matcher scores only 3–4/7
- increased sensitivity after kernel/controller code-generation changes

## rel74 delta over rel73

No matcher, template, enrollment, GPIO, PMK, TLS, OTP or S3 lifecycle change.

Only capture transport:
- after a successful GET_IMAGE ACK, hold SPI completely quiet for 80 ms
- do not continue hunting TLS inside the command drain after that ACK
- the TLS record is consumed afterward by the existing bounded frame reader
- if IRQ is high but a read returns no packet, back off 3 ms before reading again
- same 3 ms empty-read backoff in gx_take_tls_frame() and gx_bio_recv()
- accepted-GET_IMAGE no-replay rule from rel48 remains mandatory

Constants:
- GX_IMAGE_READOUT_SETTLE_US = 80000
- GX_IRQ_HIGH_EMPTY_BACKOFF_US = 3000

## Research basis

berkekbgz/libfprint-goodix-spi:
- gdix51c0_capture_image_raw() suppresses all listener SPI access for 80 ms
  immediately after the image-setmode ACK
- comment records ~73 ms analog row-by-row readout and image corruption from
  SPI traffic during that interval
- async listener also backs off on IRQ-high empty reads

szlukabence/goodix-fingerprint-spi-linux:
- Windows WBDI transcript for GF_ST411SEC_APP_14115 shows image command 0x20
  ACK first, then the 10602-byte TLS image record later

This candidate preserves the known-good rel48/50/59/60/61 lineage and rel73's
1-second Windows-compatible ACK/response deadlines.

## Gates

- new test_image_readout_quiet_source_safety: PASS
- full fingerprint/research make test: PASS
- SOURCE_MANIFEST: PASS
- libfprint build: PASS
- release biometric dump hook: absent
- ACTIVE_SENSOR_IO=NONE during build
- GPIO_WRITES=NONE during build
- MMIO_WRITES=NONE during build
- FIRMWARE_ACTIONS=NONE during build

Package:
- libfprint-goodix51a0 1.94.100.goodix51a0-74
- SHA256:
  255c6b7c12a918ab4cd4e502f3b188599138532febaf7fa903468eee982466fe

Human gate required before any S3 work:
- direct verify or normal lock
- genuine DETECTED_HOLD
- require real image score >=7 and successful authentication
- compare image transport retry count and timing against rel59/60/61

## Full qualification pass — 2026-10-03

### Human-validated lineage recovered from project history

The candidate is not based on “latest release wins”. The following real human
successes are the useful lineage:

| Release | Human result | Measured evidence | Keep / lesson |
| --- | --- | --- | --- |
| rel40 | cold graphical login PASS | first pose 2/3/3, next same-press image reached 7/7 | WakeupMCU + Identify + same-press can recover |
| rel44 | one cold login PASS | first biometric image 11/7 | retry-calibrated capture can produce strong first image |
| rel45 | cold login PASS | hardware FDT 5 zones; first biometric image 7/7 | hardware touch bitmap + clean-background protection are correct |
| rel48 | cold login PASS | first real image 23/7; one safe no-evidence GET_IMAGE retry | accepted GET_IMAGE must never be replayed |
| rel48/49 gate | genuine deep S3 PASS | first actual captured post-resume image 11/7; no TLS/GCM error | rel48 cold recovery is a proven S3-quality baseline |
| rel50 | normal lock PASS | pose 1 = 4/4/4; pose 2 first image = 15/7; READY ~8.77 s | retain full same-press budget and reposition |
| rel51 | normal lock PASS | one pose, first captured image 13/7; greeter -> READY ~4.17 s; warm rebase ~1.75 s | validated awake warm-context reuse |
| rel56 | clean reboot login PASS | same physical press 4 -> 6 -> 7; post-S3 immediately collapsed to <=4/7 | proves S3 hardware state, not templates, caused that regression |
| rel59 | normal lock PASS | READY ~6.1 s; same-press 5 -> 6 -> 7; 90 ms retry barrier | apply retry-assisted pacing before the next same-press frame |
| rel59 | deep S3 PASS | resume -> READY ~7.8 s; successful image 8/7 | fast S3 recovery can work without lowering threshold |
| rel60 | normal lock PASS | READY ~6.84 s; first actual image 9/7 | MCU rearm after a failed usable pose is valuable |
| rel61 | genuine deep S3 PASS | resume -> READY ~21.5 s; first true post-READY image 20/7; unlock | strongest quality proof for fresh cold Claim/Open + PAM resume rearm |
| rel66 | conditional deep-S3 PASS | when sensor had really been parked before S3: READY +4.434 s, first image 7/7, unlock | Windows 0x60 park is useful only at the real sleep boundary; ordinary Close must not use it |

Rejected lessons retained:
- rel62–64 fast-resume/reconditioning: repeatedly degraded to 3–4/7.
- rel68/69 ordinary-Close 0x60 sleep: weakened normal captures; do not restore it.
- persistent timing learning, heartbeat/keepalive and external system-sleep hooks remain absent.
- SIGFM threshold remains 7.
- enrollment/templates remain unchanged.

### External research reconciled with the lineage

Current hardware-validated ChicagoHS reverse engineering
(`berkekbgz/libfprint-goodix-spi`, `re/PARITY.md`) independently establishes
the Windows transport contract used by rel73:
- 1 ms pre-submit guard;
- non-zero ACK/data deadlines below 1000 ms become 1 s;
- one complete-command retry on missing ACK / required response;
- exact-length reads;
- post-TLS D4 is mandatory;
- image/FDT transport uses long enough bounded windows.

The same parity work documents official calibration/ImageBase behavior and warns
that wrong DAC/calibration produces low-quality captures. This remains the next
investigation area only if rel74 delivers transport-clean frames that still score
below threshold.

`szlukabence/goodix-fingerprint-spi-linux` identifies this exact
GXFP51A0 / chip 0x2504 / ChicagoHS / STM32F411 /
`GF_ST411SEC_APP_14115` family and points to the GodsQuantum driver as the
working native libfprint implementation for MateBook 13.

Current upstream libfprint documentation also confirms:
- suspend/resume are paired lifecycle operations;
- `FP_DEVICE_ERROR_NOT_SUPPORTED` is an accepted suspend result;
- an error from the internal suspend completion cancels an ongoing action.
The patched fprintd manager already treats NOT_SUPPORTED as expected.

### rel74 software gates on the current source

Targeted tests PASS:
- Windows transport parity
- image-readout quiet window
- target ACK timeout
- FDT retry
- GET_IMAGE retry
- capture no-reply timeout
- same-press Verify + Identify
- retry-pose MCU rearm
- native resume recovery
- sleep lifecycle

Full `make -C fingerprint/research test`: PASS.

Release/build gates:
- SOURCE_MANIFEST=PASS
- LIBFPRINT_PATCH=PASS
- MESON_CONFIGURE=PASS
- LIBFPRINT_BUILD=PASS
- GOODIX51A0 object/ACPI/archive/type/Identify gates=PASS
- FASTBRIEF/RANSAC matcher present
- release biometric dump hook=ABSENT
- ACTIVE_SENSOR_IO=NONE during build
- GPIO_WRITES=NONE during build
- MMIO_WRITES=NONE during build
- FIRMWARE_ACTIONS=NONE during build

Canonical rel74 rebuild:
- package container SHA256:
  `5e116fb4cccd7218657db3e99fe41219d357bea00a8fdb6936a4acfdb2cf8b9c`
- payload / installed `libfprint-2.so.2.0.0` SHA256:
  `7c21497018438b7780803575fcaac99a680f8cc32d5f6c299e6e020a82c9f8d8`
- rebuilt payload is bit-identical to the live installed library.
- the earlier package SHA recorded above refers to an earlier package container;
  package metadata is not the runtime identity. The payload SHA above is the
  authoritative runtime identity.

### fprintd S3-open lifecycle qualification

Candidate package:
- fprintd 1.94.5-73
- package SHA256:
  `102e024fe22d9d34952fb752e8011225d62d492f3cde5cdad38dc7e546d9cca6`
- live / package payload `/usr/lib/fprintd` SHA256:
  `3145f89a59127e96fec6a64f4330ee0470f8959a3a8b9ba3dabcff1293064b10`

Clean-path test result:
- 35/36 fprintd tests PASS.
- all PAM tests PASS.
- the only failure is the daemon Python test because the deliberately
  non-introspection libfprint build does not expose GI namespace `FPrint 2.0`.
- running the same suite from the canonical project path makes pam_wrapper
  truncate at the spaces in `Capteur Empreinte Huawei`; this is a test-harness
  path limitation, not a runtime PAM failure.

Installed live stack after qualification:
- libfprint-goodix51a0 1.94.100.goodix51a0-74
- fprintd 1.94.5-73
- three enrollments intact
- package integrity: zero modified files
- D-Bus idle: finger-needed=false, finger-present=false
- zero failed systemd units

S3 lifecycle:
1. fprintd receives PrepareForSleep.
2. if the exact goodix51a0 device is idle/closed, fprintd opens it.
3. rel74 prepares a real production-ready context.
4. driver suspend sends Windows SLEEP `0x60 / 01 00` and requires its ACK.
5. transport is closed and host TLS/FDT state is invalidated.
6. deep S3 occurs.
7. after resume fprintd completes resume and closes the temporary-open device.
8. the next PAM Claim gets a fresh cold Open rather than stale post-S3 state.

No Windows SLEEP is sent on ordinary device Close.

### Current cross-distro source matrix

The exact rel74 source was rebuilt in isolated containers on 2026-10-03:

| Environment | Result |
| --- | --- |
| CachyOS / Arch host | PASS; native package and exact live payload reproduced |
| Debian stable / glibc | BUILD_ONLY=PASS |
| Fedora current / glibc | BUILD_ONLY=PASS; fprintd relocation ABI PASS; lib64 discovered dynamically |
| openSUSE Tumbleweed / glibc | BUILD_ONLY=PASS; fprintd relocation ABI PASS; minimal-image pam_pwquality warning is unrelated |
| Alpine edge / musl | BUILD_ONLY=PASS |

Therefore the current candidate is distro-portable across the five major package
families tested. This does NOT mean every laptop with a Goodix sensor is already
hardware-supported: GXFP51A0 board GPIO/reset/IRQ integration still needs a
validated device profile on hardware other than the MateBook target.

### Current kernel discriminator

Pegasus is still RUNNING `7.2.8-2-cachyos`, the kernel build that showed the
new ACK/timing sensitivity. The rel74 normal-lock gate therefore tests the
candidate against the harder environment directly.

`7.2.8-1` is prepared on disk only for a later user-chosen A/B maintenance
window. No reboot is required for the next rel74 tests.

## Next physical gates — do not reorder

1. ONE user-triggered normal graphical lock; no S3 first.
2. Fingerprint normally.
3. Read complete logs before any code change.
4. PASS requires genuine score >=7 and actual unlock, while recording:
   - greeter -> READY
   - target-ACK retries / timing scale
   - GET_IMAGE retry count
   - 80 ms readout-quiet path
   - all genuine scores.
5. Only if normal lock passes: ONE user-triggered deep S3.
6. On resume, wait for the lock UI/fingerprint readiness, then use an enrolled finger.
7. Read logs for S3_PARK ACK, fresh post-resume Claim/Open, READY, scores and unlock.

No reboot, re-enrollment, threshold change or new release before those gates.
