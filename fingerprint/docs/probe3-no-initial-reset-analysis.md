# Probe #3 analysis — no unconditional initial reset

Date: 2026-08-30

This note records the current reasoning boundary for the next GXFP51A0/GF3658 Milan experiment. It contains only sanitized technical information. No proprietary binary, firmware image, raw disassembly dump, local account name, or private filesystem path belongs here.

## Canonical baseline before this documentation update

Code baseline: `10f0cb97cd8199e1acdc827ee536179c768576c1` — `research: model DriverState ACK retry and reset`.

The first supervised live probe was negative but bounded: Linux controller submissions succeeded, GPIO48 remained LOW, the exact-length RX path performed no reads while readiness was absent, A/4 reached its allowed ACK timeout/retransmission behavior, cleanup restored GPIO264 LOW, and no firmware operation occurred.

Follow-up static analysis corrected DriverState:Install to use generic B/0 ACK bookkeeping for packed command `0x96`, an effective 1000 ms ACK window, one exact retransmission per transport wrapper call, at most two wrapper calls, and `HardResetMcu` only after both wrapper calls fail.

## New startup-order correction

The reset primitive itself remains proven for HardwareID 3:

```text
GPIO264 HIGH 10 ms -> LOW 100 ms -> final LOW
```

What changed is **where that reset is justified**.

Static control-flow review does not show an unconditional `HardResetMcu` in `MilanEvtDeviceD0Entry`. D0Entry clears lifecycle state and performs runtime/thread setup before initialization, but its direct call list does not contain the hard-reset helper.

A direct hard-reset call at `0x18000ea42` was found inside the initialization-thread function, not in D0Entry or PrepareHardware. That call is conditional: the per-attempt output/status value is tested first, and the reset is skipped when that value is zero. The surrounding retry loop is bounded by `retry_count_for_common_init`.

Therefore the previously used Linux **initial reset before DriverState** is a proven reset primitive but is no longer a proven step of the normal Windows startup path. Keeping it at probe entry changes device state before the path being reproduced.

### Consequence

Probe #3 should remove only the unconditional initial reset. It must preserve:

- the Windows-faithful DriverState ACK/retry logic;
- DriverState's own conditional hard-reset fallback after both wrapper calls fail;
- one logical `GetEvkVersion` attempt with deterministic Linux A/4 fixture `00 00`;
- exact-length RX and immediate terminal stop on `FF FF FF FF`;
- at most one A/4 retransmission after its first ACK timeout;
- unconditional final cleanup using the proven GPIO264 reset;
- the independent supervisor and GPIO264-only restore fail-safe.

This is a one-variable change relative to the corrected DriverState model.

## Probe #3 off-hardware gate

The target-side offline patch was reported with SHA-256:

`6d9f26183aa471ac569f845fcf20eace50fbab4e6b0344e82aed2285c1d3cebd`

The patch scope is seven research files:

```text
research/linux/live_probe_supervisor.sh
research/linux/probe_runtime.c
research/probe_harness.c
research/probe_harness.h
research/tests/test_live_probe_supervisor.sh
research/tests/test_probe_harness.c
research/tests/test_probe_runtime_source_safety.sh
```

Its intended invariants are:

```text
INITIAL_RESET=NO
DRIVERSTATE_FALLBACK_RESET=PRESERVED
FINAL_CLEANUP_RESET=PRESERVED
DRIVERSTATE_ACK_TARGET=96
DRIVERSTATE_ACK_TIMEOUT_MS=1000
DRIVERSTATE_WRAPPER_CALLS=2
DRIVERSTATE_SENDS_PER_WRAPPER=2
DRIVERSTATE_MAX_INSTALL_SENDS=4
A4_FIXTURE=0000
SUPERVISOR_TOKEN=GXFP51A0_REVIEWED_PROBE_3
SUPERVISOR_TIMEOUT=12S
```

The submitted gate log reports successful GCC tests, Clang + ASan/UBSan tests, GCC `-fanalyzer`, and build/link of the real probe, reset-restore helper and passive preflight against libgpiod 2.3.1. It also records that none of those real binaries were executed and that no SPI bind/open/transfer, GPIO request/write, reset, pinmux write or firmware action occurred during the gate.

### Important gate defect: privacy result is invalid

The same gate log shows the privacy `grep` commands failing because the local project path contained a shell metacharacter and was not preserved correctly by the audit command. The script then printed `PRIVACY_AUDIT=OK` despite those failed scans.

Treat the probe #3 gate as follows:

- compiler/test/build evidence: usable;
- behavioral/source invariants: usable;
- `PRIVACY_AUDIT=OK`: **invalid for this gate and must be re-run with correct quoting**.

A direct search of the current GitHub tree found no matches for the known local username, common absolute home-directory markers, the local project-root fragment, or the local workstation-project fragment. That is a current-tree sanity check only; it is not an assertion of absolute historical Git-object erasure.

## Pinmux conclusion

The primary GSPI1 signal pads used for CS/CLK/MISO/MOSI were observed in their native SPI mode, and controller submissions completed without Linux-side transfer errors. The main SPI pinmux is therefore not the leading explanation for the silent device.

The Cannon Lake-LP clock-loopback pad remains an unresolved difference: the upstream pinctrl definition includes an additional loopback pad for the SPI group, while the observed firmware state leaves that pad as locked GPIO. The running kernel's debug representation does not make this discrepancy sufficient evidence of a fault. The pad is firmware full-locked, so no experiment should alter it without much stronger platform-specific proof.

## Experimental design consequence: fresh boot is mandatory

A no-initial-reset experiment is only diagnostically clean if the sensor has not already been deliberately reset earlier in the same boot.

The cleanup from every prior active experiment intentionally performs the proven GPIO264 reset. Re-running probe #3 after such a cleanup would no longer test the natural startup state that motivated removing the initial reset.

Therefore the next hardware experiment, if authorized after publication and final review, must be:

1. start from a fresh/cold boot with no prior fingerprint protocol or GPIO264 operation in that boot;
2. perform only passive identity/state checks needed to prove the target and ownership assumptions;
3. run the supervised probe #3 exactly once;
4. never invoke `gxfp-live-probe` directly;
5. allow only the built-in DriverState and A/4 retransmission rules already modeled;
6. stop on the first terminal/fatal RX condition;
7. always execute final cleanup/reset and restore spidev/module state;
8. do not repeat the probe in the same boot to obtain a second sample.

The cleanup reset is still mandatory for safety even though it means the experiment cannot be repeated in the same boot under the same initial-state hypothesis.

## Not authorized

Probe #3 does **not** authorize:

- firmware flashing, UPFW, erase, bootloader or firmware-management paths;
- the full three-attempt common-init + hard-reset + final-attempt sequence;
- pinmux writes or IRQ-trigger reconfiguration;
- enrollment or image capture;
- libfprint integration;
- blind reuse of USB Goodix firmware flows;
- repeated live probes in one boot.

## Next gate

Before any new hardware action:

1. fix/re-run the privacy audit so paths containing shell metacharacters are handled safely;
2. publish the exact seven-file no-initial-reset model only after the corrected gate is green;
3. review the final fresh-boot one-shot command path against the canonical commit;
4. then perform at most one supervised probe #3 on a fresh boot.

Until those steps are complete, the correct state is: **no live probe authorized yet**.
