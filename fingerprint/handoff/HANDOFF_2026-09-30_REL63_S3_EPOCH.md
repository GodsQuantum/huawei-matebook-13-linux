# HANDOFF — rel63 S3 epoch candidate

Date: 2026-09-30
Machine: Pegasus uniquement
Branche: `fingerprint-rel63-s3-epoch`

## Résultat humain rel62

rel62 deep S3: FAIL.

Cycle exact:
- PM suspend entry: 09:51:56.715518
- PM suspend exit: 09:52:10.641482
- KScreen resume hook: 09:52:10.647060
- fingerprint PAM restart: 09:52:10.647087
- premier trafic fprintd: 09:52:12.744899
- premier TLS fail digest: 09:52:14.112524
- accepted GET_IMAGE TLS timeout: 09:52:22.189149
- recovery complète déclenchée tardivement
- READY: 09:52:28.007512
- resume -> READY: ~17.366 s
- READY -> first DETECTED_HOLD: ~0.584 s

Biométrie après READY:
- pose 1: 3/7, 3/7, 3/7
- pose 2: 3/7, 3/7, 3/7
- pose 3: 3/7, 3/7
- cycle suivant: première image rejetée quality gate

Conclusion:
- PAM/KScreenLocker a correctement redémarré.
- fprintd a repris.
- transport/TLS a échoué puis récupéré.
- les vraies images post-READY restent à 3/7: état image post-S3 dégradé.
- aucun marqueur `FAST_RESUME` n’apparaît avant le premier TLS alors que le binaire live rel62 contient ces chaînes.

## Root cause rel62

Le détecteur S3 `gx_warm_crossed_sleep()` dépendait de
`warm_sleep_clock_valid`. Or `gx_warm_abandon()` effaçait cette baseline.
Un Claim/échec/abandon antérieur pouvait donc supprimer l’unique preuve RAM-only
qu’un prochain Open avait traversé S3. Résultat: pas de hard lifecycle boundary,
pas de reset+A8 pré-TLS; la panne n’était découverte qu’après TLS/image timeout.

## rel63 candidate

Correctif minimal:
- l’epoch `CLOCK_BOOTTIME-MONOTONIC` est armée dès l’init du device;
- elle survit à `gx_warm_abandon()`;
- elle reste process-local/RAM-only;
- après S3, `gx_dev_open()` peut donc imposer reset+A8 avant premier TLS même si le warm state avait déjà été invalidé.

Inchangés:
- threshold 7;
- GQ-SIGFM/template v4;
- enrollments;
- GPIO/reset 300/600 ms;
- same-press / pose budget;
- PAM/KScreenLocker rel62;
- aucun hook system-sleep, heartbeat, keepalive ou fichier timing persistant.

Package:
`libfprint-goodix51a0-1.94.100.goodix51a0-63-x86_64.pkg.tar.zst`
SHA256:
`dd34359bd5886fc974e1e9efafd371e3456ba26bfed13cd3690f6a0dd3d8420b`

Software validation:
- `make -C fingerprint/research test`: PASS
- `tests/test-goodix51a0-boot-binding.py`: PASS
- `git diff --check`: PASS
- full Meson/Ninja libfprint v1.94.100: PASS
- source manifest: PASS
- release biometric dump hook: absent
- package build: PASS

État live au moment de ce handoff:
- rel62 reste installé;
- rel63 n’est PAS encore installé;
- RDC bloque explicitement l’exécution de `pacman -U`;
- aucun reboot/suspend/lock n’a été déclenché par l’assistant;
- l’utilisateur a indiqué qu’un reboot manuel est de toute façon nécessaire après de nombreuses updates.

Prochain ordre:
1. installer le package rel63 manuellement;
2. reboot manuel utilisateur;
3. inspecter cold login après ce reboot naturel;
4. effectuer ensuite un deep S3 humain rel63;
5. vérifier impérativement le marqueur FAST_RESUME avant premier TLS puis mesurer resume→READY et les scores.
