# KScreenLocker S3 PAM fix (Plasma 6.7.5)

This local package keeps the intent of KDE bug 481808 / MR !340 and adds one
narrow resume fix for Pegasus.

- Plasma/KScreenLocker: 6.7.5
- local package: 6.7.5-1.3
- upstream MR !340 reference commit: 992f3fa8f4c4ade5dad7df789e1883a5d5e8ac2c

## Behaviour

On PrepareForSleep(true), KScreenLocker does not cancel PAM. Suspend is not
treated as an authentication failure.

On PrepareForSleep(false), KScreenLocker calls
PamAuthenticators::resumeAuthenticating() directly from the C++ logind boundary.

resumeAuthenticating() is intentionally precise:

- if the whole group is still Idle, it calls the normal startAuthenticating()
  path, starting password + configured noninteractive authenticators;
- if the group is already Authenticating, it leaves the interactive password
  authenticator alone and only calls tryUnlock() on the noninteractive
  authenticators (fingerprint/smartcard);
- each PamWorker::authenticate() already ignores a duplicate request while it
  is inside pam_authenticate(), so a healthy fingerprint worker is not restarted;
- grace-lock remains respected.

Normal lock startup stays in the existing window-ready QML path. There is no
pre-QML forced authentication, QML resume timer, heartbeat, periodic keepalive,
external system-sleep hook, or runtime-PM tweak.

No Goodix matcher, threshold, template, PAM policy, or enrollment data is
changed by this package.
