# KScreenLocker S3 fingerprint PAM recovery (Plasma 6.7.5)

Local package: 6.7.5-1.4.

The patch keeps KDE bug 481808 / MR !340 semantics: suspend is not treated as
a password authentication failure.

Runtime logs proved that the previous resume hook could log a rearm while
fprintd received zero requests. Upstream PamWorker ignores tryUnlock while an
old pam_authenticate is still active and latches unavailable after
PAM_AUTHINFO_UNAVAIL.

On resume this package leaves the interactive password worker untouched and
restarts only noninteractive authenticators. A stale fingerprint PAM
conversation is cancelled, allowed to unwind, PAM fail-delay is respected,
the unavailable latch is cleared at the new resume boundary, and a fresh
fingerprint authentication is started.

There is no polling heartbeat, periodic timer, external sleep hook, runtime-PM
manipulation, or Goodix matcher/enrollment change.
