# HANDOFF — GXFP51A0 / GF3658 ST411 — rel38 definitive verify WIP

Date: 2026-09-23
Workspace canonique:
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/`

Repo local:
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/`

Repo GitHub:
`GodsQuantum/huawei-matebook-13-linux`

Zone publique à synchroniser après stabilisation:
`fingerprint/`

## Contraintes absolues

- NE JAMAIS reboot Pegasus automatiquement.
- NE JAMAIS toucher GPIO112/GPP_D16.
- GPIO264 = reset MCU active HIGH, runtime LOW.
- Ne jamais exposer PMK/PSK/templates/captures biométriques.
- Ne pas checkout/reset/stash le WIP rel38.
- Ne pas pousser rel38 vers stable/main avant validation runtime complète.
- Les tests physiques sont déclenchés uniquement par Arezki.
- Ne plus utiliser /mnt/Cloud9 pour les scripts/tests interactifs.
- Ne jamais réutiliser l'ancien gxfp51a0-rel36-runtime-test.sh.
- Quand une action physique est nécessaire: `À faire de ton côté maintenant : ...`

## État Git

Branche locale:
`fingerprint-rel38-definitive-verify`

HEAD:
`8093955777457f3d643af41dadf0d1a9a7496099`

HEAD = commit rel35:
`fix(fingerprint): stabilize first greeter fingerprint attempt`

rel38 est entièrement NON COMMITÉ au-dessus de ce HEAD.

Aucun push rel38 n'a été effectué.

## État paquet / runtime AVANT le prochain reboot

Installé sur disque:
- libfprint-goodix51a0 1.94.100.goodix51a0-38
- fprintd 1.94.5-2.1
- plasma-login-manager 6.7.5-3.3
- package integrity: 45 fichiers, 0 modifié

Enrollments toujours présents:
- right-index-finger
- left-index-finger
- right-middle-finger

IMPORTANT:
- rel38 a été installé avec pacman --noscriptlet.
- fprintd n'a volontairement PAS été redémarré.
- processus fprintd encore actif avant reboot: PID 32244, démarré à 19:14:05.
- ce processus a chargé l'ancien libfprint rel36 en mémoire.
- donc rel38 n'est PAS encore validé runtime.
- le capteur / contexte TLS du vieux processus est considéré empoisonné après les anciens wrappers.
- prochain démarrage rel38 doit être un vrai cold boot humain.

Aucun debug env fprintd actif.

## Pourquoi les derniers tests n'affichaient jamais POSE

Ce n'était pas un échec du matcher rel36.

L'ancien wrapper:
1. arrêtait le keepalive;
2. activait G_MESSAGES_DEBUG=all;
3. redémarrait fprintd;
4. forçait boot-prewarm;
5. le script faisait des polls busctl finger-needed/finger-present.

À 19:12:
- ces polls busctl ont timeouté;
- fprintd-verify n'a jamais atteint Verify started!;
- Claim a fini en timeout;
- la préparation cold a ensuite produit des TLS digest check failed répétés.

Le PMK cache avait été validé avec succès à 16:45, donc TLS fonctionnait avant cette séquence.
Le fichier PMK existe toujours et n'a jamais été exposé.

Conclusion:
les wrappers de test qui redémarrent fprintd ont perturbé le lifecycle.
Ils sont abandonnés.

## Recherche externe réactualisée septembre 2026

Sources étudiées:
- issues récents de GodsQuantum/huawei-matebook-13-linux;
- szlukabence/goodix-fingerprint-spi-linux, GXFP51A0/Huawei;
- berkekbgz/libfprint-goodix-spi, driver GDIX51C0 actuel;
- documentation libfprint suspend/resume.

Conclusions utiles:
1. Le même principe Windows/Goodix RetryCaptureIMG est confirmé:
   - image initiale;
   - FDT-manual confirme doigt toujours posé;
   - image retry 0x20;
   - jusqu'à 3 images sur la même pose.
2. Les images doivent rester scorées indépendamment.
3. Le deep-S3 est une vraie frontière froide; s2idle évite le problème chez un autre testeur.
4. Les drivers Goodix récents gèrent explicitement ImageBase/FDT baseline et cold boundary.
5. Sur CE GXFP51A0, les mesures historiques du repo montrent qu'un background vieux de quelques dizaines de secondes peut faire chuter le score de ~11-28 à ~2-4.
6. Notre ancien gx_warm_validate capturait justement un fond frais pour valider TLS puis LE JETAIT, en continuant à utiliser self->bg_frame ancien.

## Architecture rel38

### 1. Same-press Verify conservé

Threshold = 7, inchangé.

Chaque pose physique peut produire:
- image 1 initiale;
- image 2 RetryCaptureIMG;
- image 3 RetryCaptureIMG.

Les scores:
- ne sont jamais additionnés;
- ne sont jamais fusionnés;
- chaque image doit indépendamment atteindre 7;
- arrêt immédiat au premier score >= 7.

Enrollment et Identify ne passent pas par ce chemin.

### 2. WARM_REBASE: vrai refresh background + FDT

gx_warm_validate:
- sonde FDT avant le refresh;
- si doigt déjà présent: NE capture PAS de nouveau background;
- conserve le dernier background propre;
- sinon capture une image no-finger fraîche;
- re-sonde FDT après la capture;
- si un doigt est arrivé entre-temps: rejette cette image comme background;
- sinon adopte réellement cette image comme self->bg_frame;
- rafraîchit aussi self->fdt_base et self->fdt_abs.

Marqueurs runtime normaux:
- GXFP51A0 WARM_REBASE deferred...
- GXFP51A0 WARM_REBASE discarded...
- GXFP51A0 WARM_REBASE refreshed background+FDT...

### 3. Fin propre du TLS au shutdown de fprintd

Bug lifecycle trouvé:
- gx_dev_close ferme les FDs hôte mais conserve TLS pour le prochain Claim dans le même processus;
- lors d'un arrêt/restart du daemon, finalize ne pouvait plus envoyer close_notify car les FDs étaient déjà fermés;
- le MCU pouvait donc rester dans une session dont l'état TLS host venait de disparaître.

rel38:
- finalize réouvre seulement le transport si une session warm doit être terminée;
- gx_warm_discard peut alors envoyer le teardown TLS;
- puis les FDs sont fermés.

Marqueurs:
- GXFP51A0 FINALIZE_TRACE reopened transport for warm TLS teardown
- ou erreur explicite.

### 4. Plus de keepalive périodique

Le paquet rel38 ne contient PLUS:
- gxfp51a0-warm-keepalive.timer
- gxfp51a0-warm-keepalive.service
- /usr/libexec/gxfp51a0-warm-keepalive

Raison:
- les Claims synthétiques périodiques ne sont plus nécessaires;
- ils pouvaient multiplier les opérations lorsque le capteur était déjà malade;
- les vrais Claims font maintenant le refresh background/FDT;
- boot-prewarm et resume-prewarm restent installés.

### 5. Protocole de test définitif piloté par le driver

Le driver écrit sans debug global:
- GXFP51A0 VERIFY_TRACE physical press N/3 READY
- ... DETECTED_HOLD
- same-press image 1/3 score=...
- éventuellement 2/3, 3/3
- same-press completed images=... best=... threshold=7
- ... LIFT_NOW
- ... RELEASED

Le script:
`fingerprint/tools/gxfp51a0-verify-diagnostic.py`

ne:
- poll plus busctl;
- ne redémarre jamais fprintd;
- ne force aucun prewarm;
- ne touche aucun timer;
- ne déduit jamais le retrait via finger-present.

Il affiche POSE uniquement après READY émis par le driver.

Si le Claim/init échoue avant READY, il l'indique explicitement et aucune pose n'est demandée.

## Validation logicielle rel38

PASS:
- git diff --check
- Python py_compile du diagnostic
- test-goodix51a0-boot-binding.py
- suite complète make -C fingerprint/research test
- nouveaux tests:
  - test_same_press_verify_source_safety
  - test_warm_rebase_source_safety
  - test_finalize_warm_teardown_source_safety
  - test_verify_trace_protocol_source_safety

Build réel libfprint v1.94.100:
- SOURCE_MANIFEST=PASS
- LIBFPRINT_PATCH=PASS
- MESON_CONFIGURE=PASS
- LIBFPRINT_BUILD=PASS
- GOODIX51A0_OBJECT_COMPILED=YES
- ACPI/udev gate=PASS
- FASTBRIEF/RANSAC present
- biometric dump release hook absent
- aucune I/O capteur/GPIO/firmware pendant build

Paquet:
`fingerprint/packaging/arch/libfprint-goodix51a0-1.94.100.goodix51a0-38-x86_64.pkg.tar.zst`

SHA256:
`ded6805d8bbf81b35f9ae9c75d966f7ec3008e66a81997b9025af2a45bc2a6e2`

NOTE: si le paquet est rebuild après ce handoff, recalculer le SHA avant publication.

## Prochaine action exacte

NE PAS lancer de test fingerprint dans la session actuelle.

Le vieux fprintd rel36 est encore en mémoire et son contexte est invalide.

1. Arezki redémarre Pegasus MANUELLEMENT.
2. Après reconnexion, via RDC vérifier AVANT tout test:
   - package rel38 installé;
   - fprintd démarré après le reboot;
   - aucun debug env;
   - keepalive absent;
   - enrollments présents;
   - boot-prewarm Result=success;
   - journal TLS/cold-open sain;
   - idéalement WARM_REBASE visible.
3. Seulement si init sain, Arezki lance lui-même le test définitif:
   `cd "/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux" && python3 fingerprint/tools/gxfp51a0-verify-diagnostic.py -f right-index-finger -u arezki --physical-label "INDEX DROIT" --timeout 90`
4. Lire ensuite le log + journal via RDC.
5. Chercher particulièrement une pose sauvée:
   image1 < 7 puis image2/3 >= 7.
6. Répéter plusieurs Verify seulement au moment choisi par Arezki.
7. Ensuite lockscreen.
8. Ensuite cold boot humain.
9. Ensuite corriger proprement le fallback password sans timeout 12 s bloquant.
10. Ensuite deep-S3.
11. Seulement alors commit/push/build final/kit/cleanup/stable.

## Critères de stabilisation

- Verify rel38 reproductible sur plusieurs poses;
- same-press réellement observé;
- lockscreen une pose immédiate;
- cold boot login fingerprint;
- password fallback non bloquant;
- deep-S3 direct;
- aucun debug temporaire;
- aucun wrapper perturbateur;
- repo clean après commit final;
- package final reconstruit depuis commit exact;
- checksums et kit alignés;
- seulement ensuite synchronisation fingerprint/ vers stable/main.

## Update 2026-09-24 — login password/fingerprint preemption fixed

User-observed regression on first rel38 reboot:
- Plasma Login Manager auto-started fingerprint.
- password entry was effectively blocked until the fingerprint PAM attempt expired.
- this is NOT acceptable UX.

Root cause:
1. /usr/lib/pam.d/plasmalogin had pam_fprintd.so max-tries=3 timeout=12 BEFORE system-login.
2. PAM is sequential here, so password could not overtake the active fingerprint module.
3. patch 0004 also disabled footer/mainStack during the automatic fingerprint attempt.
4. PLM 6.7.5 daemon rejects a second concurrent Auth while one is active.

Implemented local PLM package 6.7.5-3.4 with:
fingerprint/integration/plasma-login-manager-6.7-pam-messages/0005-split-fingerprint-password-auth.patch

Contract:
- plasmalogin = normal password PAM, NO pam_fprintd.
- plasmalogin-fingerprint = dedicated fingerprint-only PAM.
- automatic fingerprint attempt uses FingerprintLogin + dedicated PAM.
- password UI stays enabled during fingerprint attempt.
- first password typing sends CancelLogin.
- daemon stops fingerprint helper.
- LoginCancelled ACK is emitted only after helper has actually exited.
- password path is then immediately free.
- Enter while cancellation is pending queues password login until ACK.
- helper PAM service name is hard-whitelisted to plasmalogin-fingerprint.

New protocol:
- FingerprintLogin
- CancelLogin
- LoginCancelled

Validation:
- full CMake build incl. QML/daemon/helper: PASS
- clean makepkg from official 6.7.5 tarball + patches 0001..0005: PASS
- staged PAM split: PASS
- installed package integrity: 210 files, 0 modified
- full fingerprint/research suite incl. dual-auth safety: PASS
- test-goodix51a0-boot-binding.py: PASS

Installed:
- plasma-login-manager 6.7.5-3.4
- libfprint-goodix51a0 1.94.100.goodix51a0-38
- fprintd 1.94.5-2.1

Installed PAM:
- /usr/lib/pam.d/plasmalogin: NO pam_fprintd
- /usr/lib/pam.d/plasmalogin-fingerprint: pam_fprintd max-tries=3 timeout=12

Important live state:
- plasmalogin PID 910 started 2026-09-24 01:45:44, before 3.4 installation.
- it was deliberately NOT restarted because that would disrupt/logout the user.
- next PLM 3.4 greeter validation must use a USER-INITIATED FULL REBOOT so daemon and greeter load 3.4 together.
- do not use a simple logout as the first 3.4 validation.

Build-only deps were removed after build:
- extra-cmake-modules
- cmake
- cppdap
- rhash
~105 MiB cleaned.
Build tarball/package residue removed after successful installation.

rel38 cold boot already healthy:
- fprintd PID 723 started 01:45:38.
- boot-prewarm SUCCESS.
- WARM_REBASE refreshed background+FDT succeeded at 01:46:10.
- keepalive absent.
- no debug env.

Do not commit/push yet. Runtime fingerprint Verify + PLM 3.4 reboot behavior still need human validation.

## Update 2026-09-24 — rel39 installed

Observed cold-boot failure on rel38:
- PLM 6.7.5-3.4 correctly issued FingerprintLogin.
- matcher was never reached.
- no VERIFY_TRACE score / verify-match / verify-no-match occurred.
- fprintd logged repeated GET_IMAGE had no ACK/TLS and FDT retries.
- root cause: rel38 fresh one-shot warm handoff allowed a Claim within 10 s to skip gx_warm_validate() after transport close/reopen.

rel39 change:
- removed warm_handoff_ready.
- removed GX_WARM_HANDOFF_TTL_US.
- removed gx_warm_consume_fresh_handoff().
- no path may skip background GET_IMAGE merely because a prior Claim ended recently.
- every reopened warm context must pass gx_warm_validate() (FDT + GET_IMAGE/TLS).
- failed validation falls back to existing cold rebuild path.
- same-press Verify, threshold=7, WARM_REBASE, finalize TLS teardown and PLM 3.4 remain unchanged.

Validation before packaging:
- test_fresh_warm_handoff_source_safety: PASS (blind handoff disabled)
- test_warm_rebase_source_safety: PASS
- test_lifecycle_recovery_source_safety: PASS
- test-goodix51a0-boot-binding.py: PASS
- full fingerprint/research suite: PASS
- reproducible libfprint v1.94.100 build: PASS
- RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT

Package built:
libfprint-goodix51a0-1.94.100.goodix51a0-39-x86_64.pkg.tar.zst
SHA256:
0e73b10a1fbcda33ba69c5fba9e01e2f7efac9a729e381d98b9c4b165201c533

Installed with pacman --noscriptlet:
- libfprint-goodix51a0 1.94.100.goodix51a0-39
- package integrity: 45 files, 0 modified
- enrollments intact: right-index, left-index, right-middle
- PLM remains 6.7.5-3.4
- password PAM contains no pam_fprintd
- fingerprint PAM remains dedicated

Important:
- fprintd was deliberately NOT restarted during rel39 installation.
- current fprintd process predates installation and therefore still has rel38 library code mapped in memory.
- rel39 runtime validation requires next USER-INITIATED reboot (preferred) or an explicitly controlled fprintd restart.
- do not launch surprise biometric tests.
- do not commit/push yet.

Local branch renamed to:
fingerprint-rel39-validated-warm-reopen

## Update 2026-09-24 — rel40 Windows WakeupMCU + Identify same-press

Human rel39 reboot result:
- fingerprint login failed.
- this was NOT a biometric no-match.
- rel39 WARM_REBASE succeeded at 09:28:35.
- first real finger GET_IMAGE ~11 s later failed before matcher with repeated
  "GET_IMAGE had no ACK/TLS".
- therefore enrollments/threshold were not implicated.

Exact Windows GXFP51A0 evidence revalidated locally:
- private package: FingerPrint_1.1.141.36
- exact gfspi.dll SHA-256:
  4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59
- WakeupMCU function located at VA 0x1800413e4.
- it constructs exactly 4 bytes:
  0f 00 00 0e
- passes them with length 4 and direction 0 into _SpbPeripheralRW.
- the same direction 0 is used by the function explicitly logged as
  PeripheralWriteWrapper / SpbPeripheralWrite.
- it then calls Sleep(5).
- conclusion: WakeupMCU is exactly one raw SPI write {0f 00 00 0e} + 5 ms,
  NOT a Milan protocol frame and NOT a GPIO operation.
- the temporary extracted Windows binaries under /tmp were deleted after static
  analysis. The private source package remains private and was never exposed.

The exact GXFP51A0 WBDI transcript also confirms real finger GET_IMAGE uses 0x20.
Do NOT port the 0x22 initial-image behavior from unrelated GDIX51C0/Chicago.

fprintd behavior:
- VerifyStart("any") can use all enrolled prints when device supports it.
- this driver exposes Identify.
- rel36-rel39 only enabled same-press recapture for 1:1 Verify and therefore
  could bypass their main improvement at the graphical login.
- rel40 extends independent same-press captures to Identify too.

rel40 changes:
1. gx_wakeup_mcu():
   - raw SPI bytes 0f 00 00 0e
   - no Milan framing / no ACK expectation
   - 5 ms sleep
   - invoked at operation/session start after TLS/background/FDT are ready and
     before waiting for the user's finger.
2. Same-press applies to both 1:1 Verify and 1:N Identify:
   - initial image + up to two RetryCaptureIMG images;
   - each image scored independently;
   - threshold remains 7;
   - scores are never summed/fused;
   - Identify independently scores each image against the enrolled gallery.
3. Physical tracing now reports VERIFY_TRACE or IDENTIFY_TRACE.
4. Diagnostic parser accepts both modes.
5. Capture pacing remains unchanged for this candidate:
   - persisted capture pacing is still 200% / 60 ms;
   - do not change wake + pacing simultaneously without evidence.

Software validation:
- git diff --check PASS.
- test_windows_wakeup_identify_same_press_source_safety PASS.
- test_same_press_verify_source_safety PASS (Verify + Identify).
- test_verify_trace_protocol_source_safety PASS (Verify + Identify).
- full fingerprint/research suite PASS, including the new wake/identify test.
- test-goodix51a0-boot-binding.py PASS.
- reproducible libfprint v1.94.100 build PASS.
- GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES.
- GOODIX51A0_FASTBRIEF_RANSAC_IN_LIBRARY=YES.
- RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT.
- no active sensor I/O / GPIO / MMIO / firmware action during build.

Final rel40 package:
libfprint-goodix51a0-1.94.100.goodix51a0-40-x86_64.pkg.tar.zst
SHA256:
d40586f84f6ae91c3f7dc84c02bc344729e7148eae1df02713fd3db1696b5c4e

Installed with pacman --noscriptlet:
- libfprint-goodix51a0 1.94.100.goodix51a0-40
- package integrity: 45 files, 0 modified
- enrollments intact: right-index, left-index, right-middle
- plasma-login-manager remains 6.7.5-3.4
- password PAM remains free of pam_fprintd
- dedicated fingerprint PAM remains in place
- no debug environment.

IMPORTANT runtime state:
- fprintd PID 718 started 09:28:25, before rel40 installation.
- therefore that process still has rel39 mapped.
- rel40 is installed ON DISK but has not yet been runtime-tested.
- do not restart fprintd as a substitute for the next cold-boot validation.
- do not launch surprise biometric tests.

Next validation:
1. user manually reboots Pegasus;
2. at the greeter, user tries an enrolled finger normally;
3. password remains available through PLM 3.4;
4. after login, collect logs BEFORE any fprintd restart;
5. expected rel40 evidence:
   - AUTH_TRACE WakeupMCU raw SPI write complete;
   - IDENTIFY_TRACE physical press ...;
   - AUTH_TRACE mode=identify same-press image ...;
   - ideally a real score / match;
6. if GET_IMAGE still fails after exact WakeupMCU, investigate persisted capture
   pacing 200% / 60 ms separately; nominal validated value is 100% / 30 ms.
7. no re-enrollment unless healthy transport reaches matcher repeatedly and old
   templates genuinely score below threshold.

Do not commit/push yet.
Local branch:
fingerprint-rel40-windows-wakeup-identify

## Runtime validation 2026-09-24 — rel40 LOGIN SUCCESS

Human cold-boot login result: SUCCESS via fingerprint.

Boot:
- 2026-09-24 13:33:19
- libfprint-goodix51a0 1.94.100.goodix51a0-40
- fprintd 1.94.5-2.1
- plasma-login-manager 6.7.5-3.4

Observed authentication sequence:
- PLM FingerprintLogin: 13:33:48
- WARM_REBASE refreshed background+FDT: 13:33:50
- exact Windows WakeupMCU raw SPI write: SUCCESS
- Identify physical press 1:
  - image 1/3 score 2
  - image 2/3 score 3
  - image 3/3 score 3
  - best 3 < threshold 7
- next physical press:
  - image 1/3 rejected by quality gate
  - image 2/3 score 7
  - threshold 7 reached
  - same-press stopped immediately
- PAM opened plasmalogin-fingerprint session for arezki at 13:33:58
- Wayland user session started successfully.

This is direct proof that:
1. rel40 exact-target WakeupMCU path is executing.
2. graphical login uses Identify.
3. same-press is now active on Identify.
4. an additional image from the SAME press can rescue authentication.
5. existing enrollments remain valid; re-enrollment is NOT needed.

Remaining issue before final/stable:
- prewarm earlier this boot had GET_IMAGE/TLS desync and escalated capture pacing:
  200% -> 250%.
- persisted files now read:
  - capture timing = 250
  - init/TLS timing = 300
- this is the same one-way pacing-ratchet class previously reported by szlukabence.
- therefore rel40 is functionally successful but NOT yet final/stable.
- next work should isolate/remove incorrect pacing escalation caused by lifecycle/prewarm failures, without touching the now-working matcher/WakeupMCU/Identify same-press path.

## Update 2026-09-24 — rel42 fast + distro-portable candidate

Baseline preserved:
- rel40 cold-boot graphical fingerprint login remains the last human-validated runtime baseline.
- rel42 does NOT change WakeupMCU, WARM_REBASE, Identify same-press, threshold 7,
  template format, enrollments, PMK handling or PLM 3.4 split-auth behavior.
- existing enrollments remain: right-index, left-index, right-middle.

rel42 performance/lifecycle change:
- adaptive timing remains process-local/RAM-only; no timing value is persisted.
- every fresh daemon/lifecycle starts from validated nominal 100% timing.
- gx_prepare_capture_context now suppresses capture-pacing learning while doing
  TLS/background/FDT lifecycle/calibration work.
- a prewarm/background GET_IMAGE miss may trigger session recovery but cannot
  slow the first real biometric capture.
- real biometric captures retain session-local adaptation and decay.

Portable installation:
- automatic dependency recipes: Arch/CachyOS, Debian/Ubuntu, Fedora/RHEL,
  openSUSE and Alpine.
- generic distributions may use --no-install-deps after installing build deps.
- Meson libdir is discovered dynamically: plain lib, lib64, Debian multiarch.
- distro fprintd ABI is validated against staged rel42 before system changes.
- glibc: ldd -r + executable smoke test.
- musl: dependency ldd + LD_BIND_NOW=1 executable smoke test.

- systemd: local libfprint is exposed only to fprintd via service-local
  LD_LIBRARY_PATH; boot/resume prewarm remains an optimization.
- non-systemd: /etc/dbus-1/system-services activation override starts an
  isolated fprintd wrapper; no global ld.so.conf replacement.
- rollback restores distro-owned files and supports both systemd and D-Bus paths.
- old rel41 global-loader file is cleanup-only compatibility residue.

Real clean-container validation:
- Debian stable: PASS; /usr/local/lib/x86_64-linux-gnu; fprintd ABI PASS.
- Fedora latest: PASS; /usr/local/lib64; fprintd ABI PASS.
- openSUSE Tumbleweed: PASS; /usr/local/lib64; fprintd ABI PASS.
- Arch Linux latest: PASS; /usr/local/lib; fprintd ABI PASS.
- Alpine edge/musl: PASS; /usr/local/lib; musl ABI fallback PASS.
- all temporary rel42 validation containers removed afterwards.

Portability fixes discovered by real matrix:
- Debian exposes libudev.pc while libfprint 1.94.100 queried udev metadata:
  rel42 passes udev_rules_dir explicitly and disables optional generated hwdb.
- meson install uses --no-rebuild after the already-gated build.
- openSUSE uses libpixman-1-0-devel.
- Arch current split requires glib2-devel for glib-mkenums.
- pristine Arch build-only container refreshes package sync DB first.
- Alpine CI bootstraps with sh and uses Git checkout without JS/glibc action.

Validation:
- git diff --check PASS.
- full fingerprint/research suite PASS.
- test-goodix51a0-boot-binding.py PASS.
- test-fingerprint-tooling.py PASS.
- prepare-pacing-neutral source gate PASS.
- portable installer source gate PASS.
- source manifest PASS.
- reproducible native Arch package build PASS.
- RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT.
- no active sensor I/O/GPIO/MMIO/firmware action during build.

Installed on disk:
- libfprint-goodix51a0 1.94.100.goodix51a0-42
- package integrity: 45 files, 0 modified
- package SHA256:
  37f00f4aad84c45236f745a2eb5edf0a3310bf42ce89f8cad37de0982ac13453
- legacy non-secret timing integer files removed.
- PMK and fingerprint templates untouched.

Runtime boundary:
- current fprintd remains PID 727, started 2026-09-24 13:33:27 CEST,
  before rel42 installation; therefore it still executes rel40 in memory.
- rel42 is installed ON DISK but has not been runtime-tested.
- next validation must be USER-INITIATED cold reboot + normal greeter fingerprint.
- after rel42 login validation, manually validate suspend/resume separately.

Git:
- branch: fingerprint-rel42-fast-portable
- commit: 6b04e80c8903c7e47e2daf39b626cfbd52f16cf7
- commit message: feat(fingerprint): make rel42 fast and distro-portable
- working tree clean.
- do NOT push/promote stable/main until cold boot and suspend/resume are validated.

## Update 2026-09-24 — rel42 fast + portable software-final candidate

Reference runtime baseline preserved:
- rel40 cold-boot graphical fingerprint login SUCCESS.
- exact Windows GXFP51A0 WakeupMCU retained.
- WARM_REBASE retained.
- Verify + Identify same-press retained.
- threshold remains 7; no score fusion/addition.
- 20 enrollment views and existing template-v4/SIGFM-v3 enrollments unchanged.
- PLM 6.7.5-3.4 password/fingerprint split unchanged.

rel42 fixes the remaining pacing ratchet:
- no adaptive timing is persisted to disk.
- every fresh lifecycle begins at nominal 100%.
- lifecycle/prewarm preparation has capture_pacing_suppressed and cannot train pacing.
- 3 consecutive successful captures that needed GET_IMAGE retry may raise capture pacing one 50-point step in the current daemon only.
- 8 clean captures decay one step toward nominal.
- true biometric transport desync may still raise current-session pacing and requests full recovery.
- TLS/protocol timing adaptation is also session-only.
- legacy rel24-rel40 .goodix51a0 timing integers are migration-only and removed.

Portable installer:
- Arch/CachyOS: native pacman package.
- Debian/Ubuntu: isolated /usr/local candidate, dynamic multiarch libdir.
- Fedora/RHEL and openSUSE: dynamic lib64.
- Alpine/musl: plain lib plus musl-compatible ABI gate.
- non-systemd: high-precedence D-Bus activation wrapper isolates candidate to fprintd.
- systemd: service-local LD_LIBRARY_PATH; distro libfprint remains untouched elsewhere.
- staged candidate is ABI-tested against the distro fprintd BEFORE any system file change.
- rollback manifest and uninstall helper are installed.
- no global ld.so.conf override in rel42.

Real clean-container build/ABI validation on 2026-09-24:
- Debian stable: PASS, /usr/local/lib/x86_64-linux-gnu, fprintd ABI PASS.
- Fedora current: PASS, /usr/local/lib64, fprintd ABI PASS.
- openSUSE Tumbleweed: PASS, /usr/local/lib64, fprintd ABI PASS.
- Arch Linux: PASS, /usr/local/lib, fprintd ABI PASS.
- Alpine edge/musl: PASS, /usr/local/lib, dependency-only musl ldd gate + eager binding PASS.
All builds also passed:
- SOURCE_MANIFEST
- libfprint v1.94.100 pinned build
- GXFP51A0 ACPI/udev registration
- Identify path
- FASTBRIEF/SIGFM RANSAC
- release biometric dump hook ABSENT
- no active sensor/GPIO/MMIO/firmware action during build.

Final Arch rel42 package checksum before cleanup:
SHA256 38f39739d49119f2e6286f107f6491a5cf2b9b59cee972fcc67a7c71832a21b5
libfprint-goodix51a0-1.94.100.goodix51a0-42-x86_64.pkg.tar.zst

Installed-on-disk state:
- libfprint-goodix51a0 1.94.100.goodix51a0-42
- package integrity: 45 files, 0 modified
- fprintd 1.94.5-2.1
- plasma-login-manager 6.7.5-3.4
- enrollments intact: right-index, left-index, right-middle
- PMK cache untouched
- old .goodix51a0-timing and .goodix51a0-capture-timing: ABSENT

IMPORTANT live state:
- fprintd PID 727 has ActiveEnterTimestamp 2026-09-24 13:33:27 CEST.
- this process predates the final rel42 install/reinstall at ~15:39, so it must be treated as the previously validated runtime code already mapped in memory.
- rel42 is final on disk but still requires one USER-INITIATED cold reboot for runtime validation.
- do not restart fprintd as a substitute for that final cold-boot test.

Benjamin Allègre / Sigfrodr latest relevant message:
- 2026-09-24 12:27 UTC, Sigfrodr/libfprint-goodixtls issue #5, comment 5814092473.
- provides tools/eval/fp_eval.py for privacy-preserving local held-out evaluation.
- reports only aggregate EER/FAR/FRR, score histograms and d-prime.
- no capture/template upload is needed.
- this supports the current host descriptor/geometric matcher direction; it does NOT justify changing the validated threshold 7 without broader aggregate data.
- README EN/FR/ZH now documents this as an optional external validation method.

## rel42 final software checkpoint — 2026-09-24 15:xx CEST

Git:
- branch: fingerprint-rel42-fast-portable
- rel42 code commit: 6b04e80 feat(fingerprint): make rel42 fast and distro-portable
- docs/portable-validation commit: 6684963 docs(fingerprint): record rel42 portable validation
- working tree: CLEAN

Cleanup completed:
- deleted local package artifacts rel36 through rel42 after recording final rel42 SHA256
- deleted makepkg src/pkg work trees
- deleted public-build and research-build temporary trees
- deleted /tmp distro-matrix logs
- no PMK/enrollment/template/private reference data touched

Installed disk state remains rel42, but live fprintd PID 727 started at 13:33:27 before final rel42 installation. Therefore the only remaining acceptance gate is a user-initiated full cold reboot followed by normal graphical fingerprint login and log inspection.

Do NOT modify matcher/threshold/WakeupMCU/Identify same-press unless rel42 cold-boot logs provide concrete evidence.
Do NOT push/promote stable until that runtime gate passes.

## Update 2026-09-24 — rel43 protocol auto-calibration candidate

rel42 cold-boot runtime result: FAILED before biometric capture.
- Boot: 2026-09-24 17:30:01 CEST.
- Installed/runtime candidate at that boot: libfprint-goodix51a0 1.94.100.goodix51a0-42.
- WARM_REBASE succeeded.
- exact Windows WakeupMCU succeeded.
- greeter reached IDENTIFY_TRACE physical press 1/3 READY.
- no DETECTED_HOLD followed, therefore no GET_IMAGE finger capture, no score and no matcher decision.
- PLM fingerprint PAM timed out/failed; password login remained available and succeeded.

rel42 regression isolated:
- rel42 correctly removed all persistent capture/protocol timing files.
- but gx_cold_prepare also forced protocol timing back to 100% on every cold preparation.
- this boot immediately showed repeated no-IRQ target ACK retries and FDT ACK retries.
- rel40 had succeeded with a more conservative learned protocol timing.
- capture pacing and protocol timing must therefore remain separate concepts.

rel43 change:
- capture pacing remains RAM-only and non-persistent.
- lifecycle/prewarm work remains unable to train capture pacing.
- protocol timing begins at 100% in a fresh fprintd process.
- each observed idempotent target-ACK, FDT or TLS-handshake miss may raise protocol timing by one bounded 50-point step, maximum 300%.
- a same-process cold/session recovery preserves the already-proven protocol timing instead of resetting to 100%.
- no protocol or capture timing value is written to disk, so there is no cross-boot ratchet.
- rel40 biometric path is untouched: exact WakeupMCU, WARM_REBASE, Verify+Identify same-press, threshold 7, template-v4/SIGFM-v3, enrollments and PLM 3.4 split auth.

rel43 software validation:
- git diff --check: PASS.
- full fingerprint/research suite: PASS.
- test-goodix51a0-boot-binding.py: PASS.
- test-fingerprint-tooling.py: PASS.
- session-local timing gate: PASS (RAM auto-calibration).
- reproducible native Arch libfprint build: PASS.
- release biometric dump hook: ABSENT.
- active sensor/GPIO/MMIO/firmware actions during build: NONE.

rel43 clean multi-distro build/fprintd ABI matrix:
- Debian stable: PASS.
- Fedora current: PASS.
- openSUSE Tumbleweed: PASS.
- Arch Linux latest: PASS.
- Alpine edge/musl: PASS.
- openSUSE minimal-image pam_pwquality warning originates from pam-config while installing distro packages; the module is disabled there and final libfprint build + fprintd ABI gate both PASS.

Installed-on-disk state:
- libfprint-goodix51a0 1.94.100.goodix51a0-43.
- package integrity before cleanup: 45 files, 0 modified.
- package SHA256: cbecd4e4d289c139e5367b73c0b6fc4100665778cc17686f1c8566621d2e7e5a.
- fprintd 1.94.5-2.1.
- plasma-login-manager 6.7.5-3.4.
- enrollments intact: right-index, left-index, right-middle.
- PMK/templates untouched.
- legacy .goodix51a0-timing and .goodix51a0-capture-timing files: ABSENT.

Git:
- branch: fingerprint-rel43-protocol-autocal.
- code commit: 44b5f2c5f5809c6ff674a94056e816f348aacdad.
- docs commit: bdd1ed7.
- do not push/promote stable until runtime acceptance.

IMPORTANT live boundary:
- current fprintd PID 728 started 2026-09-24 17:30:09 CEST, before rel43 was installed.
- therefore the current daemon still executes rel42 mapped in memory.
- rel43 has NOT yet had a biometric runtime test.
- next acceptance gate is a USER-INITIATED full reboot followed by a normal graphical fingerprint login.
- if rel43 cold boot succeeds, validate suspend/deep resume separately before stable promotion.
- do not re-enroll and do not alter matcher/threshold unless healthy rel43 captures reach the matcher and provide concrete evidence.

### rel43 cleanup/final software checkpoint
- multi-distro rel43 matrix finished: Debian/Fedora/openSUSE/Arch/Alpine all PASS build + fprintd ABI.
- all temporary validation containers exited and none remain.
- /tmp/gxfp* logs/work directories removed.
- local rel43 package artifact removed after checksum was recorded.
- makepkg src/pkg/build residues removed.
- installed package integrity: 45 files, 0 modified.
- systemctl --failed: 0 units.
- pacman orphan list: empty.
- periodic warm-keepalive timer: not found/inactive.
- repository working tree: CLEAN.
- no untracked files reported by git clean -nd.
- no fingerprint build directories remain under the repo.
- current package on disk: libfprint-goodix51a0 1.94.100.goodix51a0-43.
- installed binary contains rel43 protocol auto-calibration marker.
- three enrollments and PMK cache remain intact.
- password PAM remains independent; dedicated fingerprint PAM is unchanged.

Final next action:
- user must perform one full manual reboot; a lockscreen-only test is not sufficient because current fprintd PID 728 still predates rel43 installation.
- at the greeter, try an enrolled fingerprint normally; password remains available.
- after login, inspect rel43 logs before any service restart.
- success criteria: protocol auto-calibration may rise only on real protocol misses, WakeupMCU succeeds, Identify reaches DETECTED_HOLD, same-press scores appear, and login succeeds without any persistent timing files being recreated.
- only after cold-boot success should deep-suspend/resume be tested and stable/main promotion considered.

## Update 2026-09-24 — rel44 retry-calibrated capture candidate

rel43 cold-boot runtime result: FAILED at matcher, NOT transport.
- Boot: 2026-09-24 18:56:26 CEST.
- protocol auto-calibration worked: 100 -> 150 -> 200 -> 250 -> 300% in RAM.
- WARM_REBASE succeeded.
- exact Windows WakeupMCU succeeded.
- Identify reached READY and DETECTED_HOLD normally.
- three physical presses were captured; each press produced three same-press images.
- matcher scores remained below threshold: press1 best=4, press2 best=3, press3 best=3, threshold=7.
- every first GET_IMAGE on each physical press was swallowed and succeeded only on transport retry.
- password fallback remained functional.

Root cause found in rel42/43 capture adaptation:
- capture_retry_seen is image-local and is reset by each same-press RetryCaptureIMG.
- therefore the first image's successful transport retry was forgotten before final cleanup.
- gx_capture_pacing_success() never saw the retry evidence, so capture gap stayed at nominal 100%/30ms even though every physical press needed a retry.
- rel40's successful boot had entered authentication with capture pacing 250%, and its second physical press reached score 7.

rel44 change:
- preserve a press-level OR of capture_retry_seen across all same-press images.
- after a successfully completed real finger press that needed any GET_IMAGE retry, calibrate the NEXT physical press immediately.
- target = max(current + 50 points, protocol timing - 50 points), bounded to 100..300 and protocol-derived floor capped at 250.
- on Pegasus protocol=300% therefore first retry-assisted press calibrates capture pacing 100% -> 250% for the next press, reproducing the useful rel40 runtime state without disk persistence.
- controllers at nominal protocol timing still adapt only one 50-point step.
- clean captures still decay after 8 clean presses.
- lifecycle/prewarm failures still cannot train capture pacing.
- removed obsolete capture_retry_streak state and obsolete 3-press escalation constant.
- threshold remains 7; templates/enrollments/matcher/WakeupMCU/WARM_REBASE/PLM unchanged.

rel44 validation:
- full fingerprint/research suite PASS.
- test-fingerprint-tooling.py PASS.
- test-goodix51a0-boot-binding.py PASS.
- new retry-assisted capture calibration source gate PASS.
- reproducible native Arch libfprint build PASS.
- release biometric dump hook ABSENT.
- package SHA256 c36abf1f681d9549e3bdd392f8ddd71cf5456f59d7f995801f7a840a60676e32.
- Debian stable/glibc build + fprintd ABI smoke PASS.
- Alpine edge/musl build + fprintd ABI smoke PASS.
- portable installer unchanged from rel43, whose full Debian/Fedora/openSUSE/Arch/Alpine matrix passed.

Installed-on-disk:
- libfprint-goodix51a0 1.94.100.goodix51a0-44.
- package integrity: 45 files, 0 modified.
- enrollments intact: right-index, left-index, right-middle.
- legacy timing files ABSENT.
- current live fprintd PID 722 started 18:56:33, before rel44 installation, so it still executes rel43 mapped in memory.

Git:
- branch fingerprint-rel44-retry-calibrated-capture.
- code commit af7ca79320f50b2bcdad3faead0eafb06a447a7c.
- do not push/promote stable before cold-boot runtime acceptance.

Next gate:
- USER-INITIATED full reboot, not lockscreen-only.
- at greeter use an enrolled finger normally.
- expected: protocol RAM auto-calibration, first physical press may require GET_IMAGE retry, then log 'capture pacing calibrated by retry-assisted finger frame: 100% -> 250%' and next physical press runs with 75ms capture gap.
- success requires matcher score >=7 and fingerprint PAM session open.
- if cold boot passes, then validate deep suspend/resume before stable promotion.

## Update 2026-09-24 — rel45 FDT touch bitmap + frozen-resume rebuild

Latest useful GitHub evaluation reviewed:
- Sigfrodr/libfprint-goodixtls#5, szlukabence comment 5819097488.
- GXFP51A0 MateBook 13 2020: 121 separate presses, 4 fingers, real GodsQuantum SIGFM matcher.
- genuine n=123 mean=20.35; impostor n=1089 mean=2.051; impostor max=6.
- shipped threshold 7: 0/1089 impostor comparisons accepted; 17/123 genuine single presses below 7.
- this is NOT a population FAR estimate, but it supports keeping threshold 7 and using retry/multi-press rather than lowering security.

rel44 latest runtime sequence:
- one cold boot at 22:44 succeeded: first biometric image score 11/7 and PAM session opened.
- next cold boot at 22:59 failed before DETECTED_HOLD: WARM_REBASE + WakeupMCU succeeded, but the finger was not recognized by analog-only FDT before PAM timeout.
- boot-prewarm ordering was verified correct: it finished before plasmalogin/display-manager; this was not a greeter race.
- deep/S3 on the same boot exposed a separate race: after resume the existing worker started too late.
- raw fprintd resume log showed calibration waiting for sensor clear at mean=225 while the user was already touching the reader.
- subsequent GET_IMAGE/TLS timed out and the stale/dead post-S3 session could not be rebuilt before unlock.

rel45 FDT correction:
- the existing FDT parser already extracted byte 5 touchflag but GXFP51A0 runtime ignored it.
- sibling GDIX51C0 driver for the same 0x2504/ChicagoHS silicon defines touchflag low six bits as per-zone touch bitmap and uses >=5 active zones as a finger.
- rel45 adds gx_fdt_probe_ex(), returns touchflag, masks low six bits and requires >=5 zones for the hardware finger signal.
- detection now uses: hardware touch bitmap OR existing analog drop/absolute floor.
- all sensor-clear/background/baseline paths require hardware NOT-touched as well as analog-clear, preventing contaminated ImageBase/background.

rel45 deep-resume correction:
- removed the asynchronous sleep.target service + worker pair that raced the lockscreen.
- package now installs one /usr/lib/systemd/system-sleep/gxfp51a0-resume-prewarm hook.
- only the post suspend/hibernate phase runs the existing standard fprintd Claim helper.
- systemd keeps user.slice frozen while system-sleep hooks execute, so calibration/rebuild completes before the user session can race it with a finger press.
- helper now has explicit busctl --timeout=45s under an outer 50s bound; the hook itself is bounded to 55s.
- no fprintd restart, no periodic keepalive, no VerifyStart/EnrollStart synthetic action.
- portable installer keeps systemd optional and removes obsolete old resume unit files during migration.

Validation:
- full fingerprint/research suite: PASS.
- test-fingerprint-tooling.py: PASS.
- test-goodix51a0-boot-binding.py: PASS.
- bash -n on install-linux/install-arch/resume helper/system-sleep hook: PASS.
- native Arch reproducible libfprint build: PASS, no final C warnings.
- release biometric dump hook: ABSENT; build sensor/GPIO/MMIO/firmware actions: NONE.
- Debian stable/glibc exact rel45 build + fprintd ABI: PASS.
- Alpine edge/musl exact rel45 build + fprintd ABI: PASS.
- package SHA256: 4d304f02c4828e917f78967c6110984fa462318dc729676bf83d9899bb834d14.
- Git branch fingerprint-rel45-fdt-resume-race; code commit 42a13de3bfe2587bb8c21b3b5c7a4857f6c07ae6.

Installed-on-disk:
- libfprint-goodix51a0 1.94.100.goodix51a0-45; 43 files, 0 modified.
- new system-sleep hook + resume helper present and executable.
- old resume service, worker and sleep.target wants link absent.
- timing persistence files absent; three enrollments intact; zero failed systemd units.
- live fprintd PID 726 started 22:59:39, before rel45 install, so it still executes rel44. rel45 has NOT had a biometric runtime test.

Next gate: user-initiated FULL REBOOT and cold graphical fingerprint login only. Do NOT combine this first rel45 acceptance test with deep sleep. If cold boot succeeds, inspect logs first; only then perform the deep/S3 acceptance test.

### Chronology correction 2026-09-24 late evening
- The user's cold-login failure after the 22:59 reboot was rel44 runtime, not rel45.
- Current fprintd PID 726 started at 22:59:39.
- rel45 package installation occurred later at 23:32:13 (pacman log: rel44 -> rel45).
- Therefore the deep/S3 failure around 23:04 was also rel44 runtime.
- rel45 has still never been loaded by fprintd or runtime-tested.
- rel45 on-disk audit after install: 43 package files, 0 modified; new /usr/lib/systemd/system-sleep/gxfp51a0-resume-prewarm executable; helper executable; legacy resume service/worker/wants files absent; legacy timing files absent; right-index/left-index/right-middle enrollments intact; 0 failed systemd units; repo clean.
- Next test MUST be one full user-initiated reboot to load rel45, followed only by cold graphical fingerprint login. Do not deep-suspend before reading that boot's logs.

## Update 2026-09-24 late — rel46 native S3 recovery candidate

rel45 cold boot: SUCCESS.
- Real rel45 fprintd started 23:41:52 after boot 23:41:45.
- cold login detected finger via hardware FDT bitmap: touch=0x3e, zones=5, mean=274, drop=79.
- first biometric image matched at score 7 / threshold 7 and fingerprint PAM opened the session.

rel45 deep/S3 runtime: FAILED, root cause isolated.
- suspend entry deep: 23:46:32; resume: 23:46:38.
- systemd-sleep explicitly logged: user sessions remain UNFROZEN because SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=0.
- rel45 external /usr/lib/systemd/system-sleep hook started after resume but its fprintd Claim immediately returned busy/failure.
- KDE lockscreen already owned/used the auth path, so the external D-Bus Claim raced the desktop instead of prewarming ahead of it.
- password symptoms line up exactly with that race: pam_unix conversation failed immediately after resume, then KDE logged repeated 'Authentication attempt too soon'. This explains the observed need to enter the password twice.
- therefore the rel45 assumption 'system-sleep hook runs while user.slice is frozen' is false on this Pegasus/systemd configuration.

rel46 architecture:
- removes the external resume-prewarm helper and system-sleep hook completely.
- no systemd/logind/D-Bus resume dependency remains.
- keeps the libfprint suspend/resume vfuncs as one lifecycle signal.
- makes CLOCK_BOOTTIME-vs-CLOCK_MONOTONIC sleep detection independent of warm_valid, so it still works if the suspend vfunc already invalidated warm state.
- every active WAIT_ON and WAIT_OFF poll checks for a sleep delta >250 ms before touching FDT.
- if S3 crossed while an authentication remained open, the SSM jumps directly back to GX_ST_SESSION.
- gx_session_start handles force_cold_reset by abandoning stale host TLS state, resetting capture pacing to nominal, hard-resetting the MCU, running full gx_cold_prepare (TLS + clean background + FDT + fresh sleep-clock baseline), then WakeupMCU, all inside the existing authentication operation.
- this prevents stale post-S3 FDT/GET_IMAGE traffic and avoids competing with password PAM.
- matcher, threshold 7, touchflag detection, WakeupMCU, WARM_REBASE, templates/enrollments and PLM 3.4 are unchanged.

rel46 validation:
- full fingerprint/research suite PASS.
- native resume recovery source gate PASS.
- portable installer source gate PASS.
- test-fingerprint-tooling.py PASS.
- test-goodix51a0-boot-binding.py PASS.
- reproducible native Arch libfprint build PASS.
- package contains native S3 recovery markers and contains NO external resume hook.
- Debian stable/glibc exact-source build + fprintd ABI PASS.
- Alpine edge/musl exact-source build + fprintd ABI PASS.
- release biometric dump hook ABSENT; build active sensor/GPIO/MMIO/firmware actions NONE.
- package SHA256: 27e36332e147a2afc244456fa8df2cd88572286c1a80a7cd81aba1a392407716.

Installed-on-disk:
- libfprint-goodix51a0 1.94.100.goodix51a0-46; 40 files, 0 modified.
- all rel45 external resume hook/helper paths ABSENT.
- three enrollments intact.
- legacy timing persistence files ABSENT.
- 0 failed systemd units.
- live fprintd PID 733 started 23:41:52, before rel46 install, so it still executes rel45 mapped in memory.
- rel46 has NOT yet been runtime-tested.

Git:
- branch fingerprint-rel46-native-s3-recovery.
- code commit 4771887f2dfe738bce77b7b669dee4f9ff05944f.
- do not push/promote stable before cold + deep runtime acceptance.

Next gates:
1. user-initiated full reboot; validate cold graphical fingerprint login under rel46.
2. only after cold succeeds and logs are read, perform one normal deep/S3 suspend-resume and fingerprint unlock.
3. if that succeeds, perform the race test: deep/S3 then touch fingerprint immediately as lockscreen appears.
4. confirm password remains single-attempt/independent and no 'Authentication attempt too soon' race.

## Update 2026-09-25 — rel47 adaptive Identify / pose-budget candidate

True rel46 cold-boot runtime result: FAILED at biometric matching, not transport.
- Boot: 2026-09-25 00:13:00 CEST.
- rel46 fprintd started 00:13:07, so this was a real rel46 runtime test.
- protocol timing auto-calibrated 100 -> 150 -> 200 -> 250 -> 300% in RAM.
- WARM_REBASE succeeded (idle≈354, floor≈330).
- exact WakeupMCU succeeded.
- hardware touchflag/FDT detected all three physical presses.
- every first GET_IMAGE needed the bounded transport retry, but authenticated images were produced.
- pose scores: first PAM attempt 4/4/4, second 3/3/3, third 3/3/3; threshold remained 7.
- password fallback succeeded.
- therefore rel46 S3 architecture did not cause the cold failure; the false reject was pose/matcher-quality variance.

Relevant community evidence:
- szlukabence's latest fp_eval run against this driver's real matcher: 121 poses / 4 fingers.
- threshold 7 retained 0/1089 impostor accepts.
- about 13.8% of unique genuine poses were below threshold, confirming pose variance is the dominant FRR source.
- no threshold lowering is justified.

rel47 strategy:
- keep threshold 7 and independent-image decisions; no score fusion.
- seed capture pacing before the first biometric press from protocol timing already measured during cold preparation.
- mapping is bounded/process-local: protocol 300% -> capture 250%; fast/nominal controllers remain at 100%; nothing is persisted.
- add GX_REPOSE_SCORE_CUTOFF=4.
- if the first usable image of a pose scores <=4, stop wasting two same-pose recaptures and request a fresh physical placement.
- scores 5-6 still get Windows-style same-press RetryCaptureIMG because they are close to threshold.
- quality-gate rejection still gets same-press recapture.
- Identify now uses the same fixed 3-physical-press budget internally as Verify instead of reporting no-match after the first pose.
- Identify success remains immediate when one independent image reaches >=7.
- Identify failure is reported only after the bounded 3-press budget.
- matcher, templates, enrollments, FDT touchflag, WakeupMCU, WARM_REBASE, PLM 3.4, and native rel46 S3 recovery are unchanged.

rel47 software validation:
- git diff --check PASS.
- full fingerprint/research suite PASS.
- adaptive Identify pose-budget source gate PASS.
- native S3 recovery gate PASS.
- Verify+Identify fixed-budget gate PASS.
- portable installer gate PASS.
- test-fingerprint-tooling.py PASS.
- test-goodix51a0-boot-binding.py PASS.
- reproducible native Arch libfprint build PASS.
- artifact gate updated to require both Identify success and bounded-failure paths; PASS.
- RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT.
- build active sensor/GPIO/MMIO/firmware actions NONE.
- Debian stable/glibc exact-source build + fprintd ABI PASS.
- Alpine edge/musl exact-source build + fprintd ABI PASS.
- package SHA256: d1347ae1622032555a6e9bf4236adb33c843d86445eebf39c5b1b4b6f68e6d26.

Installed-on-disk:
- libfprint-goodix51a0 1.94.100.goodix51a0-47; 40 files, 0 modified.
- fprintd 1.94.5-2.1; plasma-login-manager 6.7.5-3.4.
- three enrollments intact: right-index, left-index, right-middle.
- legacy protocol/capture timing files ABSENT.
- 0 failed systemd units.
- live fprintd PID 724 started 00:13:07 before rel47 installation, so it still executes rel46 mapped in memory.
- rel47 has NOT yet been runtime-tested.

Git:
- branch fingerprint-rel47-adaptive-identify.
- code commit f44fedd4466493ca582bac0a8ca6cde3a2ee2c51.
- do not push/promote stable before cold + S3 runtime acceptance.

Next gates:
1. user-initiated full reboot; cold graphical fingerprint login under rel47 only.
2. inspect logs before any service restart.
3. expected: capture pacing seeded from protocol calibration (likely 250% on Pegasus), low-score <=4 pose causes quick reposition instead of 3 repeated weak images, success reports immediately at >=7.
4. only after cold succeeds: normal deep/S3 resume test.
5. after deep succeeds: immediate-touch race test.

## Update 2026-09-25 morning — rel47 cold failure + PLM 3.5 password-preemption fix

True rel47 cold-boot runtime:
- boot: 2026-09-25 08:34:37 CEST.
- fprintd started 08:34:44 with libfprint-goodix51a0 1.94.100.goodix51a0-47.
- transport/session path healthy: protocol auto-calibration reached 300%, WARM_REBASE succeeded, WakeupMCU succeeded, FDT/touchflag detected every press, GET_IMAGE retry recovered each first image.
- rel47 low-score reposition logic worked: each weak first image (4,3,3) ended the same-press capture after one image and requested a new physical pose.
- first driver Identify operation consumed exactly three physical poses; best scores remained 4/7, 3/7, 3/7, so biometric match legitimately failed at threshold 7.
- threshold 7 remains unchanged; templates/enrollments remain valid because prior rel44/45 boots matched the same enrolled data at 11/7 and 7/7.

Double-password root cause:
- pam_fprintd was still configured max-tries=3 while rel47 already owns a 3-physical-pose budget internally, so PAM could restart the full driver Identify operation and multiply one login into many presses.
- at 08:35:06 an intermediate rejected fingerprint pose generated Auth::ERROR_AUTHENTICATION.
- PLM 3.4 Display::slotAuthError() incorrectly emitted loginFailed immediately for that intermediate message although the fingerprint helper remained active.
- the greeter therefore cleared its fingerprint-active state while plasmalogin-helper still owned Auth.
- at 08:35:18 the first password Login reached the daemon; startAuth() logged 'Existing authentication ongoing, aborting', so the submitted password was discarded without being checked.
- after the fingerprint helper timed out/exited, a second password submission at 08:35:23 succeeded.

PLM 6.7.5-3.5 fix:
- new patch 0006-fingerprint-password-preemption.patch.
- dedicated fingerprint PAM changed to pam_fprintd max-tries=1 timeout=15 because the driver itself already owns the bounded pose budget.
- intermediate Auth::ERROR_AUTHENTICATION messages from plasmalogin-fingerprint remain visible but are no longer emitted as terminal loginFailed while the helper is active.
- cancellation/preemption results are suppressed until the helper has actually stopped.
- daemon-side safety net: if a password Login nevertheless arrives while plasmalogin-fingerprint is active, the daemon stores the already-submitted socket/user/password/session, stops the fingerprint helper, then launches normal password PAM automatically when helper exit is observed.
- first submitted password can therefore no longer be thrown away solely because fingerprint auth is still draining.
- existing client-side CancelLogin/LoginCancelled path remains.
- password PAM remains independent and contains no pam_fprintd.

PLM 3.5 validation:
- source safety test PASS: single PAM fingerprint operation + password preemption.
- full fingerprint/research suite PASS.
- test-fingerprint-tooling.py PASS.
- test-goodix51a0-boot-binding.py PASS.
- real KDE Plasma Login Manager 6.7.5 source build PASS.
- built package SHA256: 9946e44f7e058667730ed9b03df192b65009c0c0c7764a7ad9265ad3e6602a97.
- built package contains /usr/lib/pam.d/plasmalogin-fingerprint with max-tries=1 timeout=15.
- built /usr/bin/plasmalogin contains server-preemption markers.
- installed plasma-login-manager 6.7.5-3.5 package integrity: 210 files, 0 modified.
- libfprint-goodix51a0 rel47 integrity: 40 files, 0 modified.
- temporary build dependencies cmake, ninja, extra-cmake-modules, cppdap and rhash were installed only for the build and then fully removed; no package orphans remain.

Runtime boundary:
- current plasmalogin PID 905 started 08:34:49 before PLM 3.5 installation, so it still executes PLM 3.4 mapped in memory.
- current fprintd PID 724 started 08:34:44 and already executes rel47.
- PLM 3.5 has NOT yet been runtime-tested.

Git:
- branch fingerprint-rel47-adaptive-identify.
- rel47 driver commit f44fedd4466493ca582bac0a8ca6cde3a2ee2c51.
- PLM 3.5 password-preemption commit f7e733988071ec48e4c8bc9bab47e2578233c350.

Next gate:
1. user-initiated full reboot to load PLM 3.5.
2. at cold greeter, try fingerprint normally; driver budget is at most 3 physical poses for the single PAM fingerprint operation.
3. if fingerprint succeeds, report success and inspect logs.
4. if fingerprint does not succeed, type the password ONCE and press Enter ONCE even if fingerprint UI still appears active; wait for the transition and do not submit it a second time unless the UI explicitly reports the password itself was wrong.
5. success criterion for fallback: no 'Existing authentication ongoing, aborting'; expected either client CancelLogin flow or daemon marker 'Password login preempts active fingerprint authentication' followed by 'Fingerprint helper stopped; starting queued password authentication', then one successful password PAM session.
6. do not deep-suspend until this cold-login + single-password fallback gate is validated.

## Update 2026-09-25 — final candidate: rel47 + PLM 3.7 true concurrent auth

Final architecture installed on disk:
- libfprint-goodix51a0 1.94.100.goodix51a0-47.
- fprintd 1.94.5-2.1.
- plasma-login-manager 6.7.5-3.7.
- package integrity: libfprint 40/40 files unchanged; PLM 210/210 unchanged.
- enrollments intact: right-index, left-index, right-middle.
- legacy persistent timing files absent.
- rel45 external resume-prewarm hooks absent; S3 recovery remains driver-native.
- no package orphans; temporary PLM build dependencies removed after build.

PLM 3.7 final-candidate behavior:
- password and fingerprint use two independent Auth/helper workers.
- both workers share exactly one prepared user/session/VT context.
- typing a password never cancels fingerprint.
- submitting password starts normal password PAM while fingerprint remains active.
- fingerprint can still win after password text has already been entered.
- first successful authenticator atomically wins; the losing helper is stopped.
- losing helper session results are ignored, preventing duplicate sessions.
- failure of password does not terminate fingerprint; failure of fingerprint does not terminate password.
- each fingerprint PAM operation is bounded: max-tries=1 timeout=15 because the driver owns its 3-pose budget.

Continuous fingerprint availability:
- after a bounded fingerprint no-match/timeout, PLM rearms a new fingerprint attempt after 900 ms while the greeter remains visible.
- password stays independently usable during and between fingerprint attempts.
- changing user/session cancels the old fingerprint worker and restarts against the new context.
- retry timer stops when the login UI disappears.
- this satisfies the target: both unlock methods stay available until one succeeds.

Sigfrodr issue #5 follow-up:
- newest comment added fp_eval --backend-so ABI v1 for real driver matchers.
- repo now contains fingerprint/research/eval/gq_sigfm_fpeval.c + builder + synthetic ABI smoke.
- adapter exports fpeval_extract/fpeval_score/fpeval_free/fpeval_name and executes the exact shipped goodix_sift.c + fastbrief/sigfm.c matcher.
- source and synthetic ABI tests PASS.
- this is evaluation-only; release driver still has no biometric capture dump hook and no network/data export.
- threshold remains 7. Do not lower it: contributor validation observed impostor max 6, so threshold margin is intentionally preserved.

Validation:
- full fingerprint/research suite PASS, including native S3 recovery, bounded Identify/Verify, continuous concurrent PLM auth, and real SIGFM fp_eval ABI.
- test-fingerprint-tooling.py PASS.
- test-goodix51a0-boot-binding.py PASS.
- PLM 6.7.5-3.7 full KDE build PASS.
- final PLM package SHA256: 1968bc837a94d0e8eb1e850a59cd8d06dc8688cc2394d1c9058ee20ae83a64b2.
- Git branch fingerprint-final-plm37.
- concurrent-auth commit 9de46b1e61a554662692be32365d54a8e09178ea.
- fp_eval adapter commit 2b088436458b2404eeb0eeffb0c70dcec153a2cb.

Runtime boundary:
- current plasmalogin PID 914 entered 09:51:53, before PLM 3.7 installation, so it still executes the old mapped daemon until reboot.
- current fprintd PID 726 entered 09:51:47 and executes rel47.
- PLM 3.7 has not yet been runtime-tested.
- next gate is one user-initiated full reboot, then cold-login tests for fingerprint success, password success while fingerprint remains active, and fingerprint success after password text has already been typed.
- only after those pass: deep/S3 resume, then immediate-touch resume race, before stable/main promotion.


---

# Update 2026-09-26T00:06:34+02:00 — rel48 ACK-safe transport recovery

Canonical detailed handoff:
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/handoff/HANDOFF_2026-09-26_REL48_ACK_SAFE_PENDING_RUNTIME.md`

Code commit:
`5f20a06 fix(fingerprint): recover safely after accepted image timeout`

Current branch:
`fingerprint-rel48-ack-safe-recovery`

Installed on disk:
- `libfprint-goodix51a0 1.94.100.goodix51a0-48`
- `plasma-login-manager 6.7.5-3.7`

Runtime intentionally still old until human reboot:
- fprintd PID 726 unchanged since 2026-09-25 09:51:47 CEST.
- it maps the old rel47 library as `(deleted)`.
- rel48 was installed with `pacman -U --noscriptlet`.
- no physical rel48 test has happened yet.

rel48 fixes:
1. no replay of an already accepted GET_IMAGE after TLS-image timeout; force full session recovery;
2. image TLS GCM/authentication failure now forces the same recovery in normal, cleanup and same-press capture paths;
3. the original bounded retry remains only when neither ACK nor TLS proves command acceptance.

Matcher is deliberately unchanged:
- SIGFM family unchanged;
- threshold 7 unchanged;
- 20-view enrollment unchanged.

Latest external validation:
- Sigfrodr/libfprint-goodixtls#5 comment 5834809532 publishes the gq_sigfm adapter and an 8-bit rerun essentially matching the direct matcher distributions.
- comment 5839233957 confirms the adapter was merged upstream and the ABI is faithful.
- impostor maximum remains 6 against threshold 7, so do NOT lower the threshold; multi-user pooled data is still needed.

Validation:
- complete `make -C fingerprint/research test`: PASS;
- boot-binding source test: PASS;
- reproducible libfprint v1.94.100 build: PASS;
- package integrity after install: 40 files, 0 modified;
- package SHA256: `e7faa5e10b7e6579037a2aebe858c1fd4a834d42c900a8a3b0090b66002ff8a5`.

NEXT:
- no automatic reboot;
- Arezki manually reboots;
- first test is normal graphical login, with password still concurrently usable;
- report `rel48 cold OK` or `rel48 cold échoué`;
- inspect that new boot journal before any further code change.

---

# Update 2026-09-26 03:05 CEST — PLM 3.8 greeter QML recovery

First rel48 reboot showed wallpaper + cursor but no login controls. Current-boot journal proved this was PLM 3.7 QML, not libfprint: Login.qml:38 rejected QQmlTimer as a direct child because SessionManagementScreen expects QQuickItem children.

Fix:
- added 0009-fix-retry-timer-qml-ownership.patch;
- plasma-login-manager bumped 6.7.5-3.7 -> 6.7.5-3.8;
- retry timer is now an object property, not a direct visual child;
- concurrent password/fingerprint design is otherwise unchanged.

Validation:
- patched Login.qml qmllint RC=0;
- full KDE/CMake build PASS, including QML cache generation;
- full fingerprint research suite PASS;
- installed PLM 3.8 integrity: 210 files, 0 modified;
- restarted ONLY plasmalogin.service;
- fprintd PID stayed 737, so rel48 runtime was not restarted;
- post-fix journal has no Type Login unavailable / QQmlTimer / QQuickItem fatal error;
- greeter now sends FingerprintLogin and rel48 reaches IDENTIFY_TRACE physical press 1/3 READY.

The first post-repair automatic fingerprint attempt timed out because no finger was presented. Human biometric success and password concurrency still need the user test. Temporary build dependencies and build trees were removed.

---

# Update 2026-09-26 11:49 CEST — rel48 cold boot VALIDATED

Human result: fingerprint login SUCCESS after a full reboot.

Current boot evidence:
- boot: 2026-09-26 11:46 CEST;
- plasma-login-manager 6.7.5-3.8;
- libfprint-goodix51a0 1.94.100.goodix51a0-48;
- fprintd PID 739 started in this boot, so rel48 is genuinely loaded;
- gxfp51a0 boot-prewarm completed before the display manager;
- PLM greeter loaded normally with no fatal QML error.

Successful auth path:
- 11:47:05 PLM received FingerprintLogin;
- WARM_REBASE succeeded;
- WakeupMCU write completed;
- physical press 1/3 became READY then DETECTED_HOLD;
- first GET_IMAGE produced neither ACK nor TLS, so the allowed bounded retry 2/2 ran;
- retry succeeded;
- SIGFM Identify score = 23, threshold = 7, candidate = 0;
- same-press completed after one image;
- PLM logged: Authentication race won by fingerprint;
- PAM opened plasmalogin-fingerprint session for arezki;
- graphical Wayland session started successfully.

Critical rel48 validation:
- old unsafe marker 'ACK arrived but TLS image timed out; retrying once' is ABSENT;
- no accepted-command late-TLS replay occurred;
- no 'not replaying accepted command' recovery was needed on this cold boot;
- no TLS digest/GCM failure;
- no capture transport desync;
- no Type Login unavailable / QQmlTimer / QQuickItem greeter failure.

Interpretation:
- the safe no-evidence retry path is proven functional in real cold-login use;
- matcher margin was strong on this press: 23 vs threshold 7;
- rel48 + PLM 3.8 cold graphical fingerprint login is now human-validated.

Remaining acceptance gates before final promotion:
1. verify password remains usable while fingerprint is actively waiting (human test);
2. perform one deep suspend/S3 resume and fingerprint login;
3. inspect that resume journal for safe recovery and absence of accepted-command replay / TLS digest failure.

Do not change matcher threshold, enrollments, FDT, WakeupMCU, PLM dual-auth architecture, or GPIO behavior based on this successful cold test.

---

# Update 2026-09-26 12:10 CEST — S3/password validated; rel49 KDE PAM-delay fix

Human tests:
- real ACPI S3/deep suspend-resume completed;
- user reported two physical finger placements after resume;
- separate password unlock succeeded.

S3 journal interpretation:
- suspend was genuine PM suspend entry (deep) / ACPI S3;
- fprintd PID 739 survived the entire suspend/resume;
- after resume, calibration logged mean=229 floor=340 before READY;
- this strongly indicates the first physical touch occurred while the driver
  still needed a finger-off calibration baseline;
- at 11:51:38.904 the driver announced IDENTIFY press 1/3 READY;
- the first pose actually captured then matched immediately:
  score=11, threshold=7, candidate=0;
- no second matcher pose was needed by the driver.

Transport/lifecycle result:
- one no-evidence GET_IMAGE retry (neither ACK nor TLS) was used safely;
- no accepted-GET_IMAGE replay;
- no TLS digest/GCM failure;
- no capture transport desynchronisation;
- no external resume helper was involved.
Thus rel48 passed its intended deep-S3 recovery gate.

KScreenLocker 6.7.5 separately logged:
- pam_unix(kde:auth) conversation failed after resume;
- "Authentication attempt too soon. This shouldn't happen!".
Source audit showed the rel32/v3 QML heartbeat was a partial backport from a
newer KDE authenticator architecture. On 6.7.5 it can call
startAuthenticating() during the old PAM fail-delay and provides no useful
fingerprint rearm while the authenticator state is still Authenticating.

rel49 therefore changes integration only:
- KDE helper marker becomes window-ready fingerprint integration v4;
- keeps the 25 ms Window.window startup gate;
- removes only the custom 1-second heartbeat block;
- v1/v2/v3 migrations remain reversible;
- helper --remove still restores stock structure;
- targeted KDE test, native-resume test, boot-binding test and full research
  suite pass.

Package validation:
- built libfprint rel49 SHA equals installed rel48 library SHA exactly:
  c1a702c28cadef536df29f2519bd7c63adf0fb30cdad551079d398e37dd1ab8c;
- libfprint binary is therefore byte-identical rel48 -> rel49;
- rel49 package installed with --noscriptlet;
- fprintd PID/timestamp stayed 739 / 11:46:56;
- helper v4 applied explicitly;
- live LockScreenUi.qml qmllint RC=0;
- fingerprint package integrity: 40 files, 0 modified.

GitHub refresh:
- Sigfrodr/libfprint-goodixtls issue #5 has no newer comment after
  Sigfrodr's 2026-09-25 20:37 UTC message already recorded;
- latest gq_sigfm evidence remains ABI-faithful and still does NOT justify
  lowering threshold 7 or changing the matcher;
- no newer GXFP51A0/GodsQuantum issue update was found.

Next human gate after rel49:
1. normal lock -> password unlock, preferably promptly;
2. normal lock -> one fingerprint unlock;
3. later, one more S3 resume test while waiting for the fingerprint prompt/READY
   before touching the reader, to distinguish readiness latency from recognition.
No re-enrollment is indicated.

---

## Update 2026-09-26 12:34 CEST — rel50 installed, pending human lock/S3 validation

Trigger:
- normal lock fingerprint failed; password succeeded;
- real S3 resume fingerprint did not react to multiple touches.

Exact diagnosis:
- normal lock DID start fprintd and captured multiple physical poses;
- six observed usable images scored 3/7, with safe no-ACK/no-TLS GET_IMAGE retry;
- no accepted-GET_IMAGE replay, GCM/digest failure or transport desync;
- rel47's score<=4 shortcut discarded same-press images 2/3 on every weak pose;
- historical rel40 runtime proved a later image from the same physical press can
  rescue authentication (image 2 reached threshold 7);
- after the later S3 resume there were ZERO fprintd log entries before password
  unlock: KScreenLocker 6.7.5 had not rearmed fingerprint at all.

rel50 changes:
- threshold stays 7; matcher/SIGFM/template format/enrollments unchanged;
- restores all 3 independent same-press images for every non-matching usable
  physical pose; scores are never fused;
- retains fixed 3-physical-pose driver budget;
- KDE helper v5 uses SessionManagement.resumingFromSuspend();
- resume rearm is one-shot: immediate if authenticator is idle, otherwise waits
  for the old PAM state transition and starts once;
- no periodic heartbeat, external suspend hook, daemon, persistent timer or
  timing file added.

Validation:
- targeted KDE migration/rollback test PASS;
- qmllint on v5-patched real LockScreenUi.qml PASS;
- full fingerprint/research suite PASS;
- boot-binding/native lifecycle source test PASS;
- reproducible rel50 build PASS;
- artifact gates: dump hook absent, active sensor IO/GPIO/MMIO/firmware actions
  during build NONE;
- package SHA256:
  1e7165bf6c0bf289839eedda01ffd7ba6a6d0e9828019f610972d081c3c304d7;
- installed libfprint-goodix51a0 1.94.100.goodix51a0-50;
- fprintd restarted intentionally only to load rel50, PID 27787 at 12:33:12;
- QML v5 applied live and qmllint PASS;
- enrollments remain right-index, left-index, right-middle;
- normal boot-prewarm helper run once after daemon restart to remove the
  artificial cold-daemon penalty from the next human test.

Important PAM decision:
- /usr/lib/pam.d/kde-fingerprint still uses distro default pam_fprintd retry
  policy. Do NOT force max-tries=1 yet: KScreenLocker 6.7.5 cannot cleanly
  rearm only the noninteractive fingerprint backend after that terminal PAM
  cycle while leaving password untouched. rel50 should first be validated.

Next human tests:
1. normal lock: touch an enrolled finger immediately when the lock UI is visible;
   do not wait for any hidden READY state. Keep the same placement down long
   enough for same-press recaptures. Password must remain usable.
2. after logs are inspected, user-initiated deep S3; when lock UI appears, touch
   immediately. QML v5 must cause a fresh fprintd operation automatically.
3. inspect logs before any further code change.

---

## Update 2026-09-26 13:17 CEST — rel50 human PASS; rel51 warm-latency candidate

Human rel50 result:
- normal graphical lock fingerprint unlock: PASS;
- user perceived three placements;
- exact journal shows only two driver biometric poses after READY:
  - physical press 1: same-press images 1/2/3 all score 4/7;
  - physical press 2: image 1 score 15/7 -> immediate success.
- the user's apparent extra first placement happened during cold preparation:
  calibration saw finger-present mean=225 before READY.
- rel50 therefore validated both the restored same-press 3-image path and the
  unchanged threshold=7 matcher.

Latency diagnosis:
- greeter process logged at 13:06:03.148;
- driver READY at 13:06:11.917: about 8.77 s later;
- rel50 warm context had last been prepared around 12:33, so the historical
  5-minute GX_WARM_IDLE_TTL_US forced an unnecessary cold rebuild;
- that 5-minute limit was introduced before the current robust S3 boundary and
  full warm FDT+encrypted-GET_IMAGE validation architecture existed.

rel51 design:
- remove only GX_WARM_IDLE_TTL_US / gx_warm_idle_expired();
- ordinary awake wall-clock idle no longer discards a retained TLS/FDT context;
- real S3 is still detected before hardware I/O using
  CLOCK_BOOTTIME-CLOCK_MONOTONIC;
- force_cold_reset still forces cold preparation;
- every retained awake context is still actively validated by FDT plus a fresh
  encrypted background GET_IMAGE (WARM_REBASE);
- warm validation failure still abandons host TLS state, resets MCU and falls
  back to deterministic cold preparation;
- no keepalive, no periodic timer/service, no external resume hook added;
- matcher, threshold=7, templates, enrollments, same-press behavior, QML v5,
  GPIO and PMK/TLS security boundaries unchanged.

Software/build validation:
- full fingerprint/research suite PASS;
- lifecycle/native-resume/boot-binding gates PASS;
- reproducible libfprint v1.94.100 build PASS;
- release biometric dump hook absent;
- build active sensor I/O/GPIO/MMIO/firmware actions NONE;
- package libfprint-goodix51a0 1.94.100.goodix51a0-51;
- package SHA256:
  6d74059cc3636a03303ce94c85d51e1858e9358dcdc36f8f78b7a22da6034e06.

Installed/runtime benchmark:
- rel51 installed and fprintd restarted intentionally to load it;
- fprintd PID 40754, ActiveEnterTimestamp 13:16:13 CEST;
- first cold prewarm Claim after daemon restart: 4.935 s;
- immediate retained-context Claim: 1.834 s;
- second retained-context Claim: 1.830 s;
- WARM_REBASE itself measured 1.744 s then 1.741 s;
- both warm rebases produced idle=352, floor=328.
Thus the normal awake-lock preparation floor is currently ~1.8 s rather than
the previous 5-9 s cold path, without background freshness being skipped.

Important UX interpretation:
- user should still touch immediately when lock UI appears; there is no hidden
  user-facing READY contract.
- on an awake retained context, if a finger is already present during
  WARM_REBASE, the driver intentionally defers rebase and retains the previous
  clean background rather than contaminating it.
- after real S3 a cold rebuild remains required by this sensor, but KDE QML v5
  requests rearm on resumingFromSuspend, allowing preparation to begin during
  graphical wake rather than waiting for user interaction.

Next gate:
1. normal rel51 graphical lock, finger immediately on visible UI;
2. inspect exact greeter->WARM_REBASE/READY/detect/match timeline;
3. then user-triggered S3 test, again touching immediately when UI appears;
4. do not change threshold/enrollments based on latency work.

---

## Update 2026-09-26 — rel51 human lock PASS; rel52 parallel greeter auth installed

Human rel51 normal-lock result: PASS.

Exact rel51 timeline:
- kscreenlocker_greet process visible in journal: 13:55:41.604605;
- WARM_REBASE completed at 13:55:45.717594 in 1753 ms;
- WakeupMCU completed at 13:55:45.773896;
- driver press 1/3 READY at 13:55:45.774067;
- first actual detected physical press at 13:55:48.962514;
- GET_IMAGE used one safe no-ACK/no-TLS retry;
- first captured image scored 13/7 and authenticated;
- only one biometric pose was required.

Latency interpretation:
- greeter-process -> READY was about 4.17 s;
- WARM_REBASE itself was only about 1.75 s;
- therefore roughly 2.4 s were spent before libfprint open/preparation began.
- KDE Plasma 6.7.5 source confirms PamAuthenticators::startAuthenticating()
  returns immediately when state is already Authenticating.
- the historical rel30 experiment also proved a Component.onCompleted direct
  auth call begins fprintd work immediately; its defect was only that the UI
  remained hidden. rel32 fixed the UI by waiting for Window.window, but thereby
  delayed the sensor start as well.

rel52 design (integration-only):
- driver/libfprint is bit-identical to rel51;
- KDE helper v6 calls authenticator.startAuthenticating() immediately from
  Component.onCompleted;
- the existing 25 ms Window.window gate remains and independently controls
  uiVisible/requestActivate;
- when uiVisible later triggers Plasma's stock startAuthenticating() call, KDE
  6.7.5 safely returns because state is already Authenticating;
- resume v5 one-shot rearm remains unchanged;
- no periodic heartbeat/keepalive/timer service is introduced.

Validation:
- helper v6 migration tests PASS from stock, v4, v5 and historical v3;
- helper --remove restores stock test fixture byte-for-byte;
- live/copied QML qmllint PASS;
- full fingerprint/research suite PASS;
- rel52 package SHA256:
  783a83ab296673cfd77d3c4738263ba5e63740c78e5f659dd175ab3eac53efda;
- rel51 live libfprint SHA256 == rel52 packaged libfprint SHA256:
  27d3c8f007bdf9d8113a62b5ab2227c9a6ce098a815c66d98936efc5d4aa415c;
- installed libfprint-goodix51a0 1.94.100.goodix51a0-52;
- fprintd was NOT restarted: PID remains 40754, ActiveEnterTimestamp remains
  13:16:13 CEST;
- package integrity: 40 files, 0 modified.

Next human gate:
1. normal graphical lock;
2. touch immediately when UI appears;
3. inspect greeter -> WARM_REBASE -> READY -> match timestamps;
4. target: sensor preparation should now overlap the ~2.4 s greeter/window
   startup and ideally be READY at or before visible UI;
5. only after this, validate real S3 again.

---

## Update 2026-09-26 15:55 CEST — rel52 failure diagnosed; rel53 installed

User report:
- rel52 normal-looking lock test: fingerprint failed.

Important hidden condition:
- this was NOT an ordinary awake rel52 lock;
- Pegasus had entered a real ACPI S3 deep suspend at 14:44:36 and resumed at
  15:19:40 before the 15:27 rel52 test.

Exact rel52 failure trace:
- rel52 did start fprintd;
- S3 correctly invalidated the warm TLS context, so driver used cold prep;
- user touched immediately when the graphical lock UI appeared;
- cold calibration then repeatedly observed a present finger and correctly
  refused to bake it into the no-finger background:
  - 15:28:00 mean=247, waiting for sensor clear;
  - 15:28:05 contaminated background mean=228 touch=0x3f;
  - 15:28:10 contaminated mean=252;
  - 15:28:17 contaminated mean=218;
- READY was not reached until 15:28:19 after lift/reposition;
- subsequent actual biometric poses scored 4/5/4, then 3/4/4, then 3 and did
  not match.
This proves the remaining UX defect was post-S3 cold calibration with a finger
already held down, not an ordinary rel51/rel52 matcher regression.

KDE resume evidence:
- the pre-existing lock greeter at resume logged
  "Authentication attempt too soon. This shouldn't happen!";
- KScreenLocker 6.7.5 source exposes
  loginFailedDelayStarted(..., const uint uSecDelay) and state Idle/Authenticating.

rel53 driver:
- retains last proven-clean background + FDT baseline in process RAM only when
  an actual S3 boundary invalidates warm TLS;
- sensor TLS/MCU session is still rebuilt cold after S3;
- after new TLS, if FDT already says finger present, first auth bootstraps from
  that pre-S3 clean background rather than waiting for finger-off calibration;
- if finger is absent, normal fresh calibration is unchanged;
- RAM bootstrap is OPENSSL_cleanse'd/freed after adoption;
- unrelated transport recovery clears it explicitly;
- never written to /var, /run or any persistent file;
- threshold 7, matcher, templates, same-press policy and enrollments unchanged.

KDE helper v7:
- retains rel52 early Component.onCompleted authentication for awake locks;
- resume rearm no longer blindly restarts PAM;
- bounded resume-only timer waits for authenticator Idle;
- loginFailedDelayStarted for interactive PAM sets the exact uSecDelay + 50 ms
  scheduling margin before another rearm attempt;
- max state polling window 50 x 100 ms;
- no permanent heartbeat, daemon, keepalive or external sleep hook.

Validation:
- dedicated test_resume_held_finger_bootstrap_source_safety.sh PASS;
- full fingerprint/research suite PASS;
- KDE v7 migration/rollback test PASS;
- copied real QML qmllint PASS;
- native resume, TLS transport, privacy, matcher and same-press tests PASS;
- reproducible package build PASS;
- artifact gates: active sensor I/O/GPIO/MMIO/firmware during build NONE;
- package libfprint-goodix51a0 1.94.100.goodix51a0-53;
- package SHA256:
  70c1e917391d47b0ff0f9e4bd13181add2148c919a67cf32ed1a1dde2c3f422a;
- installed package integrity: 40 files, 0 modified;
- PLM remains 6.7.5-3.8;
- fprintd restarted intentionally to load rel53, PID 72232 since 15:53:37;
- enrollments intact: right-index, left-index, right-middle;
- one boot-prewarm Claim completed successfully at 15:54:29 under rel53,
  establishing a clean warm background for the next S3 bootstrap.

Next human gate:
- user initiates real deep S3;
- when lock UI appears, touch enrolled finger IMMEDIATELY and keep normal
  behavior: do not deliberately wait for READY and do not deliberately lift
  just to satisfy calibration;
- password must remain concurrently usable;
- after result, inspect for:
  "preserved RAM-only clean background for post-S3 held-finger bootstrap",
  "RESUME_BOOTSTRAP finger already present",
  absence of repeated "calibration waiting for sensor clear",
  absence of "Authentication attempt too soon",
  match score and timing.

---

## Update 2026-09-26 — rel53 deep failure diagnosed; rel54 installed

User report:
- `rel53 deep échoué`.

Observed S3 cycles:
- 16:08:23 deep suspend -> 16:19:40 resume;
- 16:21:15 deep suspend -> 16:21:29 resume.

Critical rel53 evidence:
- both resume windows had ZERO fprintd journal activity;
- rel53's driver-side active-S3 recovery and RAM bootstrap never got a chance to
  execute;
- KScreenLocker logged on both resumes:
  - `pam_unix(kde:auth): unexpected response from failed conversation function`
  - `pam_unix(kde:auth): conversation failed`
  - `pam_unix(kde:auth): auth could not identify password for [arezki]`

Root cause:
- Plasma/KScreenLocker 6.7.5 cancels the in-progress PAM conversation from
  `LogindIntegration::prepareForSleep`.
- This is KDE bug 481808.
- KDE MR !340 / commit
  `992f3fa8f4c4ade5dad7df789e1883a5d5e8ac2c`
  ("Don't cancel in-progress authentication on suspend") removes that cancel and
  leaves authentication parked across suspend/resume.

rel54 architecture:
- Goodix driver C source and SOURCE_MANIFEST are byte-for-byte unchanged from
  rel53.
- KScreenLocker 6.7.5 is locally packaged as 6.7.5-1.2 with only the adapted
  upstream 992f3fa8 semantic patch.
- Installed CachyOS version before patch was 6.7.5-1.1.
- Future 6.7.6+ packages naturally supersede local 6.7.5-1.2.
- QML helper is v8:
  - retains early parallel `authenticator.startAuthenticating()`;
  - removes ALL custom resume-rearm QML;
  - no `gxfp51a0ResumeRearmPending`;
  - no resume timer;
  - no `onLoginFailedDelayStarted`;
  - no heartbeat/keepalive/external sleep hook.

Package/build validation:
- official KDE 6.7.5 tarball signature verified. Signing subkey
  B3CB366552540BE06EE9AD9711968C44928CAEFC belongs to already-approved KDE
  main key 0AAC775BB6437A8D9AF7A3ACFE0784117FBCE11D (Bhushan Shah).
- KScreenLocker package: 6.7.5-1.2
  SHA256 83bae55a9def12f20d483b3f3792594d375e1abc4be2456935b6c8ff8bb66dd7.
- libfprint package: 1.94.100.goodix51a0-54
  SHA256 854d4c317d9de2615ef3be51127a75a5b31db1aef35581848e0105152f203a03.
- full fingerprint research suite PASS.
- KScreenLocker suspend-PAM source safety PASS.
- QML v8 stock migration + rel53-v7 migration + rollback PASS.
- native resume lifecycle safety PASS.
- installed `pacman -Qkk`: kscreenlocker 346/346 clean; libfprint 40/40 clean.
- PAM files remain byte-identical to distro versions.
- enrollment labels intact: right-index, left-index, right-middle.
- fprintd restarted after install; PID 90570.
- rel54 prewarm Claim completed successfully at 16:43:23.
- temporary build dependencies removed; no orphan packages remain.

Next HUMAN validation:
1. user triggers a real deep S3;
2. wake normally and use fingerprint immediately; do not alter natural gesture;
3. password must remain concurrently usable;
4. inspect logs after result.

Expected success evidence:
- NO `pam_unix(kde:auth): unexpected response from failed conversation function`;
- fprintd remains active/reachable after resume;
- driver should now get its chance to detect:
  `GXFP51A0 active S3 boundary detected during authentication; scheduling native cold recovery`;
- if a finger is already down during rebuild:
  `GXFP51A0 preserved RAM-only clean background for post-S3 held-finger bootstrap`
  and possibly `GXFP51A0 RESUME_BOOTSTRAP finger already present`;
- normal match score >= unchanged threshold 7.

Do not modify matcher/threshold/TLS/FDT before this rel54 human S3 test.

### rel54 repository finalization

- implementation commit: `20b4a69 fix(lockscreen): carry PAM authentication across S3`
- branch: `fingerprint-rel54-upstream-kscreenlocker-s3`
- pushed to origin.

---

## Update 2026-09-26 19:33 CEST — rel55 installed, pending human validation

User report triggering rel55:
- `rel54 deep échoué`
- user requested stepping back from regressions and a focused rel55.

Reference baseline:
- rel51 is the last human-validated good normal lock release:
  - `rel51 lock OK`
  - window-ready QML v5 startup;
  - one biometric pose;
  - score 13 / threshold 7.
- rel52 introduced direct `Component.onCompleted -> startAuthenticating()`;
  subsequent regressions started from that integration change.

rel54 failure at 18:56:
- greeter appeared at 18:56:16.322;
- deep S3 entered 18:56:17.131, resumed 18:56:22.701;
- ZERO fprintd/GXFP51A0 activity before or after that S3;
- therefore fingerprint auth had not started before sleep and v8 had no
  post-resume start path.

rel55 lifecycle correction:
1. Goodix `gx_dev_suspend()` no longer returns
   `FP_DEVICE_ERROR_NOT_SUPPORTED`.
   libfprint documents that a suspend error cancels the current action.
2. Suspend now:
   - preserves clean RAM-only background/FDT bootstrap;
   - sets `force_cold_reset=TRUE`;
   - invalidates warm/production readiness;
   - calls `fpi_device_suspend_complete(dev, NULL)`.
   Verify/Identify therefore remains the same active action across S3.
3. Existing `gx_active_sleep_recovery()` detects the BOOTTIME-vs-MONOTONIC
   sleep jump in WAIT_ON/WAIT_OFF and jumps the live SSM to `GX_ST_SESSION`.
4. `gx_session_start()` sees `force_cold_reset`, resets/rebuilds MCU/TLS/FDT
   and uses the rel53 held-finger RAM bootstrap when appropriate.
5. `gx_run_async()` now enters a libfprint critical section around blocking
   session/TLS or GET_IMAGE work; `gx_session_done()` and
   `gx_capture_done()` leave it on return to the main loop.
   fprintd currently owns a logind delay inhibitor:
   `net.reactivated.Fprint ... sleep ... delay`, with 5 s logind delay max.

KDE v9:
- normal lock returns to rel51 window-ready startup;
- NO direct `authenticator.startAuthenticating()` in Component.onCompleted;
- startup timer still reveals UI and stock onUiVisibleChanged starts password +
  fingerprint together;
- on resume only, one idempotent kick:
  `gxfp51a0StartupAuthTimer.restart(); authenticator.startAuthenticating();`
- if auth already survives S3, KScreenLocker state guard makes start a no-op;
- if greeter slept before auth began, it starts immediately on resume;
- no pending flag, PAM delay timer, heartbeat, keepalive, or system-sleep hook.
- KScreenLocker upstream MR !340 / commit 992f3fa8 remains installed so KDE
  itself does not cancel PAM on suspend.

Unchanged:
- SIGFM matcher;
- threshold 7;
- 3 same-press image budget;
- enrollment data;
- GPIO behaviour;
- PMK/TLS crypto;
- capture recipe.

Validation before install:
- complete fingerprint/research test suite PASS;
- lifecycle/S3/bootstrap/TLS timeout/transport tests PASS;
- KDE v9 stock and v8 migration/rollback test PASS;
- boot binding test PASS;
- reproducible libfprint build PASS;
- build artifact gates: sensor I/O NONE, GPIO writes NONE, MMIO writes NONE,
  firmware actions NONE;
- copied real LockScreenUi.qml + v9 qmllint PASS.

Installed:
- kscreenlocker 6.7.5-1.2 (upstream S3 PAM fix from rel54);
- libfprint-goodix51a0 1.94.100.goodix51a0-55;
- plasma-login-manager 6.7.5-3.8;
- fprintd 1.94.5-2.1;
- rel55 package SHA256:
  `b559c0555f2a681ff64e0d9381e4a22fe1711f1c7258e7ff5bc96406b6f8b1ac`;
- driver source SHA256:
  `8d8c9bd730218951578d1876e647cbeb9e53e3e4303ac714f17d1d7e7af94747`;
- libfprint package integrity 40/40 clean;
- KScreenLocker integrity 346/346 clean;
- fprintd PID 109705 since 19:32:28;
- prewarm Claim completed successfully 19:32:35;
- sleep delay inhibitor present for fprintd;
- enrollments intact: right-index, left-index, right-middle;
- no orphan packages.

NEXT HUMAN GATES:
A. First perform a normal lock test. Expected behaviour should reproduce rel51.
B. Then perform a real deep S3 -> wake -> use fingerprint naturally/immediately.
Password must remain concurrently usable in both tests.

Do NOT auto-lock, auto-suspend, reboot or re-enroll.
If deep fails, inspect exact sequence:
- KScreenLocker start/resume;
- fprintd suspend/resume;
- `GXFP51A0 suspend: preserving active authentication; native cold recovery armed for resume`;
- `GXFP51A0 active S3 boundary detected during authentication`;
- `GXFP51A0 active resume recovery: rebuilding cold sensor context`;
- RAM bootstrap marker if finger already present;
- READY/DETECTED_HOLD/score.

### rel55 repository finalization

- implementation commit: `035f923 fix(fingerprint): preserve authentication across S3`
- branch: `fingerprint-rel55-native-s3-continuity`
- pushed to origin.

---

## Update 2026-09-27 02:12 CEST — rel55 lock failure diagnosed; rel56 installed

Human rel55 normal-lock result: FAIL.

This was NOT a KDE/PAM startup failure and NOT an S3 test:
- KScreenLocker started fingerprint normally;
- no suspend/S3 occurred after rel55 was installed at ~19:32 and before the
  failed lock at 02:03;
- rel55 fprintd therefore retained the same awake sensor context for roughly
  6.5 hours.

Exact rel55 failure:
- WARM_REBASE succeeded in 1744 ms, idle=354, floor=330;
- WakeupMCU completed and Identify reached READY;
- physical press 1 same-press scores: 3 / 3 / 2;
- physical press 2 same-press scores: 3 / 4 / 3;
- physical press 3 same-press scores: 3 / 3 / 4;
- unchanged threshold: 7;
- no accepted-GET_IMAGE replay, TLS digest/GCM failure or transport desync.

Templates were NOT modified. The same boot/templates had previously produced
genuine successful scores 23, 11, 15 and 13. Re-enrollment is not indicated.

Root cause:
- rel50 used `GX_WARM_IDLE_TTL_US = 5 minutes` and forced a deterministic cold
  rebuild after that awake-idle age;
- rel50 human normal-lock PASS reached score 15/7;
- rel51 commit 277a272 removed only that TTL as a latency optimization;
- rel51 assumed FDT + encrypted WARM_REBASE could validate retained state for an
  unlimited awake duration;
- the rel55 ~6.5 h idle test disproves that assumption: the sensor-side context
  can still answer FDT/TLS validation while its imaging state yields only 2-4.

rel56:
- branch: `fingerprint-rel56-bounded-warm-context`;
- restores rel50's proven 5-minute `GX_WARM_IDLE_TTL_US`;
- restores `gx_warm_idle_expired()`;
- `gx_dev_open()` cold-rebuilds on `slept || expired || force_cold_reset`;
- an expired awake context is abandoned host-side, GPIO-reset and prepared cold;
- short/medium awake reuse still uses fast WARM_REBASE;
- S3 RAM bootstrap remains guarded by `slept && !resume_bg_valid` and is NOT
  used to hide an expired awake context.

All rel53-rel55 S3 work remains:
- held-finger RAM-only post-S3 bootstrap;
- upstream KScreenLocker MR !340 / commit 992f3fa8;
- native same-action Verify/Identify continuity across S3;
- libfprint critical sections around blocking TLS/session/GET_IMAGE work;
- KDE helper v9 with rel51 window-ready normal startup + one resume-only kick.

Unchanged:
- SIGFM matcher;
- threshold 7;
- 3 same-press captures;
- templates/enrollments;
- PMK/TLS crypto;
- GPIO mapping.

Validation:
- targeted lifecycle/native-resume/boot-binding tests PASS;
- complete fingerprint/research suite PASS;
- reproducible build PASS;
- source SHA256:
  `64461719c93b4315e8561d09d3901ef554bde9e78a858d335fcc72db1b02fb89`;
- rel56 package SHA256:
  `d74a08c3e5efe7f8936072fa540ded2b634c6fe26af5b4997ab8a0bc771da245`;
- build active sensor I/O/GPIO/MMIO/firmware actions NONE.

Installed:
- libfprint-goodix51a0 1.94.100.goodix51a0-56;
- fprintd 1.94.5-2.1, PID 183078 since 02:11:40 CEST;
- prewarm Claim completed successfully at 02:11:46;
- kscreenlocker remains 6.7.5-1.2;
- plasma-login-manager remains 6.7.5-3.8;
- enrollments intact: right-index, left-index, right-middle.

NEXT HUMAN GATE:
1. normal lock now, under the freshly rebuilt rel56 context;
2. user reports `rel56 lock OK` or `rel56 lock échoué`;
3. inspect logs before attempting deep S3.
Do NOT auto-lock, auto-suspend, reboot or re-enroll.

### rel56 repository finalization

- implementation commit: `23c6833 fix(fingerprint): bound retained warm context`
- branch: `fingerprint-rel56-bounded-warm-context`
- pushed to origin.

---

## Update 2026-09-27 02:27 CEST — rel56 human lock FAIL; post-S3 hardware state now primary hypothesis

Human report:
- `rel56 lock échoué`
- user tried enrolled index repeatedly and right middle finger.

Exact rel56 runtime:
- rel56 had been freshly loaded at 02:11:40 and cold prewarm completed 02:11:46.
- normal lock greeter started ~02:19:58; no new S3 occurred during this test.
- because retained context age exceeded restored 5-minute TTL, rel56 DID take a
  full cold preparation path. Therefore stale warm context is not sufficient to
  explain the persistent low scores.
- user touched as soon as UI was visible; cold calibration correctly refused to
  learn a finger as background:
  - mean 231 -> contaminated 215;
  - mean 213 -> contaminated 220;
  - mean 219 -> contaminated 241;
  - READY only at 02:20:15.358 after the sensor became clear.
- first captured physical pose: scores 3/3/4, best 4/7.
- second captured physical pose: score 3/7, then finger-off stopped same-press
  recapture.
- driver reached READY for a third pose but authentication ended before another
  physical detection/capture.
- thus not every user touch reached the matcher, but the captures that did are
  genuinely poor.

Critical historical correlation on this same boot:
- BEFORE first deep S3: successful genuine scores 23, 11, 15, 13.
- first real deep S3: 14:44:36 -> 15:19:40.
- AFTER that S3, even rel51/52 (driver bit-identical to previously successful
  rel51) produced only roughly 3-5.
- rel55/56 later on the same boot continue producing 2-4 despite fprintd
  restarts, warm rebase and now full cold preparation.
This strongly shifts the root cause from KDE/matcher/templates to sensor or SPI
controller state left degraded across S3.

Passive post-S3 platform audit:
- pinctrl is exactly the known-good reference state:
  - pin44 GSPI1_CS0B mode1 0x44000700
  - pin45 GSPI1_CLK mode1 0x44000700
  - pin46 GSPI1_MISO mode1 0x44000702
  - pin47 GSPI1_MOSI mode1 0x44000700
  - pin41 IRQ GPIO 0x40100100
  - pin189 reset GPIO 0x44000200 (LOW/runtime)
- current driver reset already uses the current validated Linux recipe:
  GPIO264 HIGH 300 ms -> LOW 600 ms.
  Therefore an obsolete 10/100 ms reset pulse is NOT the missing recovery.
- PCI 00:1e.3 Intel LPSS SPI and pxa2xx-spi.4 are both currently
  power/control=auto and runtime_status=suspended when idle.
- current szlukabence reference tooling still sets both power/control=on while
  running SPI experiments, but this has not yet been proven causal for the
  biometric degradation.
- RDC policy blocked direct /sys power/control writes, so no runtime-PM setting
  was changed.

Latest upstream/reference evidence:
- no new issue/comment provides a ready post-S3 GXFP51A0 fix.
- latest SIGFM evidence still supports matcher/threshold 7; do not lower it.
- Windows WBDI transcript confirms that before D0Exit the working Goodix stack
  sends `setmode: sleep`:
    command packed 0x60, payload 01 00, ACK expected for 0x60.
- goodix-fp-dump independently exposes the same operation as
  Message(0x6, 0, b"\x01\x00") / mcu_switch_to_sleep_mode().
- our gx_dev_suspend() currently sends NO sensor sleep command; it only preserves
  host bootstrap state and arms native cold recovery.
- Windows S0-idle resume uses WakeupMCU then FDT rearm/capture; its persistent
  ImageBase is managed separately.
- the old unresolved DeviceInit intermediate operation is NOT relevant:
  device_action(0x0F) only changes Windows-local besdenable and sends no sensor
  I/O.

Next discriminating human gate BEFORE any rel57 code:
1. user performs one full normal reboot; assistant must NOT trigger it.
2. keep installed rel56 unchanged.
3. after login, perform one normal graphical lock and fingerprint test BEFORE
   any suspend/deep sleep.
4. report `rel56 reboot lock OK` or `rel56 reboot lock échoué`.
5. inspect scores.
If reboot restores normal scores, post-S3 persistent hardware/controller state
is confirmed and rel57 should target suspend lifecycle (first candidate: exact
Windows sleep 0x60/01 00 before S3, with no matcher changes).
If reboot does not restore scores, reject the post-S3-state hypothesis and
continue diagnosis before adding SLEEP.

---

## Update 2026-09-28 00:05 CEST — rel56 isolates S3 regression; rel57 Windows SLEEP lifecycle installed, pending clean reboot + S3 validation

### Human result that closes the rel56 diagnosis

User report:
- `rel56 reboot lock OK`
- after that reboot the laptop automatically entered sleep; fingerprint unlock then failed.

Exact same-boot evidence:
- clean reboot: 2026-09-27 23:26:52 CEST.
- rel56 graphical login succeeded at 23:27:
  - WARM_REBASE idle=354 floor=330;
  - same physical press scores 4 -> 6 -> 7;
  - best=7, threshold=7;
  - Plasma Login Manager: `Authentication race won by fingerprint`.
- first automatic deep S3:
  - PrepareForSleep(true): 23:43:14.543;
  - kernel `PM: suspend entry (deep)`: 23:43:15.618;
  - resume complete: ~23:43:49.846.
- first post-S3 unlock:
  - press 1 scores 3/3/4, best 4;
  - press 2 scores 3/3/3, best 3;
  - FDT/touch detection itself remained healthy;
  - GET_IMAGE no-evidence retries still recovered transport;
  - biometric image quality/match signal collapsed immediately after S3.

Conclusion now strongly established:
- matcher, threshold 7, enrolled templates and normal cold-boot path are NOT the root cause.
- a full reboot restores useful scores.
- one real S3/deep cycle creates the persistent degraded imaging state.
- restarting fprintd and even doing a full Linux cold software preparation after that S3 had previously failed to restore the pre-S3 scores.

### Why rel56 resume recovery did not prevent this

No `GXFP51A0 suspend:` marker exists for the observed automatic S3.
The driver `gx_dev_suspend()` callback was therefore not called.

This matches libfprint lifecycle semantics: the driver suspend vfunc protects an active interactive action, but the common case here is an idle device already released/closed by fprintd before system S3.

Therefore putting a Windows SLEEP command only in `gx_dev_suspend()` would not fix the real path.

### Exact Windows/reference evidence used for rel57

Working Windows WBDI trace shows sensor deactivation and power transition use:
- command: MCU SLEEP packed `0x60`
- payload: `01 00`
- ACK expected for `0x60`
- Windows sends it from OnActivate(false)/ChicagoHUSetMode(sleep), and also before D0Exit.
- Windows later uses exact WakeupMCU before FDT/capture.

goodix-fp-dump independently implements the same command as:
- `mcu_switch_to_sleep_mode()`
- command `0x60`, payload `01 00`.

The exact Goodix wire body generated by rel57 is:
`60 03 00 01 00 46`.

### rel57 implementation

Branch:
`fingerprint-rel57-sleep-lifecycle`

Code commit:
`2152dae fix(fingerprint): sleep sensor across idle lifecycle`

Package:
`libfprint-goodix51a0 1.94.100.goodix51a0-57`

Package SHA256:
`c54db2608685789cfa6fcc6c3c9cba566074b895fad81c15c218a208e047c9e1`

Behavior:
1. add exact SLEEP builder `0x60 / 01 00`;
2. add `gx_sensor_sleep()`, which marks sensor_sleeping only after a valid ACK;
3. on normal `gx_dev_close()`, while transport is still open:
   - send exact Windows SLEEP;
   - only retain warm TLS/background/FDT when SLEEP is ACKed;
   - if SLEEP is ambiguous/fails, discard warm context so next open rebuilds cold;
4. on the next warm open:
   - if sensor_sleeping, issue exact Windows WakeupMCU first;
   - only then perform WARM_REBASE/FDT/TLS validation;
5. active-operation `gx_dev_suspend()` also sends best-effort SLEEP, but still arms the existing full cold resume recovery regardless;
6. cold/unknown lifecycle paths clear sensor_sleeping.

Unchanged:
- GQ SIGFM matcher;
- threshold 7;
- templates/enrollments;
- FDT thresholds;
- same-press capture policy;
- exact WakeupMCU bytes;
- GPIO264 reset recipe;
- PLM dual password/fingerprint path;
- no external resume hook;
- no periodic keepalive;
- no persistent timing-learning files.

### rel57 validation completed before install

PASS:
- full research test suite;
- exact SLEEP packet test `60 03 00 01 00 46`;
- new sleep-lifecycle source safety;
- lifecycle recovery;
- native S3 recovery;
- held-finger bootstrap;
- PLM dual auth;
- real GQ SIGFM ABI smoke;
- boot binding integration test;
- complete reproducible libfprint v1.94.100 Meson/Ninja build;
- GXFP51A0 object/type/ACPI gates;
- release biometric dump hook absent.

Package audit:
- 43 archive entries;
- forbidden external resume/keepalive/timing artifacts absent.
Installed audit:
- `pacman -Q libfprint-goodix51a0` = `1.94.100.goodix51a0-57`;
- `pacman -Qkk`: 40 package files, 0 modified;
- fprintd active/running;
- 0 failed systemd units;
- old resume hooks absent;
- old timing files absent;
- warm keepalive not found/inactive.

### rel57 non-biometric runtime lifecycle proof on the current contaminated boot

After installing rel57, two normal boot-prewarm Claims were run without any physical fingerprint test.

The installed library contains the new SLEEP marker.

Observed ordering on the next retained-context open:
- `GXFP51A0 AUTH_TRACE WakeupMCU raw SPI write complete`
- later `GXFP51A0 WARM_REBASE refreshed background+FDT ...`

This ordering is new and is significant:
- rel56 warm open performed WARM_REBASE first, then WakeupMCU during authentication.
- rel57 sets `sensor_sleeping=TRUE` only after the SLEEP ACK.
- therefore seeing WakeupMCU before WARM_REBASE on the following open proves the close-side SLEEP transition was ACKed and the sleeping state was consumed by the rel57 wake-before-validation path.

Do NOT use fingerprint scores from this current boot to judge rel57: the boot already crossed the rel56-failing S3 boundary before rel57 was installed.

### Next acceptance sequence — USER controls reboot/suspend

1. User performs ONE full normal reboot. Assistant must not reboot Pegasus.
2. Confirm installed rel57 is loaded.
3. Test fingerprint at graphical login.
4. Before any sleep, perform one normal lock/unlock fingerprint test.
5. Inspect scores and rel57 lifecycle ordering.
6. Then user performs ONE normal deep/S3 suspend.
7. Immediately test fingerprint unlock.
8. Inspect whether post-S3 scores remain >= threshold instead of collapsing to 3-4.

Success gate:
- clean login/lock remains functional;
- rel57 close-side SLEEP is used;
- after one real S3, fingerprint unlock succeeds with a genuine score >=7;
- password remains simultaneously usable;
- no external resume hook/keepalive is introduced.

If post-S3 still collapses to 3-4 despite confirmed pre-S3 SLEEP:
- the SLEEP hypothesis is rejected or incomplete;
- next investigation should target host LPSS/pxa2xx runtime-PM/system-S3 state, not matcher/threshold/templates.

---

## Update 2026-09-28 01:42 CEST — rel58 final candidate installed; rel50 core restored + precise C++ resume rearm

### Why rel58 is a reset rather than another layered driver experiment

The rel57 human sequence was:
- login fingerprint failed;
- normal lock eventually succeeded after 2–3 physical poses;
- deep-S3 unlock failed.

Forensics:
- rel57 login/lock did run under package -57 before a later diagnostic downgrade.
- no rel57 Windows-SLEEP marker appeared anywhere in that test boot, so the
  0x60/01 00 experiment was never exercised and did not explain the result.
- the S3 unlock had ZERO fprintd journal entries after resume. Fingerprint PAM
  never started; this was a desktop authentication lifecycle failure, not a
  measured biometric mismatch.
- QML v9 contained onResumingFromSuspend(), but the real race still produced no
  fprintd request.

Decision:
- stop stacking rel53-rel57 lifecycle experiments;
- restore the last strongly human-validated driver core, rel50 c8ec8cb;
- fix the proven resume-auth race in KScreenLocker C++, where the lifecycle
  signal originates.

### Driver core

The complete directory fingerprint/driver/goodix51a0 is restored to rel50
commit c8ec8cb.

This retains:
- rel48 accepted-GET_IMAGE/TLS-timeout safety;
- fixed SIGFM threshold 7;
- full 3-image same-press budget;
- 3 physical-pose Identify budget;
- 5-minute bounded warm-context TTL;
- native BOOTTIME-vs-MONOTONIC S3 detection;
- active-S3 libfprint NOT_SUPPORTED cancellation contract;
- cold reset/rebuild after lifecycle invalidation;
- no persistent learned timings;
- no external resume hook / keepalive.

This intentionally removes the post-rel50 driver experiments:
- no resume_bg_frame / RAM-only stale-background bootstrap;
- no gx_sensor_sleep / Windows 0x60 SLEEP-on-close state;
- no libfprint critical-section wrapper added in rel55;
- no same-action suspend-preservation path.

Reproducibility check:
- fresh rel58 GXFP51A0 goodix51a0.c.o .text SHA256:
  ed9ffa18eed318b8001f23b7d0143efdb478116b0aabc2fc804818c808dd4d87
- fresh rel50 c8ec8cb goodix51a0.c.o .text SHA256:
  ed9ffa18eed318b8001f23b7d0143efdb478116b0aabc2fc804818c808dd4d87
- DRIVER_TEXT_IDENTICAL=YES.
- Whole libfprint .so is NOT claimed byte-identical because build paths/current
  non-driver repository inputs differ.

### KScreenLocker 6.7.5-1.3

QML resume rearming is removed.

The patched C++ logind boundary now does:
- PrepareForSleep(true): do not cancel PAM (KDE bug 481808 / MR !340 intent);
- PrepareForSleep(false): call PamAuthenticators::resumeAuthenticating().

resumeAuthenticating():
- returns while graceLocked;
- if group state is Idle: invokes normal startAuthenticating(), starting password
  plus all configured noninteractive authenticators;
- if group is already Authenticating: leaves interactive password untouched and
  only calls tryUnlock() on noninteractive authenticators;
- PamWorker::authenticate() already ignores duplicate calls while it is still in
  pam_authenticate(), so a healthy fingerprint worker is not restarted.

This directly addresses both observed resume races:
1. greeter exists before S3 but authentication never started;
2. password remains active while libfprint stopped only fingerprint.

No pre-QML forced authentication patch is retained.

KScreenLocker patch SHA256:
674ecb8010335fdf78f832ac419b396d87d78e0cb48d7f2ad84eec478a8e2fae

KScreenLocker package:
- kscreenlocker 6.7.5-1.3
- package SHA256:
  8ad6e95ae1415ffc98c1d5b648d953da8244ba53ebd0502d601c7556197060e9
- package was built from the SHA256-verified KDE 6.7.5 tarball; local makepkg
  lacked the current KDE signing key, so the build invocation skipped local PGP
  verification only after the pinned source checksum gate.

### KDE QML v10

Marker:
GXFP51A0 cpp-lifecycle-auth fingerprint integration v10

QML owns only normal window-ready startup:
- no onResumingFromSuspend();
- no resume pending/timer;
- no heartbeat;
- no periodic auth loop.

qmllint PASS and helper --check PASS on the live file.

### rel58 package / live state

libfprint package:
- libfprint-goodix51a0 1.94.100.goodix51a0-58
- package SHA256:
  5340896c38bbc1292128e9b6bdc657fdddf6432dabb38719bb2a6fd2adb2582a

Live:
- libfprint-goodix51a0 1.94.100.goodix51a0-58
- kscreenlocker 6.7.5-1.3
- fprintd 1.94.5-2.1
- plasma-login-manager 6.7.5-3.8
- fprintd PID 59333 since 01:39:06 CEST
- final prewarm Claim completed 01:39:13
- fprintd logind sleep-delay inhibitor present
- enrollments intact:
  right-index, left-index, right-middle
- libfprint package integrity: 40/40, 0 modified
- KScreenLocker package integrity: 346/346, 0 modified
- 0 failed systemd units
- 0 orphan packages after build cleanup

Live libfprint marker audit confirms:
- rel50 active-S3 boundary code present;
- rel50 5-minute warm TTL present;
- Windows SLEEP experiment absent;
- RESUME_BOOTSTRAP experiment absent;
- rel55 same-action suspend-preservation marker absent.

### Tests/builds

PASS:
- full fingerprint/research suite;
- real GQ-SIGFM fp_eval ABI smoke;
- lifecycle recovery;
- accepted GET_IMAGE/TLS timeout recovery;
- transport recovery;
- same-press capture;
- normal/idle S3 source gates;
- KScreenLocker precise C++ resume source gate;
- QML v10 migration/removal/check;
- Plasma Login concurrent password/fingerprint source gates;
- boot binding integration test;
- full libfprint Meson/Ninja build;
- full KScreenLocker 6.7.5 build;
- release biometric dump hook absent.

Build trees/packages/temp copies were cleaned after recording hashes, including
the old temp/rel56-rebuild directory.

### Upstream refresh 2026-09-28

Checked exact GitHub repos/issues again:
- szlukabence/goodix-fingerprint-spi-linux latest commit remains
  7b8284898696e26a2fd5cb9a05b8605012439a7d, 2026-09-21, README/funding/status
  update only; no newer GXFP51A0 S3 fix.
- Sigfrodr/libfprint-goodixtls latest commit remains
  dda67c8affef6c2ba3fc45145539db2768eb96b2, 2026-09-25, adding the contributed
  GQ-SIGFM fp_eval plugin.
- Sigfrodr issue #5 has no later actionable GXFP51A0 driver fix; latest evidence
  still measures real GQ-SIGFM around EER 4.7%, with NBIS near chance on 80x64.
- goodix-fp-dump issue #69 has no newer suspend/resume fix.
- do not lower threshold 7 from this evidence.

### Remaining HUMAN acceptance gates

rel58 is installed and fully software-validated but NOT yet declared human-valid.

User controls all physical transitions:
1. full reboot;
2. fingerprint at graphical login;
3. normal lock -> fingerprint;
4. one deep S3 -> immediate fingerprint unlock;
5. password remains usable concurrently.

Assistant must never trigger reboot/suspend automatically.
After each user result, inspect exact logs before any further code change.

### rel58 repository finalization

- implementation/docs commit:
  `a84ebb7 fix(fingerprint): restore rel50 core and rearm resume in C++`
- branch:
  `fingerprint-rel58-rel50-core-cpp-resume`
- pushed to origin.
- rel58 remains pending the user-controlled reboot/login/normal-lock/deep-S3
  acceptance sequence; do not describe it as human-validated before those gates.

---

## Update 2026-09-29 10:05 CEST — rel58 human failure diagnosed; rel59 same-press pacing installed

Human rel58 result:
- login failed;
- normal lock failed;
- S3 unlock failed.

### rel58 forensic result

Clean boot began 2026-09-29 08:43:36.

Graphical login:
- fingerprint PAM started normally;
- WARM_REBASE succeeded: idle 357, floor 333;
- touch/FDT was healthy;
- physical pose 1: scores 4,4,3;
- physical pose 2: scores 3,3,3;
- physical pose 3 first image score 3;
- threshold remained 7;
- password won normally.
Therefore the login failure was a real low-score biometric capture failure, not
a missing KDE/fprintd request.

Key comparison with the known rel56 reboot success:
- rel56 successful pose: first image needed safe no-evidence GET_IMAGE retry,
  then image2 and image3 were accepted first-try; scores 4 -> 6 -> 7.
- rel58 failed pose: image1, image2 and image3 each needed the no-evidence
  GET_IMAGE retry; scores 4 -> 4 -> 3.
- FDT/drop values were otherwise comparable.

Normal lock around 09:51:
- KScreenLocker started;
- retained context was beyond the 5-minute trust bound and a cold rebuild ran;
- TLS handshake failed once;
- capture preparation then hit accepted-GET_IMAGE/TLS timeouts;
- the driver did not reach READY before the later S3 request.
This remains a separate cold-preparation latency/reliability issue to revisit
after matching is stabilized.

S3:
- KScreenLocker 1.3 C++ resume fix DID fire:
  `Resume: rearming missing authenticators`.
- fprintd began native cold preparation after resume.
Therefore rel58's previous zero-fprintd resume bug is fixed.
- Immediate finger placement can still collide with the required clean
  post-S3 background calibration; do not reintroduce stale-background bootstrap
  without new evidence.

### rel59 root cause / change

The existing capture pacing calibration was too late for same-press recapture:
- retry evidence was applied only after final cleanup;
- `gx_capture_retry_same_press_frame()` performed FDT-manual then sent GET_IMAGE
  immediately, with no `gx_capture_gap_us()` barrier.

rel59:
1. if a successfully authenticated same-press image needed the safe no-evidence
   GET_IMAGE replay, the existing `gx_capture_pacing_success()` calibration is
   applied immediately before another image is requested;
2. RetryCaptureIMG now waits `gx_capture_gap_us()` after FDT-manual and before
   GET_IMAGE;
3. expected reference-machine behavior after protocol timing reaches 300%:
   capture pacing is bounded to 250-300%, so RetryCaptureIMG barrier is 75-90 ms;
4. all timing remains RAM-only / process-local.

Unchanged:
- GQ-SIGFM matcher;
- threshold 7;
- three enrolled prints;
- same 3-image / 3-pose biometric budgets;
- templates;
- GPIO;
- KScreenLocker C++ resume rearm;
- QML v10;
- rel50 S3 lifecycle contract;
- no external resume hook;
- no keepalive;
- no persistent timing-learning file.

Validation:
- targeted same-press pacing gates PASS;
- safe GET_IMAGE retry gates PASS;
- accepted GET_IMAGE/TLS timeout recovery gate PASS;
- native S3 source gate PASS;
- full fingerprint/research suite PASS;
- GQ-SIGFM ABI smoke PASS;
- boot binding test PASS;
- full libfprint Meson/Ninja build PASS;
- release biometric dump hook ABSENT;
- active sensor/GPIO/MMIO/firmware actions during build NONE.

Package:
- `libfprint-goodix51a0 1.94.100.goodix51a0-59`
- SHA256:
  `9920ce4626cff557a6ba6d4d85094e4c42fd4c2d968134be915e3112801b5755`

Installed live at ~10:04 CEST:
- fprintd restarted to load rel59, PID 16038;
- non-biometric boot-prewarm Claim completed;
- enrollments intact: right-index, left-index, right-middle;
- package integrity 40 files / 0 modified;
- live binary contains:
  `RetryCaptureIMG pacing barrier=%u us`
  and
  `same-press retry-assisted pacing applied before next image`.

Next human gate:
- first test ONE normal lock/unlock now, before any reboot/S3.
- do not wait for a hidden READY; when lock UI is visible, place an enrolled
  finger normally and hold it through same-press recaptures.
- immediately inspect whether later images stop needing GET_IMAGE replay and
  whether scores climb above threshold.
- only after normal-lock success should reboot-login and then deep-S3 be tested.


---

## Runtime validation 2026-09-29 — rel59 normal lock PASS

Human result: `rel59 lock OK`, perceived on the second touch/pose.

Exact runtime:
- kscreenlocker greeter appeared at ~10:36:37.837;
- fingerprint reached `physical press 1/3 READY` at 10:36:43.974;
- visible-greeter -> READY latency was therefore about 6.1 s;
- the user's earlier perceived first touch occurred before the driver was armed,
  explaining why the driver itself records the successful touch as physical
  press 1/3.

Successful recorded press:
- DETECTED_HOLD: touch=0x3f, zones=6, mean=239, drop=114;
- image 1 needed the safe no-evidence GET_IMAGE retry;
- rel59 immediately applied capture pacing 250% -> 300% (90 ms);
- image 1 score=5/7;
- RetryCaptureIMG barrier=90000 us;
- image 2 score=6/7 with NO additional GET_IMAGE replay;
- RetryCaptureIMG barrier=90000 us;
- image 3 score=7/7 with NO additional GET_IMAGE replay;
- same-press best=7 -> human unlock succeeded.

This reproduces the useful shape of the historical rel56 success (4 -> 6 -> 7)
and confirms rel59 fixed the same-press pacing defect without changing threshold,
matcher, templates or enrollments.

Remaining issue:
- normal-lock visible UI -> fingerprint READY is still ~6 s when a cold
  preparation is required.
- Do not optimize this yet: preserve the now-working rel59 biometric candidate
  until reboot/login and deep-S3 gates are validated. Once those are green,
  optimize startup arming separately so UI-visible more closely means
  fingerprint-ready.

Next human gate:
1. user performs a full reboot manually;
2. at graphical login, use an enrolled finger normally;
3. report `rel59 login OK` or `rel59 login échoué`;
4. inspect logs before any S3 or code change.

---

## Update 2026-09-29 12:52 CEST — rel59 S3 PASS; rel60 installed

### rel59 human deep-S3 result

User report:
- `rel59 S3 OK` after several perceived poses.

Exact S3:
- PrepareForSleep(true): 12:35:20.264;
- kernel deep suspend entry: 12:35:21.390;
- resume complete: 12:35:25.859.

KScreenLocker/fprintd rearm worked. The driver then performed a real post-S3
cold preparation. Because the user touched immediately, calibration correctly
waited for the sensor to become clear:
- 12:35:29.812: `calibration waiting for sensor clear: mean=222 floor=340`;
- READY: 12:35:33.667.
Thus resume -> fingerprint READY was about 7.8 s.

First post-S3 Identify cycle:
- pose 1: 3 / 3 / 4, best 4;
- pose 2: 3 / 3 / 4, best 4;
- pose 3: 3 / 3 / 3, best 3.
All same-press RetryCaptureIMG requests used the rel59 90 ms calibrated barrier.

After those three bounded poses, pam_fprintd started a new Identify cycle.
That new cycle issued normal WakeupMCU at 12:35:48.130 and its very first
captured image scored 8/7 at 12:35:50.176. Human unlock succeeded.

This proves:
- rel59 deep-S3 unlock is functionally working;
- rel59 pacing remains active after S3;
- background contamination was not accepted: the cold preparation explicitly
  waited for a clean sensor before calibration;
- the striking runtime difference before the successful 8/7 press is a fresh
  WakeupMCU at the start of the new Identify cycle.

### rel60 change

Branch:
`fingerprint-rel60-rearm-between-poses`

Only one behavioral delta over rel59:
- after a usable Verify/Identify pose is below threshold and another physical
  pose remains, set a one-shot `rearm_mcu_before_retry` flag;
- once finger release is proven in `gx_poll_off()`, issue the already validated
  WakeupMCU raw write before returning to WAIT_ON;
- clear the flag immediately;
- Wakeup failure terminates with protocol error rather than continuing in an
  uncertain MCU state.

The rearm is NOT used:
- after a successful match;
- before finger release;
- during enrollment;
- for transport-desync retries;
- after the fixed physical-pose budget is exhausted.

Unchanged:
- GQ-SIGFM matcher;
- threshold 7;
- enrollment/templates;
- 3 same-press images;
- 3 physical poses;
- rel59 same-press pacing;
- FDT/background logic;
- rel50 S3 lifecycle contract;
- KScreenLocker 6.7.5-1.3 precise C++ resume rearm;
- QML v10;
- no external resume hook/keepalive/persistent timing file.

Validation:
- dedicated retry-pose MCU-rearm safety gate PASS;
- same-press / retry-assisted pacing gates PASS;
- native resume / KScreenLocker gates PASS;
- boot binding PASS;
- complete research suite PASS;
- real GQ-SIGFM ABI smoke PASS;
- full reproducible libfprint build PASS;
- build sensor I/O/GPIO/MMIO/firmware actions NONE.

Package:
- `libfprint-goodix51a0 1.94.100.goodix51a0-60`
- SHA256:
  `42341f265d0a1f42c85ca467f68041c34d00349b4dc24a2bad693402257e5b49`

Install:
- an initial install attempt was blocked by a genuine pacman database lock from
  an unrelated CachyOS system upgrade; the lock disappeared normally when that
  transaction completed. It was NOT deleted manually.
- rel60 then installed successfully with --noscriptlet.
- fprintd restarted; PID 57301 since 12:51:52.
- final non-biometric prewarm completed.
- package integrity: 40 files, 0 modified.
- enrollments intact: right-index, left-index, right-middle.
- KScreenLocker remains 6.7.5-1.3 / QML v10.

Note: the unrelated CachyOS upgrade completed with a system message that a
reboot is recommended for upgraded core packages. Do NOT reboot Pegasus on the
assistant's initiative; the user explicitly avoids unnecessary reboots.

Next human gate:
1. one normal lock/unlock under rel60;
2. if normal lock remains good, one user-triggered deep S3;
3. inspect whether a failed first usable pose now logs
   `MCU rearmed after failed usable press before retry 2/3`
   and whether the next pose succeeds instead of exhausting all three poses and
   starting another PAM Identify cycle.

### rel60 repository finalization

- implementation/docs commit:
  `e876def fix(fingerprint): rearm MCU between failed poses`
- branch:
  `fingerprint-rel60-rearm-between-poses`
- pushed to origin.
- installed live package:
  `libfprint-goodix51a0 1.94.100.goodix51a0-60`
- rel60 package SHA256:
  `42341f265d0a1f42c85ca467f68041c34d00349b4dc24a2bad693402257e5b49`
- next gate is user-controlled normal lock, then user-controlled S3.
