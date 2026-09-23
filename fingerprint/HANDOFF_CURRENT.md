# Current handoff — GXFP51A0 / GF3658 ST411

Updated: 2026-09-23.

## Stable and candidates

- stable public release / main: fingerprint-gxfp51a0-rel23
- published transport prerelease: fingerprint-gxfp51a0-rel24-rc1
- rel25-rel28: superseded development candidates
- rel29: stale warm-context expiry candidate, functionally validated at lock
- rel30: superseded first instant-lock attempt; revealed FDT-only false-ready state
- rel31: image-ready transport candidate; KDE startup race found in human testing
- rel32: one-press direct lock validated; cold-boot greeter exposed un-prewarmed sensor
- current branch: fingerprint-rel33-coldboot-prewarm
- installed reference package: libfprint-goodix51a0 1.94.100.goodix51a0-33
- installed fprintd: 1.94.5-2.1
- current Plasma desktop: 6.7.5-1.1
- Plasma Login Manager compatibility target: 6.7.5-3.2
- libfprint base: v1.94.100
- target: GXFP51A0 / GF3658 ST411 / chip 0x2504 / firmware
  GF_ST411SEC_APP_14115

### Human evidence now established

- rel28 lock failure occurred before matching because GET_IMAGE/TLS transport
  was stale.
- rel29 added a five-minute warm-context expiry.
- after a clean prewarm, rel29 lock authentication succeeded using the
  existing right-index enrollment. Re-enrollment is therefore not required.
- a second enrolled finger also authenticated once KScreenLocker made its PAM
  prompt active.
- observed UX defect: with the lock screen visually idle, placing a finger alone
  did nothing until mouse movement made the UI visible. Plasma 6.7.5 stock QML
  starts authenticator.startAuthenticating() from onUiVisibleChanged.
- first rel30 direct-lock test failed: fprintd did start immediately, proving the
  early QML hook fired, but the prompt remained hidden and GET_IMAGE/FDT retries
  showed that a recent Claim-only keepalive had accepted an image-path-stale
  context. This directly motivated rel31.
- rel31 direct lock succeeded once, but later fresh-enrollment testing reproduced
  a no-prompt failure. The 09:48 journal captured
  LockScreenUi.qml:128 TypeError: requestActivate of null. rel31 had set
  uiVisible=true in Component.onCompleted before Window.window was guaranteed to
  exist; the exception aborted onUiVisibleChanged before
  authenticator.startAuthenticating(), and later mouse motion could not retrigger
  the handler because uiVisible was already true. This directly motivated rel32.
- a fresh right-index enrollment completed successfully in KDE at 09:37:37 on
  2026-09-23; left-index and right-middle enrollments remain unchanged.
- rel32 human direct-lock validation: PASS at about 10:16 CEST on 2026-09-23.
  User locked Pegasus and immediately placed the freshly enrolled right index
  before waiting for any visible prompt; the machine unlocked on the first
  single press with no mouse or keyboard interaction.
- the temporary root-only enrollment rollback archive in /run was removed only
  after that successful rel32 validation.
- first rel32 cold-boot validation failed. Boot journal proved fprintd was active
  at 10:27:45 CEST and Plasma Login Manager at 10:27:49, so daemon ordering was
  already correct. The greeter auto-started PAM at 10:27:52, but the sensor's
  first real open/cold preparation ran then; the fingerprint prompt appeared
  only at 10:27:57 and timed out at 10:28:09. The problem was cold sensor
  preparation happening inside the first login attempt, not a missing PAM rule.

### rel31 architecture

rel31 keeps the rel29 lifecycle safeguards and the rel30 package-owned keepalive,
but closes the false-ready state seen in the human rel30 lock test:

1. Full warm readiness
   - FDT success alone is insufficient.
   - gx_warm_validate() must also complete one encrypted background GET_IMAGE.
   - the validation frame is discarded and never enters biometric matching.
   - failure abandons stale TLS host-side and resets/rebuilds before Verify.
   - readiness failures cannot escalate persistent capture pacing.

2. gxfp51a0-warm-keepalive.timer
   - OnBootSec=20s
   - OnUnitActiveSec=3min
   - performs only fprintd Claim
   - never starts Verify or Enroll
   - now exercises the full FDT + GET_IMAGE warm-readiness path.

3. rel31 KDE attempt (superseded)
   - helper: /usr/libexec/gxfp51a0-kde-lockscreen-integrate
   - set uiVisible=true directly in Component.onCompleted.
   - this could race Window attachment and throw from requestActivate().
   - do not restore this behavior.

### rel32 KDE architecture

rel32 leaves the rel31 driver, warm validation, matcher and templates unchanged.
It replaces only the KDE lockscreen integration:

1. Window-ready startup
   - Component.onCompleted starts gxfp51a0StartupAuthTimer.
   - every 25 ms the timer checks lockScreenRoot.Window.window.
   - only after a real Window exists does it set uiVisible=true.
   - stock Plasma onUiVisibleChanged then performs requestActivate() followed by
     authenticator.startAuthenticating() without the rel31 null-window race.
   - the timer stops after success; a bounded 80-attempt guard prevents an
     infinite loop on an unsupported theme.

2. Upstream authentication heartbeat
   - KDE plasma-desktop commit e5616c6a (2026-08-18) added a one-second
     authenticator.startAuthenticating() heartbeat while uiVisible is true.
   - rel32 backports only that heartbeat to Plasma 6.7.5.
   - if a future Plasma package already contains the upstream heartbeat, the
     helper detects it and does not duplicate it.

3. Packaging / rollback
   - rel30 and rel31 markers are migrated automatically.
   - qmllint passes on the real patched 6.7.5 QML.
   - applying rel32 then removing it restores the package-stock
     LockScreenUi.qml byte-for-byte.
   - the pacman hook reapplies after plasma-desktop upgrades.
   - package removal restores stock behavior.

The installed integration intentionally makes exactly one plasma-desktop file
differ from the distro package checksum. That difference is expected,
versioned and reversible; it is not temporary residue.

Matcher/template policy remains unchanged: template v4 / SIGFM v3, threshold 7,
20 enrollment views, maximum three independent verification presses.

### rel33 cold-boot architecture

rel33 keeps the rel32 driver, matcher, enrollments and KDE lockscreen unchanged.
It adds only an early boot preparation layer:

1. gxfp51a0-boot-prewarm.service
   - pulled in by graphical.target;
   - Requires/After=fprintd.service;
   - Before=display-manager.service;
   - waits up to 5 seconds for fprintd to expose the default device;
   - performs a bounded 45-second Claim, never Verify or Enroll;
   - failures are logged and return success so password login is never bricked.

2. Verified ordering on the installed system
   - boot-prewarm Before=plasmalogin.service and graphical.target;
   - plasmalogin.service After=gxfp51a0-boot-prewarm.service;
   - graphical.target wants fprintd, boot-prewarm and plasmalogin.

3. Controlled cold-state simulation
   - warm keepalive timer stopped;
   - fprintd restarted to discard in-process warm state;
   - boot-prewarm completed in 4703 ms with Result=success;
   - log: cold-boot fprintd Claim completed; sensor ready before display manager;
   - keepalive timer restored active;
   - post-prewarm fprintd-verify immediately reached the waiting-for-finger state.

### External-repo refresh — 2026-09-23

Latest tracked external activity was re-read before rel33; rel33 changes only local boot prewarm:
- GodsQuantum issue #6: no comment newer than the already-integrated deep-vs-s2idle
  lifecycle evidence.
- szlukabence/goodix-fingerprint-spi-linux: no new code after the board-discovery
  work already reviewed; its issue #1 is closed and points users to this driver.
- Sigfrodr/libfprint-goodixtls issue #5: latest comment at 2026-09-22 22:53 CEST
  confirms NBIS/minutiae was unsafe on the same tiny GXFP51A0 sensing area and
  supports a common local-only matcher evaluation harness.
- berkekbgz/libfprint-goodix-spi and bchapoton/goodix-gxfp3200-linux: no newer
  commits requiring a rel33 driver port.

Future matcher work should therefore build a privacy-preserving local FAR/FRR/EER
harness that emits only aggregate statistics. Do not retune threshold 7 from
single-user anecdotes and never export captures or templates.

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

rel23 remains stable/Latest until candidate validation is complete. rel24 remains
the published transport prerelease. rel25-rel32 are superseded development
candidates. rel33 preserves the validated one-press direct lock behavior and
adds pre-display-manager cold-boot sensor preparation. A new cold-boot human
login test and real deep-S3 resume authentication remain before stable promotion.

## Final cleanup / local kit

Current cleanup rule for the reference machine:
- build trees, research binaries, src/pkg directories and /tmp work directories must be removed after validation;
- repository working tree must be clean after commit/push;
- no ad-hoc GXFP service or local PAM override is allowed;
- package-owned rel33 boot-prewarm, resume-prewarm, warm-keepalive and KDE integration files
  under /usr/lib are legitimate runtime state, not temporary glue;
- the single modified Plasma LockScreenUi.qml is expected while the rel32 KDE
  integration is installed and must be restored byte-for-byte by package removal;
- legitimate persistent runtime state remains /var/lib/fprint enrollment/PMK/timing data and pacman metadata;
- the temporary /run enrollment rollback copy was removed after the successful
  rel32 one-press direct-lock validation.

The local reinstall kit in OS & Drivers must track rel33:
- rel33 Arch/CachyOS driver package;
- Plasma Login Manager 6.7.5-3.2 fingerprint-prompt/auto-attempt package;
- exact rel33-rc1 public source archive;
- INSTALL.txt;
- SHA256SUMS.txt;
- one-shot INSTALL-GXFP51A0.sh.

Direct-lock is validated. The remaining deep-S3 and rel33 cold-boot checks are human-interactive.
Never reboot Pegasus automatically.

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

## 2026-09-22 14:42 logout validation update

Human logout test result: the rel25 Plasma Login Manager fix works at the UI/PAM layer.
The fingerprint prompt appeared automatically without typing or pressing Enter.
Authentication then failed below PAM, during GXFP51A0 GET_IMAGE/TLS capture transport.

No template was lost. All three enrollments remain present. Do not re-enroll.

Simple spidev rebind and the exact validated GPIO264 reset + rebind did not restore
reliable TLS in the already degraded boot. A reversible rel23 A/B test also could not
recover that degraded state, so no rel23-vs-rel25 conclusion may be drawn from it.
The exact rel25-rc1 package was restored and all A/B build/snapshot residue was cleaned.

Important correlation: this boot started cleanly at 08:56 with rel24 already installed;
TLS failure appears after the package-driven fprintd restart later in the boot, and the
14:18 biometric capture then entered a transport desynchronisation that bounded recovery
could not clear.

Full evidence and next-step rationale:
`fingerprint/handoff/HANDOFF_2026-09-22_1442_REL25_LOGOUT_TRANSPORT_FAILURE.md`

Next step is now a **manual cold reboot by Arezki** as a diagnostic baseline. The assistant
must not reboot Pegasus. On the first fresh greeter, type nothing, press no key, verify the
automatic fingerprint prompt and try one existing enrolled finger. Collect logs immediately
after login and before any fprintd restart.

Even if cold-boot login succeeds, do not promote rel25 yet: restart/recovery robustness
must be explained or fixed first.

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
- branche locale doit être propre et synchronisée avec `origin/fingerprint-rel25-login-integration`
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