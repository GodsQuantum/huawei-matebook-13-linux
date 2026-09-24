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
