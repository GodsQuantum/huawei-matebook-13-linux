# Current handoff — GXFP51A0 / GF3658 ST411

Updated: 2026-09-22.

## Stable and candidates

- stable public release / main: `fingerprint-gxfp51a0-rel23`
- transport candidate: `fingerprint-gxfp51a0-rel24-rc1`
- current login-integration candidate branch: `fingerprint-rel25-login-integration`
- installed reference package: `libfprint-goodix51a0 1.94.100.goodix51a0-25`
- installed fprintd: `1.94.5-2.1`
- installed Plasma Login Manager compatibility package: `6.7.4-3.1`
- libfprint base: v1.94.100
- target: GXFP51A0 / GF3658 ST411 / chip 0x2504 / firmware GF_ST411SEC_APP_14115

rel25 keeps the rel24 slow-transport recovery unchanged and fixes the graphical-login integration discovered during reboot/logout validation.

## Login regression diagnosis

The fingerprint templates were never lost. The reference machine still exposes:
- left-index-finger
- right-middle-finger
- right-index-finger

The login journal proved that PAM/fprintd emitted `Placez votre doigt sur le lecteur d’empreintes`, but Plasma Login Manager 6.7.4 did not render it.

Exact upstream KDE fixes:
- `8f6c2d3205df3a0aab5c156d3b7e2950eda8beb0` — show PAM authentication messages in the greeter.
- `db5e466d3c3816f2cac627ca66cea9c6734f7ecc` — stop an old failure timer from clearing an active PAM prompt.

The 6.7.4 greeter backend already forwarded `informationMessage`; its QML simply had no connection to the existing notification text.

## rel23 ordering bug fixed in rel25

rel23 removed the rel22 custom binder and correctly switched to native udev/spidev/libfprint prewarm, but its packaging comment claimed fprintd was ordered before the display manager while the drop-in did not actually contain that ordering.

Cold-boot evidence showed Plasma Login Manager becoming active just before fprintd finished enumeration.

rel25 adds:
`Before=display-manager.service`

The installed unit now resolves this to:
`Before=plasmalogin.service`

This preserves the native path and does not restore the obsolete GXFP-specific binder.

## Package-managed Plasma Login integration

Source:
`fingerprint/integration/plasma-login-manager-6.7-pam-messages/`

The compatibility package is based on official Plasma Login Manager 6.7.4 and applies:
1. KDE upstream PAM-message display fix.
2. KDE upstream notification-timer follow-up.
3. Arch PAM profile addition:
   `auth sufficient pam_fprintd.so max-tries=1 timeout=12`

The package version is `6.7.4-3.1`, so a later upstream Plasma Login Manager release can replace it normally.

No local `/etc/pam.d/plasmalogin` override is required anymore.

## Current reference-machine validation

Installed successfully without reboot:
- `plasma-login-manager 6.7.4-3.1`
- `libfprint-goodix51a0 1.94.100.goodix51a0-25`
- `fprintd 1.94.5-2.1`

Integrity:
- Plasma Login Manager: 209 files, 0 altered.
- libfprint-goodix51a0: 32 files, 0 altered.
- fprintd active with `--no-timeout`.
- all three prior enrollments remain visible.
- package-managed PAM profile contains pam_fprintd.
- `/etc/pam.d/plasmalogin`: absent.
- old PAM backup: absent.
- rel22 binder binary/service: absent.
- fprintd ordering resolves to `Before=plasmalogin.service`.

Build/package SHA-256:
- rel25 driver package: `2b37442f0cf77111686be932df6e8c186280e46c48e7e3d18af0428a83d3dabc`
- Plasma Login Manager 6.7.4-3.1 package: `d876b47daa9c28bc4d524b430900d181fa0bb0d3caada1ce611c82186e39329f`

## Verification status

The full software baseline passed after updating the obsolete rel23 test assumption:
- shell syntax
- native SPI/udev/prewarm source gates
- research and safety suite
- matcher/template gates
- source manifest
- reproducible libfprint v1.94.100 build
- no release biometric dump hook
- no sensor I/O/GPIO/MMIO/firmware action during software build

The package-specific regression test additionally requires:
- `Before=display-manager.service`
- the two exact upstream KDE PAM-message patches
- package-managed pam_fprintd profile

## Remaining human validation

Do not re-enroll.

The only remaining checks require leaving the current graphical session:
1. log out;
2. start authentication for the selected user;
3. verify that the small PAM line asking for the fingerprint is visible;
4. authenticate with an already-enrolled finger;
5. later reboot manually and repeat the same test at cold boot.

Do not reboot the machine automatically.

## Safety/privacy invariants

- never touch GPIO112 / GPP_D16;
- GPIO264 remains MCU reset and low in normal operation;
- no firmware flashing;
- threshold 7, template v4 / SIGFM v3, 20 enrollment views and max-three verify presses remain unchanged;
- never publish biometric captures/templates, PMK/PSK, serials, machine identifiers, private fixtures, proprietary firmware or Windows binaries.

## Publication policy

rel23 remains stable/Latest until candidate validation is complete. rel24 remains the transport prerelease for the MateBook 13 2020 report. rel25 should remain a candidate until the visible-login prompt and cold-boot authentication are confirmed on the reference machine.

## Final cleanup / local kit

Cleanup completed on the reference machine after rel25 installation:
- temporary build dependencies removed: cmake, cppdap, extra-cmake-modules, ninja, rhash;
- their exact downloaded pacman cache files removed;
- build trees, research binaries, src/pkg directories and /tmp work directories removed;
- repository working tree clean after commit/push;
- no GXFP-specific file remains in /etc, /usr/local or user cache/state outside legitimate package/runtime state;
- legitimate retained runtime state is only /var/lib/fprint enrollment/PMK/timing data and pacman metadata.

Local reinstall kit in OS & Drivers now contains only rel25-rc1 artifacts:
- rel25 Arch/CachyOS driver package;
- Plasma Login Manager 6.7.4-3.1 fingerprint-prompt compatibility package;
- rel25-rc1 public source archive;
- INSTALL.txt;
- SHA256SUMS.txt;
- one-shot INSTALL-GXFP51A0.sh.

Code commit pushed on the candidate branch: `4604d42`.
The final visible-greeter/logout and cold-boot tests are still human-interactive and must be performed before promotion to stable.
