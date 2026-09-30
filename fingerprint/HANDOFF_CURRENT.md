# HANDOFF COMPLET — Huawei MateBook 13 2021 / Goodix GXFP51A0 (GF3658 ST411)

**Date de gel : 2026-09-30 09:28 CEST**
**Machine : Pegasus uniquement**
**État courant : rel62 fast-resume installée, entièrement software-validée, PAS ENCORE human-validée en S3.**

Ce document est le point d’entrée canonique pour toute nouvelle session. Il a été écrit pour éviter de redécouvrir au milieu d’une session des avancées, échecs, hypothèses réfutées ou contraintes déjà établies.

## 1. Objectif final et contraintes utilisateur

Objectif : support fingerprint natif et fiable sur le Huawei MateBook 13 2021 sous CachyOS/Plasma pour :
- login Plasma Login Manager ;
- lockscreen KScreenLocker ;
- réveil deep S3 ;
- mot de passe et empreinte utilisables **en parallèle**, aucun ne doit attendre l’autre ;
- comportement rapide, autonome, survivant aux updates ;
- pas de hacks fragiles externes.

Contraintes absolues :
- ne jamais reboot, suspendre, locker ou poweroff Pegasus automatiquement ;
- les tests physiques fingerprint sont déclenchés par l’utilisateur ;
- ne jamais ré-enrôler par réflexe ;
- ne jamais baisser le seuil SIGFM sous 7 ;
- ne jamais toucher GPIO112 / GPP_D16 ;
- reset MCU connu : GPIO264 logique, runtime LOW ; le pinctrl dump expose le pad de reset comme pin189 ;
- ne jamais exposer PMK/PSK, captures brutes biométriques, templates ou secrets ;
- pas de heartbeat périodique, pas de keepalive fingerprint périodique, pas de hook system-sleep externe si l’intégration native suffit ;
- pas de persistent timing-learning file ;
- ne pas déclarer un release humainement valide avant un vrai test utilisateur ;
- préserver l’alternative password immédiate.

## 2. Machine / matériel

Pegasus :
- Huawei MateBook 13 2021 ;
- Intel i7-10510U, 16 GiB RAM, 1 TiB NVMe ;
- Intel UHD + NVIDIA MX250 2 GiB ;
- CachyOS / Plasma 6.7.5 ;
- fingerprint : Goodix GXFP51A0 / GF3658 ST411, SPI.

Pinctrl connu fonctionnel après S3 :
- pin44 GSPI1_CS0B mode1 0x44000700 ;
- pin45 GSPI1_CLK mode1 0x44000700 ;
- pin46 GSPI1_MISO mode1 0x44000702 ;
- pin47 GSPI1_MOSI mode1 0x44000700 ;
- pin41 IRQ GPIO 0x40100100 ;
- pin189 reset GPIO 0x44000200 LOW/runtime.

Reset Linux validé du capteur :
- GPIO264 HIGH 300 ms -> LOW 600 ms.
Ne pas revenir à l’ancienne hypothèse 10/100 ms.

## 3. Workspace / repo / Git

Workspace :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/`

Repo :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/`

GitHub :
`GodsQuantum/huawei-matebook-13-linux`

Branche courante :
`fingerprint-rel62-fast-resume`

HEAD :
`21effd3 docs(fingerprint): finalize rel62 fast resume`

Implémentation rel62 :
`a1e6cdd perf(fingerprint): bound cold resume preparation`

État Git au gel :
`## fingerprint-rel62-fast-resume...origin/fingerprint-rel62-fast-resume`
Repo clean.

Docs importantes :
- repo : `fingerprint/HANDOFF_CURRENT.md`
- repo : `fingerprint/README.md`
- ce handoff canonique : `HANDOFF_REL62_FULL_2026-09-30.md`
- prompt canonique : `PROMPT_REL62_CONTINUE_2026-09-30.md`
- docs techniques : `fingerprint/docs/`
- anciens handoffs : `fingerprint/handoff/`
- tests : `fingerprint/research/tests/`

## 4. État live EXACT au gel

Live :
- `libfprint-goodix51a0 1.94.100.goodix51a0-62`
- `kscreenlocker 6.7.5-1.5`
- `plasma-login-manager 6.7.5-3.9`
- `fprintd 1.94.5-2.1`

fprintd :
- PID 299950 ;
- actif depuis 2026-09-30 02:53:54 CEST ;
- lancé avec `/usr/lib/fprintd --no-timeout` via drop-in
  `/usr/lib/systemd/system/fprintd.service.d/50-goodix51a0-runtime.conf` ;
- delay inhibitor de sleep présent ;
- LimitCORE=0 ;
- char-gpiochip autorisé ;
- ordonné Before=display-manager.service.

Enrôlements intacts :
- right-index-finger ;
- left-index-finger ;
- right-middle-finger.

Matcher :
- GQ-SIGFM / SIGFM v3 ;
- template v4 ;
- seuil production = **7** ;
- 20 vues à l’enrollment ;
- max 3 images indépendantes sur une même pose ;
- max 3 poses physiques ;
- aucun score fusionné entre images/poses.

QML live :
- marqueur `GXFP51A0 cpp-lifecycle-auth fingerprint integration v10` ;
- startup normal window-ready ;
- aucun `onResumingFromSuspend()` QML ;
- aucun heartbeat / pending timer / resume timer.

KScreenLocker rel62 :
- robuste restart fingerprint-only au resume ;
- mot de passe PAM jamais annulé par la logique resume.

Plasma Login Manager :
- vrai service PAM fingerprint utilisé : `/usr/lib/pam.d/plasmalogin-fingerprint` ;
- live : `pam_fprintd.so max-tries=1 timeout=30`.
Attention : `/usr/lib/pam.d/kde-fingerprint` existe aussi mais n’est PAS le fichier PLM à utiliser pour conclure sur le timeout login.

Important : `gxfp51a0-boot-prewarm.service` existe mais est actuellement **disabled/inactive**.
Il est ordonné Before=display-manager, mais n’est pas automatiquement Wanted/Enabled dans l’état live actuel. Ne pas supposer qu’un prochain reboot bénéficie du prewarm boot. Ne pas l’activer aveuglément avant d’avoir terminé le gate S3 rel62 et compris l’intention actuelle.

## 5. Recherche externe / upstream déjà effectuée

Dernier refresh approfondi : 2026-09-30.

### szlukabence/goodix-fingerprint-spi-linux
Repo public le plus pertinent pour GXFP51A0 / MateBook SPI.
Dernier commit pertinent observé :
`7b8284898696e26a2fd5cb9a05b8605012439a7d` — 2026-09-21.
Aucun nouveau correctif GXFP51A0 deep-S3 publié après cela.

Le repo de référence force parfois Intel LPSS / pxa2xx SPI en `power/control=on` pendant ses expériences. Cela n’a PAS été prouvé causal sur Pegasus et n’est pas appliqué en production.

### Sigfrodr/libfprint-goodixtls
Dernier commit pertinent observé :
`dda67c8affef6c2ba3fc45145539db2768eb96b2` — 2026-09-25.
Ajout du plugin d’évaluation GQ-SIGFM.

Issue #5 / évaluation communautaire :
- 121 captures / 4 doigts ;
- genuine mean ~20.35 ;
- impostor mean ~2.05 ;
- max impostor 6 ;
- EER ~4.73 % ;
- seuil d’EER autour de 4.
Conséquence : le seuil production 7 garde une marge contre l’impostor max 6.
**Ne pas baisser à 6 ou moins.**

NBIS est mauvais sur ce petit capteur 80x64 ; GQ-SIGFM est nettement meilleur.

### goodix-fp-linux-dev/goodix-fp-dump
Issue #69 reste la discussion GXFP51A0 SPI pertinente.
Aucun nouveau correctif suspend/resume utile au dernier check.

### Duro02/goodix-5503-linux
Matériel différent, mais deux idées observées :
- garder fprintd résident avec `--no-timeout` pour préserver l’état warm ;
- warm readiness très rapide (~100 ms) sur 5503.
Il utilise aussi un hook system-sleep restart fprintd.
Sur Pegasus :
- `--no-timeout` a été retenu ;
- le hook system-sleep n’a PAS été copié : rel61 KScreenLocker lifecycle est human-validé et l’utilisateur ne veut pas de hook externe.

### Transcript Windows / goodix-fp-dump
Windows envoie :
- SLEEP command packed 0x60, payload `01 00`, ACK attendu ;
- puis WakeupMCU au resume.
Cette piste a servi à rel57, mais le SLEEP n’était en fait pas exécuté dans le test humain concerné et n’a pas résolu le problème. Elle a été retirée du driver final. Ne pas la réintroduire sans nouvelle preuve.

Windows D0Entry fait davantage qu’un simple GPIO reset, mais le vieil « intermediate operation » DeviceInit découvert plus tôt était local Windows/besdenable et n’envoyait pas de sensor I/O utile.

## 6. Historique des releases à connaître

### Rel20–24 : fondations natives
- rel20 : premier driver native GXFP51A0 intégré à libfprint/fprintd.
- rel22/23 : boot readiness et warm preclaim.
- rel24 : récupération du transport lent GXFP51A0 ; tag `fingerprint-gxfp51a0-rel24-rc1`.

### Rel25–29 : intégration login et lifecycle
- rel25 : intégration Plasma login ; problèmes de logout/transport.
- rel26 : récupération déplacée au lifecycle Claim.
- rel27 : première récupération native de boundary S3 idle.
- rel28 : expérimentation de prewarm post-resume via unités systemd. Important : ce design utilisait un hook externe ; utile historiquement, mais **rejeté comme architecture finale**.
- rel29 : expiration des warm sessions trop vieilles.

### Rel30–35 : KDE, image-ready et boot-prewarm
- rel30 : auth KDE plus immédiate.
- rel31 : impose contexte image-ready.
- rel32 : startup auth seulement lorsque la fenêtre lockscreen est prête ; human validation one-press.
- rel33 : boot-prewarm avant display manager ; simulation froide ~4.703 s.
- rel34 : one-shot fresh validated handoff afin d’éviter une capture background redondante juste après prewarm.
- rel35 : stabilisation première tentative greeter, évite collision keepalive/greeter. Les keepalives périodiques ont ensuite été abandonnés dans l’architecture finale.

### Rel40 : jalon majeur
Branche `fingerprint-rel40-windows-wakeup-identify`.
Validation humaine importante :
- cold/login fonctionnel ;
- same-press rescue démontré ;
- un premier frame pouvait être insuffisant puis un frame ultérieur de la même pose atteindre le seuil.
Cette preuve est la raison pour laquelle il est interdit de couper les captures same-press juste parce que la première image score bas.

### Rel41–44 : portabilité et timing RAM-only
- rel41/42 : adaptive + portable multi-distro.
- rel43 : auto-calibration du protocol timing **en RAM**, pas de fichier persistant.
- rel44 : capture pacing calibré par de vrais retries.

### Rel45–47 : S3/identify adaptatif et régression connue
- rel45 : FDT/resume race.
- rel46 : native active-S3 recovery candidate.
- rel47 : identify adaptatif ; introduit le mauvais `GX_REPOSE_SCORE_CUTOFF=4` qui coupait trop tôt une pose. Cette optimisation est **réfutée** et ne doit pas revenir.

### Rel48 / rel49 : dernier grand jalon de sécurité transport
Commit rel48 principal :
`5f20a06 fix(fingerprint): recover safely after accepted image timeout`

Règle critique :
- GET_IMAGE peut être rejoué uniquement si **aucun ACK et aucun TLS record** n’a été observé ;
- si GET_IMAGE a été accepté puis timeout, la session est considérée ambiguë/empoisonnée et doit être reconstruite, jamais replayée aveuglément.

Human validation rel48 :
- cold login score 23/7 ;
- vrai deep S3 ensuite score 11/7 ;
- pas de GCM/digest corruption.

rel49 :
- libfprint byte-identical rel48 ;
- intégration KDE retire un heartbeat 1 s incompatible ;
- password unlock human-validé.

### Rel50 : dernier socle driver humainement très solide
Commit :
`c8ec8cb fix(fingerprint): rearm resume and retain same-press captures`

Caractéristiques :
- TTL warm 5 min ;
- 3 images same-press ;
- 3 poses ;
- seuil 7 ;
- retire l’early cutoff rel47.
Human normal lock :
- première pose 4/4/4 ;
- deuxième pose 15 puis 7 -> succès.

Ce commit a servi plus tard de socle de rollback de sécurité.

### Rel51
Commit `277a272`.
Retire le TTL 5 min pour garder un contexte warm indéfiniment.
Human normal lock :
- WARM_REBASE ~1.75 s ;
- score 13/7 ;
- succès.
Mais après plusieurs heures, cette hypothèse « warm valide indéfiniment » s’est révélée mauvaise.

### Rel52
QML v6 démarre l’auth plus agressivement via Component.onCompleted.
Driver biométrique = rel51.
Régression UX/lifecycle ; ne pas réintroduire cet early start sans preuve.

### Rel53
Commit `7bd9919`.
Ajoute bootstrap RAM-only background pour doigt déjà posé au resume.
Human : deep S3 échoué.
Plus tard supprimé, car un vieux background peut faire chuter les genuine scores vers 2–4.

### Rel54
Intègre le fix upstream KScreenLocker bug 481808 / MR !340 / commit
`992f3fa8f4c4ade5dad7df789e1883a5d5e8ac2c` pour ne pas transformer suspend en échec PAM.
Human : deep S3 échoué.
Diagnostic : au S3 concerné, **aucune activité fprintd** post-resume.

### Rel55
Commit driver `035f923`.
Tente de préserver l’opération active à travers S3 + critical sections.
Human normal lock échoué après longue durée awake.
Forensics :
- WARM_REBASE normal ;
- scores 2–4 ;
- pas de S3 récent ;
- fprintd actif ~6.5 h.
Hypothèse : contexte sensor-side image dégradé après long idle.
Cette branche n’est plus le socle final.

### Rel56
Commit `23c6833`.
Restaure TTL warm 5 min.
Human lock initial échoué ; puis **après reboot rel56 lock OK**.
Après une veille automatique : unlock échoué.
C’est ce test qui a fortement isolé « reboot remet en bon état, S3 peut dégrader ».

### Rel57
Commit `2152dae`.
Expérimente Windows SLEEP 0x60/01 00 au close et WakeupMCU avant warm validation.
Human :
- login échoué ;
- lock au bout de 2–3 poses ;
- S3 échoué.
Forensics importante :
- **aucun marqueur SLEEP rel57 n’avait été exécuté dans le boot humain concerné** ;
- l’échec S3 avait zéro requête fprintd après resume.
Donc ne pas conclure que SLEEP a été causal ; la piste a été retirée.

### Rel58
Commit `a84ebb7`.
Retour volontaire au core rel50 + tentative de rearm KScreenLocker C++.
Human : login, lock et S3 échoués.
Le login a capturé de vraies images à 3–4/7.
Le S3 montrait encore des problèmes de réarm PAM.

### Rel59
Commit `3a61760 fix(fingerprint): pace same-press image retries`.

Découverte clé :
- succès rel56 : première image retry, puis images 2/3 first-try -> scores 4→6→7 ;
- rel58 raté : chaque image nécessitait un retry -> scores 4→4→3.

Fix rel59 :
- si une image valide a nécessité le retry sûr no-evidence, appliquer immédiatement le pacing avant l’image suivante ;
- RetryCaptureIMG respecte `gx_capture_gap_us()` après FDT.
Human normal lock :
- 5/7 -> pacing 250→300 % -> 6/7 -> 7/7 ;
- succès.
Human deep S3 :
- fonctionnel, mais premier cycle pouvait rester 3–4 avant second cycle à 8/7.

### Rel60
Commit `e876def fix(fingerprint): rearm MCU between failed poses`.

Après une pose exploitable mais sous seuil :
- attendre finger release ;
- WakeupMCU ;
- armer pose suivante.
Human normal lock :
- le driver n’a vu qu’une vraie pose ;
- score **9/7 dès la première image** ;
- succès.
Le premier toucher perçu avait été avant READY.

Après un reboot ultérieur :
- login a eu une vraie pose 4/7 ;
- rel60 a correctement fait WakeupMCU puis READY 2/3 ;
- PAM a expiré avant nouvelle pose.

Surtout, trois S3 ultérieurs montraient :
- KScreenLocker logguait un rearm ;
- **aucune activité fprintd après resume**.
Cela a isolé le problème dans le worker PAM/KDE, pas le driver.

### Rel61 — premier vrai fix PAM resume validé
Commit :
`0e8a50a fix(lockscreen): restart fingerprint PAM after resume`

Root cause Plasma 6.7.5 :
- `PamWorker::authenticate()` ignore un nouveau tryUnlock si `m_inAuthenticate=true` ;
- `PAM_AUTHINFO_UNAVAIL` peut latcher `m_unavailable=true`, rendant les tryUnlock suivants no-op.

Fix :
- ne jamais annuler password PAM au resume ;
- recycler uniquement les authenticators non-interactifs ;
- si fingerprint PAM stale est encore actif, le cancel lui seul ;
- attendre unwind ;
- respecter fail-delay ;
- clear du latch unavailable ;
- relancer un nouveau PAM fingerprint.

Human deep-S3 rel61 : **PASS**.
Exact :
- resume KScreen hook 01:26:39.755 ;
- vieux worker : `active=false unavailable=true` ;
- fprintd repart réellement ;
- premier TLS échoue puis recovery ;
- deux touches utilisateur arrivent avant READY et sont correctement rejetées comme contamination de background ;
- READY 01:27:01.260 ;
- première vraie pose DETECTED 01:27:01.744 ;
- première image = **20/7** ;
- succès.

Conclusion rel61 :
- PAM resume corrigé ;
- biometric quality excellente après READY ;
- gros défaut restant = latence resume→READY (~21.5 s dans ce test).

## 7. Rel62 fast-resume — état actuel

Branche :
`fingerprint-rel62-fast-resume`

Commits :
- `a1e6cdd perf(fingerprint): bound cold resume preparation`
- `21effd3 docs(fingerprint): finalize rel62 fast resume`

Package live :
`libfprint-goodix51a0 1.94.100.goodix51a0-62`

SHA256 package final rel62 enregistré :
`9d0557776881a958ff8c83f1cedf70c3c5a1d41995c8e49fa09884bdfcd58715`

### Changements driver rel62

1. `driverstate_attempted` process-local :
   - Windows DriverState Install est considéré first-init work ;
   - tenté une fois par lifetime fprintd ;
   - les cold/S3 rebuilds du même daemon le sautent ensuite.

2. TTL warm :
   - le bound 5 minutes est conservé ;
   - ne jamais revenir au warm indéfini de rel51.

3. Hard lifecycle boundary = vrai sleep ou `force_cold_reset` :
   - discard warm host state ;
   - open transport ;
   - **reset + Stage2E/A8 via `gx_recover_capture_context()` avant le premier TLS** ;
   - but : éviter de perdre plusieurs secondes dans un handshake TLS sur un MCU encore mal revenu.

4. Awake TTL expiry :
   - reset GPIO normal ;
   - ne paye pas le reset+A8 fast-resume supplémentaire.

5. Active-operation S3 :
   - même reset+A8 avant `gx_cold_prepare()`.

6. TLS :
   - `GX_TLS_SESSION_ATTEMPTS = 3` au lieu de 5 ;
   - outer `GX_PREPARE_ATTEMPTS = 2` reste ;
   - si un contexte échoue, recovery complet reset+A8 reste possible ;
   - on évite simplement de perdre énormément de temps en retries TLS identiques.

7. Rel59 et rel60 restent intégrés :
   - same-press retry-assisted pacing immédiat ;
   - RetryCaptureIMG barrier calibré ;
   - WakeupMCU après une pose exploitable mais sous seuil, après finger release.

### KScreenLocker rel62

Package live :
`kscreenlocker 6.7.5-1.5`

SHA256 package :
`71c13d27b595fe9982d66b20ba84d207784f10070c25117d1f2b6690cf2271fc`

Base = rel61 robuste fingerprint-only restart, plus optimisation :
- `PamWorker::resetUnavailable()` reset aussi
  `m_nextAttemptAllowedTime = steady_clock::now()` ;
- le restart sait si son origine est le stale `m_unavailable` ;
- un fail-delay généré par cette ancienne transaction hardware-unavailable est ignoré pour le restart resume ;
- un vrai échec biométrique conserve le vrai fail-delay PAM normal.

Objectif : supprimer le ~4 s entre hook resume rel61 et premier trafic fprintd, lorsqu’il provient seulement d’un stale PAM_AUTHINFO_UNAVAIL et pas d’un mauvais doigt.

### Plasma Login Manager rel62

Package live :
`plasma-login-manager 6.7.5-3.9`

SHA256 package :
`71afaa14faa27815f99cb45e3c9d0d80319c794f0a099aef1c093de237d0589a`

Service fingerprint réel :
`/usr/lib/pam.d/plasmalogin-fingerprint`

Live :
`-auth required pam_fprintd.so max-tries=1 timeout=30`

Pourquoi :
- le driver gère déjà 3 poses physiques x jusqu’à 3 images same-press ;
- max-tries PAM n’a pas besoin de répliquer ce budget ;
- timeout 30 évite que le PAM login expire pendant une vraie préparation froide ;
- password reste un authenticator parallèle et peut gagner immédiatement.

### fprintd rel62

Drop-in live :
`/usr/lib/systemd/system/fprintd.service.d/50-goodix51a0-runtime.conf`

Important :
- `ExecStart=/usr/lib/fprintd --no-timeout`
- l’objet libfprint et son contexte warm restent vivants entre Claim/Release ;
- Before=display-manager.service ;
- DeviceAllow gpiochip ;
- LimitCORE=0.

### Mesures rel62 déjà faites

Après restart fprintd seulement, final rel62 :
- cold bounded prewarm : **5049 ms** ;
- succès sur premier helper invocation ;
- pas de TLS handshake failure dans cette mesure.

Même daemon plus tard :
- warm Claim : **1804 ms**.

Comparaison :
- rel33 historique cold simulation : ~4703 ms ;
- rel61 human S3 : ~21.5 s resume→READY, aggravé par un TLS fail + 2 touches avant READY ;
- rel62 intermédiaire avait parfois dépassé 40 s lors de retries TLS pathologiques ;
- final rel62 ramène un cold prep sain vers ~5 s.

### Human gate rel62 : PAS ENCORE FAIT

C’est le point exact où reprendre.

Ne pas reboot Pegasus.
L’utilisateur doit faire **une seule veille deep S3 manuelle**, puis toucher naturellement au wake lockscreen.

Ensuite inspecter avant toute modification :
- PM suspend exit ;
- KScreen `Resume: rearming fingerprint PAM` ;
- éventuel `ignoring stale fail-delay from unavailable noninteractive PAM` ;
- premier trafic fprintd/GXFP ;
- marqueurs FAST_RESUME reset+A8 ;
- nombre d’essais TLS ;
- timestamp READY ;
- premier vrai DETECTED_HOLD ;
- score(s) image(s) ;
- unlock result.

Ne pas déclarer rel62 validé avant ce gate.

## 8. Tests déjà effectués et garde-fous

Toujours préférer les tests du repo plutôt que des scripts improvisés.

### Suite globale
`make -C fingerprint/research test`

A été PASS pour rel62.

### Boot binding
`python3 tests/test-goodix51a0-boot-binding.py`
PASS rel62.

### Tests critiques actuels
Notamment :
- `test_fast_resume_source_safety.sh`
- `test_lifecycle_recovery_source_safety.sh`
- `test_native_resume_recovery_source_safety.sh`
- `test_get_image_ack_tls_timeout_recovery_source_safety.sh`
- `test_get_image_retry_source_safety.sh`
- `test_tls_irq_poll_bounds_source_safety.sh`
- `test_same_press_verify_source_safety.sh`
- `test_retry_assisted_capture_calibration_source_safety.sh`
- `test_retry_pose_mcu_rearm_source_safety.sh`
- `test_kscreenlocker_suspend_pam_source_safety.sh`
- `test_plasma_login_dual_auth_source_safety.sh`
- `test_boot_prewarm_source_safety.sh`
- `test_release_biometric_dump_guard_source_safety.sh`
- `test_gq_sigfm_fpeval_source_safety.sh`
- `test_production_clean_calibration_source_safety.sh`
- `test_capture_clear_sensor_gate_source_safety.sh`
- `test_fresh_warm_handoff_source_safety.sh`
- `test_warm_rebase_source_safety.sh`
- `test_sleep_lifecycle_source_safety.sh`
- `test_resume_held_finger_bootstrap_source_safety.sh`

### GQ-SIGFM réel
Le repo contient un adapter fp_eval réel :
- `fingerprint/research/eval/gq_sigfm_fpeval.c`
- `build-gq-sigfm-fpeval.sh`
- `test-gq-sigfm-fpeval.py`
Le smoke ABI réel a PASS.

### Builds
Déjà PASS :
- libfprint v1.94.100 Meson/Ninja complet ;
- KScreenLocker 6.7.5-1.5 complet ;
- Plasma Login Manager package 6.7.5-3.9 ;
- source manifest SHA gates ;
- release biometric dump hook absent.

### Package/live integrity déjà vérifiée
Rel62 final :
- libfprint package 40 files / 0 modified ;
- kscreenlocker 346 / 0 modified ;
- plasma-login-manager 210 / 0 modified ;
- QML helper --check PASS ;
- qmllint PASS ;
- fprintd active ;
- enrollments intacts ;
- 0 failed systemd units ;
- 0 orphan packages après cleanup.

## 9. Hypothèses / approches REFUTÉES ou à ne pas réintroduire

1. **Baisser le threshold sous 7** : interdit et injustifié.
2. **Ré-enrôler pour résoudre les scores 2–4** : non. Les mêmes templates ont scoré 23, 20, 15, 13, 11, 9, 8, 7 dans des contextes sains.
3. **Cutoff same-press score<=4** : réfuté par rel40/50/59.
4. **Warm context indéfini** : rel51, réfuté après longue durée.
5. **Stale pre-S3 background bootstrap** : rel53 ; peut dégrader fortement les scores, supprimé.
6. **Sensor SLEEP 0x60 au close** : rel57 ; non démontré utile et retiré.
7. **Heartbeat/retry auth chaque seconde** : bruit, race « attempt too soon », retiré.
8. **External system-sleep resume hooks** : ne pas réintroduire tant que rel61/62 lifecycle natif fonctionne.
9. **Keepalive timer périodique** : rejeté.
10. **Aggressive QML Component.onCompleted auth** : rel52 regression.
11. **Préserver la même libfprint action active à travers S3 coûte que coûte** : rel55 complexité non retenue.
12. **Supposer que GET_IMAGE no-ACK retry est le bug** : un retry no-evidence est normal et existait aussi dans des succès élevés ; le vrai danger est de rejouer après ACK/TLS evidence.
13. **Rejouer accepted GET_IMAGE après timeout** : interdit, rel48 a fixé cela.
14. **Pinctrl SPI différent après S3** : contrôlé, les pads revenaient exactement aux valeurs de référence.
15. **Ancien reset 10/100 ms** : runtime actuel utilise 300/600 ms validé.
16. **Changer power/control LPSS/pca2xx à on** : observé dans tooling upstream mais causalité non prouvée sur Pegasus ; pas de modification production.
17. **Confondre touches avant READY avec faux rejets biométriques** : plusieurs tests ont montré que l’utilisateur touche pendant cold calibration avant que le driver soit armé. Toujours lire les logs DETECTED_HOLD avant de compter une « pose ».

## 10. Pièges runtime / interprétation

- Un utilisateur peut dire « j’ai dû poser 2/3 fois » alors que le driver n’a capturé qu’une seule pose ; vérifier timestamps greeter vs READY vs DETECTED_HOLD.
- Les touches pendant calibration peuvent logguer `background contaminated by touch` et sont volontairement rejetées. Ce n’est pas un échec matcher.
- `pam_fprintd` peut relancer une nouvelle opération Identify dans son timeout ; distinguer « nouveau cycle PAM » de « pose suivante du même cycle ».
- KScreenLocker peut logguer rearm sans trafic fprintd si un worker PAM stale est bloqué/unavailable ; rel61/62 sont conçus pour résoudre cela.
- Le boot-prewarm service existe mais est live **disabled** au moment de ce handoff. Ne pas le considérer actif.
- Après package build, nettoyer src/pkg/tarballs/temp logs et build deps.
- Ne jamais supprimer `/var/lib/pacman/db.lck` sans vérifier qu’aucun vrai pacman/makepkg/paru/yay n’est actif ; une fois, le lock appartenait à une vraie update CachyOS.
- Les packages custom peuvent être réinstallés pendant certaines étapes diagnostics ; toujours vérifier `pacman -Q` avant d’interpréter un test.

## 11. Commandes de reprise immédiate

D’abord :
```bash
date -Is
cd '/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux'
git status --short --branch
git log -5 --oneline --decorate
pacman -Q libfprint-goodix51a0 kscreenlocker fprintd plasma-login-manager
systemctl show fprintd.service -p MainPID -p ActiveEnterTimestamp -p SubState --no-pager
fprintd-list arezki
```

Après le prochain S3 utilisateur :
```bash
journalctl -b --since '-12 min' --no-pager -o short-precise |
  grep -Ei 'PM: suspend entry|PM: suspend exit|PrepareForSleep|Resume: rearming fingerprint PAM|stale fail-delay|Restarting PAM authenticator|fprintd|GXFP51A0|FAST_RESUME|TLS handshake|cold preparation|READY|DETECTED_HOLD|same-press image|score=|MCU rearmed|Authentication race|LoginCancelled'
```

Puis journal fprintd brut :
```bash
journalctl -b -u fprintd.service --since '-12 min' --no-pager -o short-precise
```

## 12. Critères de succès à viser

Rel62 idéalement doit donner :
- rearm PAM presque immédiat ;
- premier trafic fprintd très proche du resume ;
- reset+A8 propre avant premier TLS ;
- pas de chaîne de retries TLS pathologiques ;
- READY nettement plus proche des ~5 s cold mesurés que des ~21.5 s rel61 ;
- toute touche avant READY ne doit jamais contaminer un background accepté ;
- première vraie pose doit retrouver les scores sains observés (souvent >=7, parfois 9/20+) ;
- password doit rester disponible immédiatement.

Après validation rel62 S3 seulement :
- mesurer normal lock visible→READY ;
- mesurer login cold au prochain reboot naturel, pas forcé ;
- décider si le boot-prewarm disabled doit être réactivé/retiré/reconceptualisé ;
- optimiser encore seulement avec mesures comparatives et sans dégrader sécurité/fiabilité.

## 13. État à ne pas perdre

**La prochaine session ne doit PAS recommencer l’enquête.**
Elle doit partir de :
- rel61 S3 human-validé ;
- rel62 installé, software-validé, human S3 pending ;
- matcher/seuil/templates ne sont pas la cible ;
- le prochain vrai travail est le gate humain rel62 S3 + mesure précise de latence ;
- si rel62 passe, seulement ensuite optimisation login/boot-prewarm et UX visible→READY.

## 14. Update 2026-09-30 — rel62 FAIL, rel63 candidate

Cette section supersède l’état pending de la section 13.

- rel62 deep S3 humain: **FAIL**.
- KScreen/PAM restart correct et quasi immédiat.
- aucun marqueur FAST_RESUME avant le premier TLS.
- premier TLS digest fail, recovery tardive, READY ~17.366 s après resume.
- vraies poses post-READY répétées à 3/7.
- diagnostic: l’epoch S3 était effacée par `gx_warm_abandon()`, donc un warm state déjà invalidé pouvait masquer le lifecycle boundary.
- branche suivante: `fingerprint-rel63-s3-epoch`.
- rel63 arme l’epoch BOOTTIME-MONOTONIC dès l’init et la conserve indépendamment du warm TLS.
- suite complète, boot binding et full Meson/Ninja: PASS.
- package rel63 construit, mais pas encore installé car RDC bloque `pacman -U`.
- handoff détaillé: `fingerprint/handoff/HANDOFF_2026-09-30_REL63_S3_EPOCH.md`.
- prochain gate: installation rel63, reboot manuel déjà souhaité par l’utilisateur, cold login, puis deep S3 humain rel63.

## 15. Update 2026-09-30 — rel63 FAIL, rel64 candidate

- rel63 deep S3 humain: **FAIL**.
- PAM/KScreen restart correct.
- transport/TLS nettement amélioré: aucune erreur digest, READY ~8.484 s après resume.
- calibration rejette correctement les touches précoces.
- vraies images post-READY restent 3–4/7 sur plusieurs poses.
- comparaison au rel61 S3 réussi (20/7) montre une différence empirique importante: rel61 rejouait DriverState Install sur le cold rebuild post-S3, rel62/63 le sautaient après le premier init daemon.
- branche: `fingerprint-rel64-s3-recondition`.
- rel64 rejoue DriverState Install uniquement après un vrai S3, conserve reset+A8 pré-TLS et ajoute des marqueurs `S3_TRACE` visibles.
- boot-prewarm packaging corrigé: unité présente mais plus de symlink auto-start dans `graphical.target.wants`.
- tests complets + boot binding + full Meson/Ninja: PASS.
- package rel64 construit, pas encore installé.
- handoff détaillé: `fingerprint/handoff/HANDOFF_2026-09-30_REL64_S3_RECONDITION.md`.
