# Current handoff — GXFP51A0 / GF3658 ST411

Updated: 2026-09-22.

## Stable and candidates

- stable public release / main: `fingerprint-gxfp51a0-rel23`
- transport candidate: `fingerprint-gxfp51a0-rel24-rc1`
- current login-integration candidate branch: `fingerprint-rel25-login-integration`
- installed reference package: `libfprint-goodix51a0 1.94.100.goodix51a0-25`
- installed fprintd: `1.94.5-2.1`
- installed Plasma Login Manager compatibility package: `6.7.4-3.2`
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
4. A bounded compatibility patch that starts exactly one fingerprint-first PAM
   attempt when the selected-user greeter becomes visible with an empty password
   field. This restores the previously observed UI: the PAM cue appears without
   pressing Enter. A timeout returns to the normal password UI and does not loop.

The package version is `6.7.4-3.2`. Upstream 6.7.5 was checked and still lacks
the PAM-message connection, so it must not silently replace this compatibility
build until the equivalent functionality lands upstream.

No local `/etc/pam.d/plasmalogin` override is required anymore.

## Current reference-machine validation

Installed successfully without reboot:
- `plasma-login-manager 6.7.4-3.2`
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
- Plasma Login Manager 6.7.4-3.2 package: `f9b01dd7946c18a6bb530347b32abf0debd17883400c0eb583de7bd3890a9097`

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
- the bounded `0004` auto-attempt patch and its one-attempt/no-loop state

## Remaining human validation

Do not re-enroll.

The only remaining checks require leaving the current graphical session:
1. log out;
2. do not type or press Enter;
3. verify that the greeter automatically starts fingerprint authentication and
   shows the small PAM line asking for the fingerprint under the password field;
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
- Plasma Login Manager 6.7.4-3.2 fingerprint-prompt/auto-attempt compatibility package;
- rel25-rc1 public source archive;
- INSTALL.txt;
- SHA256SUMS.txt;
- one-shot INSTALL-GXFP51A0.sh.

Automatic-login compatibility implementation commit pushed on the candidate branch: `dfd439e`.
The final visible-greeter/logout and cold-boot tests are still human-interactive and must be performed before promotion to stable.

## Final rel25 machine-purity audit

Final non-interactive validation after cleanup:
- rel25 boot/login source regression test: PASS;
- libfprint-goodix51a0: 32 files, 0 altered;
- plasma-login-manager: 209 files, 0 altered;
- no failed systemd units;
- no legacy GXFP binder service/binary;
- no /etc/pam.d/plasmalogin override;
- package-managed PAM contains pam_fprintd.so;
- fprintd resolves Before=plasmalogin.service;
- no project-specific residue in /etc, /usr/local, user cache/state or /tmp;
- temporary build dependencies and their project cache artifacts are absent;
- no pacman orphans remain;
- intermediate fingerprint-development and build-dependency Snapper snapshots were deleted;
- normal timeline snapshots and the final PLM 6.7.4-3.2 rollback pair 860/861 were retained;
- all three existing enrollments remain intact.

The corrected 6.7.4-3.2 greeter has not yet been human-validated after installation.
Next human step is logout only: do not press Enter or type a password; the fresh
greeter should automatically begin one fingerprint attempt and show the small
PAM fingerprint line. Cold-boot validation follows later by manual reboot only.

## New-session bootstrap prompt

The exact reusable prompt is stored next to this handoff in:
fingerprint/handoff/PROMPT_2026-09-22_1237_REL25_LOGIN_VALIDATION.md

### Prompt complet

Reprends le chantier **Huawei MateBook 13 2021 / Goodix GXFP51A0 / GF3658 ST411** exactement là où la session précédente l’a laissé.

Utilise @Remote Desktop Commander sur Pegasus.

Workspace canonique :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/`

Repo canonique :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/`

RDC Pegasus :
`8a6eeb21-0158-4e6d-b3ea-91d580f8a223`

Commence impérativement par lire EN ENTIER, dans cet ordre :
1. `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/HANDOFF_CURRENT.md`
2. `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/HANDOFF_CURRENT.md`
3. `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/handoff/HANDOFF_2026-09-22_1237_GXFP51A0_REL25_LOGIN_INTEGRATION_READY.md`

État à préserver :
- branche candidate : `fingerprint-rel25-login-integration`
- HEAD attendu : `d455738ab4254ecb170fe8e3b909587306310b7b`
- remote de branche attendu au même commit
- `libfprint-goodix51a0 1.94.100.goodix51a0-25`
- `fprintd 1.94.5-2.1`
- `plasma-login-manager 6.7.4-3.2`
- les 3 enrollments existants doivent rester intacts
- ne jamais ré-enroller sans preuve explicite que les templates sont perdus.
Diagnostic déjà établi :
- les empreintes n’ont jamais été supprimées ;
- PAM/fprintd émettait bien « Placez votre doigt sur le lecteur d’empreintes » ;
- Plasma Login Manager 6.7.4 ne rendait pas ce message dans son QML ;
- rel23 avait aussi perdu la garantie réelle d’ordre `fprintd -> display-manager`.
- rel25 corrige l’ordre avec `Before=display-manager.service`.
- le package PLM 6.7.4-3.2 applique les deux correctifs KDE de message PAM, ajoute le profil PAM fprintd package-managed, et un patch borné qui lance UNE tentative fingerprint automatiquement quand le greeter devient visible avec mot de passe vide.

État machine déjà audité :
- aucun `/etc/pam.d/plasmalogin` local ;
- aucun binder/service GXFP51A0 hérité ;
- aucun orphan pacman ;
- aucun build/src/pkg/tmp du chantier ;
- aucun failed systemd unit ;
- packages libfprint, fprintd et PLM : 0 fichier altéré ;
- `fprintd.service` résout `Before=plasmalogin.service`;
- repo propre et pushé ;
- kit de réinstallation rel25-rc1 présent dans `~/Téléchargements/OS et Drivers/`.

NE REBOOTE PAS Pegasus toi-même.

Prochaine étape humaine prioritaire si elle n’a pas déjà été faite :
1. demander à Arezki de se déconnecter de KDE, pas de reboot ;
2. sur le greeter frais, il ne doit rien taper ni appuyer sur Entrée ;
3. vérifier que la petite ligne d’invite empreinte apparaît automatiquement sous le champ mot de passe ;
4. poser un doigt déjà enregistré et vérifier que la session s’ouvre sans mot de passe ;
5. récupérer ensuite les logs `plasmalogin` + `fprintd` pour documenter le succès/échec.

Si le logout test réussit :
- demander ensuite à Arezki de faire lui-même un reboot manuel ;
- répéter exactement le test au cold boot ;
- seulement après succès des deux tests, finaliser la publication/promotion rel25 selon le handoff.

Si le test échoue :
- NE PAS ré-enroller ;
- NE PAS modifier le matcher, threshold 7, template v4/SIGFM v3 ni firmware ;
- collecter d’abord `journalctl -b -u plasmalogin.service -u fprintd.service --no-pager`, état PAM/package/systemd et comparer au handoff ;
- corriger la couche greeter/PAM/order uniquement si les logs le justifient.

À la fin de toute intervention : maintenir Pegasus pur, supprimer tous builds/tests/tmp/deps temporaires, vérifier `pacman -Qdtq`, `systemctl --failed`, `pacman -Qkk`, `git status`, puis mettre à jour le handoff avant toute promotion.