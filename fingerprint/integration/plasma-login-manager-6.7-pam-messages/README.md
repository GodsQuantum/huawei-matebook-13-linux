# Plasma Login Manager 6.7.5 fingerprint-login compatibility package

Compatibility package for Plasma Login Manager 6.7.5 on Arch/CachyOS.

It keeps the upstream PAM-message fixes and the fingerprint-first greeter flow,
then separates password and fingerprint into independent PAM services.

## Current package: 6.7.5-3.5

Password PAM remains the normal `plasmalogin` stack and contains no
`pam_fprintd`. Fingerprint auth uses `plasmalogin-fingerprint`:

```text
-auth required pam_fprintd.so max-tries=1 timeout=15
```

The native GXFP51A0 driver already owns its bounded physical-pose budget, so a
single PAM fingerprint operation is sufficient. Stacking PAM
`max-tries=3` on top of the driver's own retries could multiply one login
attempt into many physical presses.

Patch `0006-fingerprint-password-preemption.patch` fixes the password race
observed with PLM 3.4:

- an intermediate rejected fingerprint pose stays an informational/auth message
  and no longer clears the greeter's fingerprint-active state prematurely;
- a real terminal fingerprint failure is still reported by the authentication
  completion path;
- typing a password can cancel fingerprint auth through the existing
  `CancelLogin` protocol;
- if a Password `Login` nevertheless reaches the daemon while the fingerprint
  helper is still active, the daemon queues the already-submitted credentials,
  stops the fingerprint helper, and starts normal password PAM automatically;
- the first submitted password is therefore never discarded merely because the
  fingerprint helper is still draining.

The package remains package-managed; it does not contain, modify, delete, or
re-enrol fingerprint templates.
