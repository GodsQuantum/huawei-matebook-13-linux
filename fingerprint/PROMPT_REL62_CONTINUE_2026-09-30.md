# PROMPT À COPIER-COLLER — reprise GXFP51A0 exactement au rel62

Tu reprends un chantier fingerprint Linux très avancé sur **Pegasus uniquement**.

## Règle n°1 : ne redécouvre rien

Avant toute action, lis EN ENTIER :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/HANDOFF_REL62_FULL_2026-09-30.md`

Puis consulte si nécessaire :
- `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/HANDOFF_CURRENT.md`
- `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/README.md`
- les docs de `fingerprint/docs/`
- les anciens handoffs de `fingerprint/handoff/`.

Ne me fais pas redécouvrir en milieu de session des choses déjà faites. Le handoff canonique contient l’historique rel20→rel62, les recherches GitHub, les tests humains, les hypothèses réfutées, les hashes/packages, les pièges PAM/KDE et les prochains gates.

## Machine / accès

Pegasus :
- Huawei MateBook 13 2021 ;
- i7-10510U, 16 GiB, 1 TiB ;
- CachyOS / Plasma ;
- Goodix GXFP51A0 / GF3658 ST411 SPI.

Remote Desktop Commander Pegasus device id :
`8a6eeb21-0158-4e6d-b3ea-91d580f8a223`

Travaille directement sur Pegasus avec RDC. Ne déporte pas ce chantier sur Cloud9/Galactica.

Workspace :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/`

Repo :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/`

GitHub :
`GodsQuantum/huawei-matebook-13-linux`

## État exact au départ

Branche :
`fingerprint-rel62-fast-resume`

HEAD :
`21effd3 docs(fingerprint): finalize rel62 fast resume`

Implémentation :
`a1e6cdd perf(fingerprint): bound cold resume preparation`

Live :
- `libfprint-goodix51a0 1.94.100.goodix51a0-62`
- `kscreenlocker 6.7.5-1.5`
- `plasma-login-manager 6.7.5-3.9`
- `fprintd 1.94.5-2.1`
- fprintd tourne avec `--no-timeout`.

Enrôlements :
- right-index
- left-index
- right-middle

Matcher :
- GQ-SIGFM / SIGFM v3
- template v4
- threshold **7**, NON NÉGOCIABLE
- 20 enroll views
- 3 images same-press max
- 3 poses physiques max.

## Ce qui est déjà humainement validé

Rel48 :
- cold login 23/7 ;
- deep S3 11/7 ;
- sécurité accepted GET_IMAGE timeout validée.

Rel50 :
- normal lock humain réussi ;
- same-press rescue et budget complet validés.

Rel59 :
- normal lock PASS avec séquence 5→6→7 ;
- correction pacing same-press démontrée.

Rel60 :
- normal lock PASS ;
- première vraie pose 9/7.

Rel61 :
- deep S3 PASS ;
- KScreenLocker a réellement redémarré le worker PAM fingerprint ;
- première vraie pose après READY = **20/7** ;
- les « plusieurs poses » avant étaient des touches pendant calibration, pas des faux rejets.

Donc :
- les templates sont bons ;
- le matcher est bon ;
- le threshold 7 est bon ;
- le problème actuel n’est PAS « il faut ré-enrôler » ;
- le problème actuel principal est **latence resume/login → READY**.

## Rel62 : ce qui a déjà été optimisé

Rel62 conserve rel59/60/61 et ajoute :

1. `driverstate_attempted` :
   DriverState Install une fois par lifetime fprintd, pas à chaque cold/S3 rebuild.

2. Hard lifecycle boundary (vrai S3 / force_cold_reset) :
   full reset + Stage2E/A8 via `gx_recover_capture_context()` AVANT premier TLS.

3. Awake TTL expiry :
   reset normal seulement.

4. Active-S3 recovery :
   même reset+A8 avant cold prepare.

5. TLS :
   inner attempts réduits de 5 à 3 ;
   outer prepare attempts reste 2 ;
   on évite les runs pathologiques >40 s sans supprimer le recovery complet.

6. KScreenLocker 6.7.5-1.5 :
   rel61 robust fingerprint-only restart conservé ;
   stale `PAM_AUTHINFO_UNAVAIL` ne doit plus injecter inutilement ~4 s de fail-delay au resume ;
   password PAM n’est jamais annulé.

7. Plasma Login Manager 6.7.5-3.9 :
   vrai service PAM fingerprint :
   `/usr/lib/pam.d/plasmalogin-fingerprint`
   avec :
   `pam_fprintd.so max-tries=1 timeout=30`.

8. fprintd :
   `--no-timeout` pour conserver warm state.

Mesures rel62 déjà faites :
- cold bounded prewarm : **5049 ms** ;
- warm Claim : **1804 ms** ;
- full tests/builds PASS.

## IMPORTANT : boot-prewarm

`gxfp51a0-boot-prewarm.service` existe mais est actuellement **disabled/inactive**.

Ne suppose PAS qu’il s’exécute au prochain reboot.

Ne l’active pas immédiatement : d’abord valide rel62 S3. Ensuite seulement, au prochain reboot naturel, si le login reste froid/lent, audite si ce service doit être réactivé, remplacé ou supprimé.

## Prochain gate EXACT — ne fais rien d’autre avant

Je dois faire **une veille deep S3 manuelle** sous rel62.

Tu ne dois PAS :
- suspendre toi-même ;
- locker toi-même ;
- reboot ;
- poweroff.

Quand je te réponds par exemple :
`rel62 S3 OK`
ou
`rel62 S3 échoué`

alors immédiatement :

1. lis les logs exacts du dernier S3 ;
2. mesure :
   - PM suspend exit ;
   - KScreen resume hook ;
   - stale fail-delay skip éventuel ;
   - premier appel fprintd ;
   - FAST_RESUME reset+A8 ;
   - TLS attempts ;
   - READY ;
   - DETECTED_HOLD ;
   - scores ;
   - unlock result ;
3. compare au rel61 humain :
   - resume hook 01:26:39.755 ;
   - fprintd réel 01:26:43.641 ;
   - premier TLS fail ;
   - READY 01:27:01.260 ;
   - première vraie image 20/7 ;
   - resume→READY ~21.5 s.

Le but rel62 est de ramener le S3 réel proche du cold prep mesuré ~5 s, sans perdre la fiabilité.

Commande utile après mon test :
```bash
journalctl -b --since '-12 min' --no-pager -o short-precise |
  grep -Ei 'PM: suspend entry|PM: suspend exit|PrepareForSleep|Resume: rearming fingerprint PAM|stale fail-delay|Restarting PAM authenticator|fprintd|GXFP51A0|FAST_RESUME|TLS handshake|cold preparation|READY|DETECTED_HOLD|same-press image|score=|MCU rearmed|Authentication race|LoginCancelled'
```

Puis :
```bash
journalctl -b -u fprintd.service --since '-12 min' --no-pager -o short-precise
```

## Si rel62 S3 passe

Ne saute pas directement dans un rel63.

D’abord :
- consigne les timings exacts ;
- compare rel61 vs rel62 ;
- commit/push la validation ;
- confirme que password reste parallèle ;
- vérifie QML/KScreen/fprintd package integrity ;
- garde repo clean.

Ensuite seulement optimise « à mort » ce qui reste, par ordre :
1. resume→first fprintd ;
2. first fprintd→TLS ready ;
3. TLS→clean background/FDT ;
4. visible lockscreen→READY ;
5. login cold au prochain reboot NATUREL ;
6. boot-prewarm disabled à réévaluer.

Ne sacrifie jamais le clean-background invariant : si le doigt est posé pendant calibration, le driver doit refuser ce background.

## Si rel62 S3 échoue

Avant tout code :
- déterminer si fingerprint PAM a réellement redémarré ;
- distinguer absence fprintd / transport / TLS / background / matcher ;
- ne touche au matcher que si une vraie image saine arrive et que les genuine scores restent bas de façon répétable.

Règles de diagnostic :
- pas de fprintd après resume => KDE/PAM ;
- fprintd mais pas READY => transport/TLS/prep ;
- READY + DETECTED + scores 3–4 => capture/imaging/timing ;
- scores >=7 mais pas unlock => PAM/UI/result propagation ;
- touches avant READY ne comptent pas comme faux rejet biométrique.

## Ce qu’il ne faut PAS réintroduire

- threshold <7 ;
- re-enrollment « pour voir » ;
- same-press cutoff <=4 ;
- warm context indéfini rel51 ;
- stale pre-S3 background bootstrap rel53 ;
- sensor SLEEP 0x60 experiment rel57 ;
- QML heartbeat ;
- QML aggressive Component.onCompleted rel52 ;
- periodic keepalive ;
- external system-sleep hook ;
- même libfprint operation forcée à travers S3 rel55 ;
- accepted GET_IMAGE replay après ACK/TLS ;
- persistance de timing ;
- GPIO112/GPP_D16 ;
- power/control=on LPSS/pca2xx sans preuve ;
- vieux reset 10/100 ms.

Reset validé :
GPIO264 HIGH 300 ms -> LOW 600 ms.

## Recherches upstream déjà faites

Au 30 septembre 2026 :
- szlukabence/goodix-fingerprint-spi-linux : dernier pertinent 21 sept., pas de nouveau fix GXFP51A0 S3 ;
- Sigfrodr/libfprint-goodixtls : dernier pertinent 25 sept., GQ-SIGFM evaluator ;
- issue Sigfrodr #5 : genuine mean ~20.35, impostor mean ~2.05, impostor max 6, EER ~4.73 % ;
- goodix-fp-dump issue #69 : pas de nouveau fix resume ;
- Duro02/goodix-5503-linux : idée fprintd --no-timeout retenue, hook system-sleep NON retenu ;
- Windows transcript : SLEEP 0x60/01 00 + WakeupMCU connu, mais SLEEP-on-close experiment rel57 retiré.

Si tu refais du web, cherche seulement ce qui est **nouveau depuis le 30 septembre 2026** ou une source qu’on n’a vraiment pas encore exploitée. Ne passe pas une heure à retrouver ces mêmes repos.

## Tests à utiliser avant chaque package/install

Minimum :
```bash
make -C fingerprint/research test
python3 tests/test-goodix51a0-boot-binding.py
git diff --check
```

Tests critiques :
- fast resume
- lifecycle/native resume
- accepted GET_IMAGE timeout recovery
- TLS bounds
- same-press
- retry-assisted pacing
- retry-pose MCU rearm
- KScreenLocker suspend/PAM
- Plasma Login dual auth
- GQ-SIGFM fp_eval
- clean calibration
- release biometric dump guard

Puis full Meson/Ninja libfprint build si driver change.
Full KScreenLocker build si patch KDE change.
Full PLM package build si login manager change.

Après install :
- `pacman -Qkk`
- helper `--check`
- `qmllint`
- fprintd active
- 0 failed units
- 0 orphan packages
- cleanup src/pkg/tarballs/temp logs/build deps.

## Pacman

Ne supprime JAMAIS `/var/lib/pacman/db.lck` sans :
```bash
ps -eo pid,ppid,stat,etime,cmd | grep -E '[p]acman|[m]akepkg|[p]aru|[y]ay'
lsof /var/lib/pacman/db.lck
```
On a déjà rencontré un vrai lock appartenant à une update CachyOS légitime.

## Style de travail attendu

- autonome ;
- action-first ;
- latest docs + GitHub/community quand ça apporte du nouveau ;
- ne me demande pas de faire des commandes que tu peux faire via RDC ;
- ne me monopolise que pour une action physique nécessaire ;
- pas de reboot/suspend/lock automatique ;
- fais des commits/push/handoffs propres ;
- clean les build trees/packages temporaires ;
- ne proclame pas succès sans log + human gate ;
- quand un résultat humain arrive, inspecte les logs AVANT de modifier du code.

Commence par lire le handoff canonique, vérifier versions/repo live, puis ATTENDS mon résultat S3 rel62 si je ne l’ai pas encore donné.
