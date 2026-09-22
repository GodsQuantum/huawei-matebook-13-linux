# Handoff — rel25 logout prompt fixed, capture transport failure

Updated: 2026-09-22 14:42 CEST.

## Human logout validation result

The rel25 graphical-login integration fix is confirmed at the UI/PAM layer:
- logout from KDE was performed without reboot;
- the fresh Plasma Login Manager greeter automatically displayed the fingerprint prompt;
- no Enter key or password input was needed to start the fingerprint attempt.

The enrolled fingerprint did not authenticate. This was not a matcher/template failure.
The 14:18 journal shows the capture transport failing before any biometric score:
- GET_IMAGE initially had no ACK/TLS;
- a retry received ACK but no TLS image;
- the late-image retry also returned no authenticated TLS image;
- rel24/25 marked capture transport desynchronised and moved capture pacing 100% -> 150%;
- the following MCU/session rebuild failed to re-establish TLS;
- cached-PMK and fresh-staging recovery both failed in that degraded boot state.

All three pre-existing enrollments remain intact. Never re-enroll on this evidence.
## Recovery diagnostics already executed

Two bounded recovery experiments were performed without reboot:
1. stop fprintd, detach/reattach only spi-GXFP51A0:00 from spidev, restart fprintd;
2. stop fprintd, detach spidev, run the exact rel25 gx51_reset_gpio264() recipe
   (GPIO264 HIGH 300 ms -> LOW 600 ms, final LOW), reattach spidev, restart fprintd.

Both transient systemd-run units were auto-collected and left no persistent service.
Temporary reset helper source/binary in /tmp were deleted.
Neither recovery restored reliable TLS in the already degraded boot.

Runtime-state inspection:
- /var/lib/fprint/.goodix51a0-timing = 300 (safe numeric timing state);
- .goodix51a0-capture-timing is absent;
- PMK contents were never read or exposed;
- PMK cache metadata shows a 48-byte root-only file last written 2026-09-21 23:40:41,
  consistent with a previously live-validated staging fallback.

## rel23 A/B result

Historical rel23 handoff proves the reference Pegasus had passed a five-restart fprintd
stress test, with first Claims around 112-113 ms and successful verification already
validated on the reference GXFP51A0/GF3658/ST411 unit.
A rel23 package was rebuilt exactly from commit c99522c in a detached /tmp worktree.
It was installed only as a reversible A/B test after verifying the rel25 rollback package
SHA-256 against the handoff.

In the already degraded current boot, rel23 also failed to recover cleanly: fprintd
initialization stayed blocked long enough to hit the service timeout. Therefore this
boot cannot distinguish rel23 from rel25 after the transport has entered that state.

The exact rel25-rc1 package was then restored:
- libfprint-goodix51a0 1.94.100.goodix51a0-25;
- SHA-256 2b37442f0cf77111686be932df6e8c186280e46c48e7e3d18af0428a83d3dabc;
- plasma-login-manager remains 6.7.4-3.2;
- fprintd remains 1.94.5-2.1.

The detached rel23 worktree/build was removed. Snapper A/B snapshots 867-870 were deleted.
Reference rollback snapshots 860/861 were deliberately retained.

## Boot correlation

Current boot started at 08:56 with rel24 already installed. Its initial fprintd start
showed target traffic/FDT activity but no TLS handshake failure.
At 10:51, installing rel25 restarted fprintd and a TLS handshake failure appeared.
At 14:18, the human logout attempt reached capture, then GET_IMAGE transport desynchronised
and the bounded session recovery could not restore TLS.
This correlation makes a fresh power-on state necessary before drawing another
driver-level conclusion. A manual cold reboot is now a diagnostic requirement; it is
not permission to promote rel25.

## Next human step

Arezki must reboot Pegasus manually. The assistant must never reboot it.

On the first fresh greeter after that reboot:
1. do not type a password and do not press Enter;
2. confirm the fingerprint prompt appears automatically;
3. place an already-enrolled finger;
4. record whether authentication succeeds without password.

Immediately after login, collect the complete plasmalogin + fprintd journal for that boot.
Do not restart fprintd before collecting this evidence.

Even if cold-boot login succeeds, do not promote rel25 yet. The newly exposed
restart/recovery robustness regression must be explained or fixed before stable promotion.

Safety invariants remain unchanged: no re-enrollment, no matcher/threshold/template changes,
no firmware action, no GPIO112 access, and GPIO264 must finish LOW.
