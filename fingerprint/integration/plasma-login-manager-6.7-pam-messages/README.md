# Plasma Login Manager 6.7.5 fingerprint-login compatibility package

Compatibility package for Plasma Login Manager 6.7.5 on Arch/CachyOS.

It keeps the upstream PAM-message fixes and the fingerprint-first greeter flow,
then separates password and fingerprint into independent PAM services.

## Current package: 6.7.5-3.8

Password PAM remains the normal `plasmalogin` stack and contains no
`pam_fprintd`. Fingerprint auth uses `plasmalogin-fingerprint`:

```text
-auth required pam_fprintd.so max-tries=1 timeout=15
```

The GXFP51A0 driver owns its bounded physical-pose budget, so PAM launches one
fingerprint operation rather than multiplying retries.

### Concurrent authentication

Patch `0007-parallel-password-fingerprint-auth.patch` ports the essential
multi-authenticator shape used by KDE's newer lockscreen work back to PLM 6.7.5:

- password and fingerprint run in **separate Auth/helper processes**;
- both share one prepared user/session/VT context;
- typing in the password field does **not** cancel fingerprint;
- submitting a password starts password PAM while fingerprint can remain active;
- the first authenticator to succeed atomically wins;
- the losing helper is stopped before it can start a second session;
- a failure of one method does not terminate the other;
- fingerprint is cancelled/restarted only when its user/session context changes
  or when another authenticator has already won.

Patch `0006-fingerprint-password-preemption.patch` remains in the patch history
because 3.6 is layered on top of 3.5, but 0007 deliberately removes its
password-preempts-fingerprint behavior.

Patch `0008-continuous-fingerprint-availability.patch` keeps fingerprint available
for the full greeter lifetime. Each fingerprint operation remains bounded, but a
terminal no-match/timeout rearms a fresh attempt after a short quiet gap while
password authentication remains fully usable in parallel. The retry timer stops
as soon as the login UI disappears.

Patch `0009-fix-retry-timer-qml-ownership.patch` fixes the PLM 3.7 blank-greeter
regression: `SessionManagementScreen` accepts visual `QQuickItem` children, while
`Timer` is non-visual. The retry timer is therefore bound to an object property
instead of being inserted directly into the visual child list. `qmllint` and the
compiled QML cache both pass with this form.

The package remains package-managed and never contains, modifies, deletes, or
re-enrols fingerprint templates.
