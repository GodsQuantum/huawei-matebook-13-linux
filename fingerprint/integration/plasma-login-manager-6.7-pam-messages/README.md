# Plasma Login Manager 6.7.4 fingerprint-login compatibility package

Compatibility package for Plasma Login Manager 6.7.4 on Arch/CachyOS.

It backports two upstream KDE fixes:
- `8f6c2d3205df3a0aab5c156d3b7e2950eda8beb0` — show PAM authentication messages in the greeter.
- `db5e466d3c3816f2cac627ca66cea9c6734f7ecc` — keep an active PAM prompt visible instead of clearing it with an old failure timer.

It also carries the Arch `plasmalogin` PAM profile with:
```text
auth sufficient pam_fprintd.so max-tries=1 timeout=12
```

The local compatibility patch `0004-autostart-first-fingerprint-attempt.patch`
restores the reference-machine behavior validated before the regression: when
the greeter becomes active with a selected user and an empty password field, it
starts exactly one fingerprint-first PAM attempt automatically. The PAM cue
therefore appears under the password field without pressing Enter first. If the
attempt times out, the normal password UI is restored without an artificial
generic “Login Failed” message.

The package is versioned `6.7.4-3.2`. It keeps the integration package-managed:
no `/etc/pam.d/plasmalogin` override is required, and it never contains or
modifies fingerprint templates.
