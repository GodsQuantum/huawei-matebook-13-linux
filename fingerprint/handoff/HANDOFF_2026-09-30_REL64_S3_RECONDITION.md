# HANDOFF — rel64 S3 recondition candidate

Date: 2026-09-30
Machine: Pegasus uniquement
Branche: `fingerprint-rel64-s3-recondition`

## Résultat humain rel63

Deep S3 rel63: FAIL.

Cycle principal:
- PM suspend entry: 20:00:21.249352
- PM suspend exit: 20:00:26.862404
- KScreen resume PAM: 20:00:27.316990
- premier trafic fprintd: 20:00:29.169360
- aucune erreur TLS digest/session recovery tardive
- background contaminé par touches précoces correctement rejeté
- READY: 20:00:35.346501
- resume -> READY: ~8.484 s
- first DETECTED_HOLD: 20:00:35.543690

Scores vrais:
- pose 1: 3/7, 3/7, 3/7
- pose 2: 3/7, 4/7, 3/7
- pose 3: 4/7 puis quality gate/release
- cycle suivant encore 3-4/7

Conclusion: PAM/KScreen et transport/TLS fonctionnent; panne restante = état image post-S3 dégradé.

## Comparaison rel61 humain réussi

Rel61:
- resume: 01:26:39.743883
- premier trafic: 01:26:43.641468
- premier TLS échoue à 01:26:49.654646
- récupération complète MCU/session
- deux backgrounds contaminés par touches précoces rejetés
- READY: 01:27:01.260462
- first DETECTED_HOLD: 01:27:01.744127
- première vraie image: **20/7**

Différence de code importante:
- rel61 rejouait `gx_driverstate_install_windows()` à chaque cold rebuild.
- rel62/63 avaient converti DriverState Install en étape once-per-daemon.
- l’optimisation est maintenant contredite par deux échecs post-S3 3–4/7 alors que rel61 donnait 20/7.

## rel64 candidate

- conserve l’epoch S3 rel63;
- conserve reset+A8 pré-TLS;
- remet `driverstate_attempted = FALSE` uniquement sur une vraie frontière S3, dans:
  - `gx_dev_open()`;
  - `gx_session_start()` si opération active;
- les rebuilds awake/TTL gardent l’optimisation once-per-daemon;
- nouveaux marqueurs journal visibles: `GXFP51A0 S3_TRACE ...`;
- threshold 7, GQ-SIGFM v3/template v4, GPIO, PAM, same-press inchangés;
- aucun hook system-sleep, heartbeat, keepalive ou timing persistant.

Validation:
- suite `fingerprint/research test`: PASS;
- boot binding: PASS;
- diff check: PASS;
- full Meson/Ninja: PASS;
- artifact gates: PASS;
- release biometric dump hook absent.

Package:
`libfprint-goodix51a0-1.94.100.goodix51a0-64-x86_64.pkg.tar.zst`
SHA256:
`43cd4e48e5733dc23a7b735518507c16c05bf83fad9bf25bfc9276adaa50bd6f`

Packaging boot-prewarm:
- unité et helper restent installés;
- le symlink `graphical.target.wants/gxfp51a0-boot-prewarm.service` est supprimé du package;
- seul `fprintd.service` reste auto-lié;
- prochain boot ne doit donc plus lancer boot-prewarm tant qu’il n’est pas explicitement activé.
