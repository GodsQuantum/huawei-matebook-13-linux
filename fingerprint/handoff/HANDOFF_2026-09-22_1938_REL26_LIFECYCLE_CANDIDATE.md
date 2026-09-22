# Handoff — rel26 lifecycle / Claim-time recovery candidate

Updated: 2026-09-22 19:38 CEST.

## Cold-boot rel25 evidence

Arezki manually rebooted Pegasus with rel25 installed and tried right-index then
right-middle at the fresh Plasma Login Manager greeter. Neither authenticated;
password login was required.

The boot journal proves this was not an enrollment/matcher failure. Before the
first human finger press, rel25 probe-time prewarm had already failed:
- GET_IMAGE ACK arrived but the TLS image timed out;
- the retry returned no authenticated TLS image;
- capture transport was marked desynchronised;
- `cannot decrypt the image record (-1 raw bytes)` followed.

All three existing enrollments remained visible:
left-index, right-middle, right-index. Do not re-enroll on this evidence.
## External research incorporated on 2026-09-22

Issue #6 contributor szlukabence tested rel24-rc1 on MateBook 13 2020 ST411/14115:
20/20 fresh enrollment succeeded, existing template-v4 enrollment survived,
about 35 captures remained stable, and no daemon restart was needed.

The same contributor documented stale warm TLS/FDT state across suspend/resume
with fprintd --no-timeout. fprintd 1.94.5 on Pegasus already subscribes to
logind PrepareForSleep and invokes libfprint suspend/resume.

The current GDIX51C0 driver for the same 0x2504 / ChicagoHS silicon implements
native suspend/resume and explicit cold boundaries. It also documents that an
idle libfprint device may miss the driver suspend callback, motivating a
Claim-time sleep-boundary fallback.

No more mature upstream/mainline GXFP51A0 implementation was found as of
2026-09-22. OpenGoodixSPI remains experimental.
## rel26 design

Branch: fingerprint-rel26-lifecycle-recovery
Base: rel25 candidate commit 2cf8f88.

rel26 deliberately leaves biometric policy unchanged:
template v4 / SIGFM v3, threshold 7, 20 enrollment views, three verify presses,
no firmware writes and no GPIO112/GPP_D16 access.

Transport/lifecycle changes:
- libfprint probe() is host-transport-only; it performs no reset/TLS/GET_IMAGE/FDT;
- real open()/Claim owns deterministic reset plus bounded TLS/background/FDT preparation;
- failed cold preparation is propagated as FP_DEVICE_ERROR_PROTO instead of
  falsely completing open successfully;
- cold preparation uses the bounded whole-session recovery wrapper;
- native libfprint suspend/resume callbacks invalidate warm state;
- CLOCK_BOOTTIME - CLOCK_MONOTONIC detects sleep missed while the device was idle;
- stale warm TLS is abandoned host-side without sending close_notify to a sensor
  whose session may no longer exist.
## Validation completed

Full software baseline passed against libfprint v1.94.100:
- all research/unit/source-safety tests PASS;
- source manifest PASS;
- reproducible libfprint build PASS;
- no active sensor I/O during the software gate;
- no GPIO/MMIO/firmware writes during the software gate;
- release biometric dump hook absent.

Package built:
libfprint-goodix51a0 1.94.100.goodix51a0-26
SHA-256:
123c2ad057369d3ded4f242ddee87a8f59afaeae16b7170dee43920aa63b8671

Installed on Pegasus at 19:33 CEST. Snapper rollback pair: 876/877.
PLM remains 6.7.4-3.2; fprintd remains 1.94.5-2.1.
## First live rel26 result

After package install, fprintd restarted in about 0.8 s. Its startup journal had
ZERO GXFP51A0 sensor-protocol traffic: no A8, TLS, GET_IMAGE, FDT or prewarm.
fprintd-list also listed all three enrollments without sensor-protocol I/O.

A direct `fprintd-verify -f right-index-finger arezki` then performed the first
real Claim. It reached `Verify started!` without a TLS/GET_IMAGE terminal
failure and waited for finger presence. No human press occurred during that
terminal test; it was cancelled and left no client/worker behind.

This proves the invasive pre-greeter regression is removed and the real Claim
can prepare the device far enough to enter verification even in the boot that
rel25 had previously desynchronised.

## Next human validation

No re-enrollment yet.

First do a KDE logout without reboot and authenticate with the existing
right-index finger. If that works, manually reboot Pegasus and repeat at the
first greeter to validate rel26 from a truly clean boot. The assistant must
never reboot Pegasus.

Only if transport is healthy and genuine captures reach the matcher but the
existing templates consistently score below threshold should re-enrollment be
considered. At that point re-enroll one finger first, not all three.
