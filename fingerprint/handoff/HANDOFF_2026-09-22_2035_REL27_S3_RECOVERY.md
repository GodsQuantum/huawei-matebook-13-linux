# Handoff — rel27 first-S3 recovery

Updated: 2026-09-22 20:35 CEST.

## Human failure that triggered rel27

Pegasus entered idle S3 at 19:48:36 and resumed at 20:10:00 while rel26 and
the same fprintd process were still running. The user then tried fingerprint
unlock and authentication failed.

The journal proved a transport failure, not a matcher/enrollment failure:
- 20:10:12 GET_IMAGE no ACK/TLS;
- 20:10:16 ACK received but TLS image timed out;
- 20:10:21 retry had no TLS image, raw=-1;
- capture transport marked desynchronised;
- bounded context recovery then also failed.

All three template-v4 enrollments remained present.
## rel26 root cause

rel26 correctly moved all invasive sensor work out of libfprint probe() and
added Claim-time sleep detection using CLOCK_BOOTTIME - CLOCK_MONOTONIC.

However gx_warm_crossed_sleep() rejected the stored baseline whenever
warm_sleep_delta_us <= 0.

Before the first suspend of a boot, BOOTTIME-MONOTONIC is legitimately zero or
slightly negative because the two clocks are sampled sequentially. Therefore
the first idle S3 was not detected and stale TLS/FDT warm state was reused.

The absence of the driver suspend callback in this idle case is expected:
upstream libfprint documents the driver vfunc as an interactive-action hook.
## rel27 changes

Branch: fingerprint-rel27-s3-recovery.

- gx_sleep_delta_us now returns a boolean validity result plus an out value.
- warm_sleep_clock_valid is stored separately from the numeric baseline.
- zero/negative baselines are accepted.
- a >250 ms increase logs an explicit sleep-boundary message and forces cold reset.
- after an S3 boundary, unpersisted capture pacing is discarded and only the
  last successfully persisted pacing value is reloaded.
- active-action suspend now returns FP_DEVICE_ERROR_NOT_SUPPORTED, matching
  upstream libfprint semantics for hardware that cannot continue an action
  across S3; libfprint cancels the action before sleep.
- resume itself does not perform late cancellation.
- matcher/template policy is unchanged.
## Validation

Full software baseline PASS against libfprint v1.94.100.
All research/unit/source-safety tests PASS.
No active sensor I/O, GPIO write, MMIO write or firmware action occurred during
the software gate.

Built package:
libfprint-goodix51a0 1.94.100.goodix51a0-27
SHA-256:
4d9c63121bd433bfab9c24d713f2a44d28638e16950c9ed9338ce962b3bb7eb5

Installed on Pegasus at 20:31 CEST.
Snapper rollback pair: 879/880.
fprintd remains 1.94.5-2.1.
Plasma Login Manager remains 6.7.4-3.2.
## First live rel27 state

Package installation restarted fprintd. Startup again produced zero GXFP51A0
sensor-protocol traffic; enumeration/listing is passive.

A direct Claim using the existing right-index template reached Verify started!
without a terminal TLS/GET_IMAGE failure. The test was cancelled before a
biometric press. This rebuilt the previously post-S3-broken sensor context.

Persisted state was inspected without reading PMK contents:
- init timing = 300;
- capture timing = 150;
- PMK file exists and remains private root:root 0600.

No re-enrollment has been performed or is currently indicated.
## Next validation

1. Test an ordinary KDE lock/logout with an existing enrolled finger.
2. Then test after a real suspend/resume.
3. For proof of the exact first-S3 regression fix, the strongest test is:
   fresh manual reboot -> establish/use fingerprint once -> first S3 -> resume
   -> fingerprint unlock.
4. The assistant must never reboot Pegasus itself.
5. If a failure occurs, collect the journal before restarting fprintd.
6. Re-enroll only if transport is healthy and genuine captures reach the
   matcher but old templates consistently score below threshold.
