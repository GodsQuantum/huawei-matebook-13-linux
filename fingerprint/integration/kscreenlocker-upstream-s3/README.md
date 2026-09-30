# KScreenLocker S3 fingerprint PAM recovery (Plasma 6.7.5)

Local package: 6.7.5-1.5.

The patch keeps KDE bug 481808 / MR !340 semantics: suspend is not treated as
a password authentication failure.

Runtime logs proved that the previous resume hook could log a rearm while
fprintd received zero requests. Upstream PamWorker ignores tryUnlock while an
old pam_authenticate is still active and latches unavailable after
PAM_AUTHINFO_UNAVAIL.

On resume this package leaves the interactive password worker untouched and
restarts only noninteractive authenticators. A stale fingerprint PAM
conversation is cancelled and allowed to unwind. Real authentication failures
still respect PAM fail-delay. A stale PAM_AUTHINFO_UNAVAIL result is treated as
a hardware-availability boundary instead: its unavailable latch and inherited
next-attempt delay are cleared before one fresh fingerprint authentication is
started. This removes the roughly four-second penalty observed on successful
resume recovery without weakening password or biometric failure throttling.

There is no polling heartbeat, periodic timer, external sleep hook, runtime-PM
manipulation, or Goodix matcher/enrollment change.
