# KScreenLocker S3 PAM fix (Plasma 6.7.5)

This directory packages exactly one upstream KScreenLocker fix on top of the
official KDE Plasma 6.7.5 release tarball.

- KDE bug: 481808
- Upstream merge request: plasma/kscreenlocker !340
- Upstream commit: 992f3fa8f4c4ade5dad7df789e1883a5d5e8ac2c
- Upstream patch subject: "Don't cancel in-progress authentication on suspend"

The bug aborts the already-running PAM conversation when logind announces
suspend. The aborted conversation returns as a real PAM failure at resume,
which can show a false failed-login message, trigger PAM fail delay, count
toward pam_faillock, and prevent the fingerprint authenticator from continuing
cleanly after S3.

The upstream fix removes that suspend-time cancellation. The PAM conversation
remains parked through sleep and resumes normally.

The local package uses pkgrel 1.2 so it is newer than CachyOS 6.7.5-1.1 while
remaining naturally superseded by a future 6.7.6+ package.

No Goodix driver code, matcher threshold, fingerprint template, PAM policy, or
enrollment data is changed by this package.
