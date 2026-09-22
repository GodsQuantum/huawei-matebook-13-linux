# Plasma Login Manager 6.7.4 PAM-message backport

Compatibility package for Plasma Login Manager 6.7.4 on Arch/CachyOS.

It backports two upstream KDE fixes:
- `8f6c2d3205df3a0aab5c156d3b7e2950eda8beb0` — show PAM authentication messages in the greeter.
- `db5e466d3c3816f2cac627ca66cea9c6734f7ecc` — keep an active PAM prompt visible instead of clearing it with an old failure timer.

It also carries the normal Arch `plasmalogin` PAM profile with:

```text
auth sufficient pam_fprintd.so max-tries=1 timeout=12
```

That keeps fingerprint login package-managed: no `/etc/pam.d/plasmalogin` override is required. Messages such as `Placez votre doigt sur le lecteur d’empreintes` are rendered by the greeter while PAM/fprintd authentication is active.

The package is deliberately versioned `6.7.4-3.1`; a later upstream Plasma Login Manager release can replace it normally. It never contains or modifies fingerprint templates.
