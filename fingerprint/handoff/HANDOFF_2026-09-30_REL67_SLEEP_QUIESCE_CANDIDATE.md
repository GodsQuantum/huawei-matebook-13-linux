# HANDOFF — rel67 sleep-quiesce candidate

Date: 2026-09-30
Machine: Pegasus uniquement
Branch: fingerprint-rel67-sleep-quiesce
Base stable: rel66 / c149ac5 + human validation e6298e0

## Baseline rel66 conservée

rel66 deep S3 humain VALIDÉ:
- PM suspend exit 22:55:44.758879
- KScreen PAM rearm 22:55:44.766391
- READY 22:55:49.192664
- DETECTED_HOLD 22:55:51.480747
- first image score **7/7**
- unlock humain OK
- resume -> READY ~4.434 s
- resume -> accepted score ~7.809 s

rel66 reste la baseline stable et le package -66 doit être conservé pour rollback.

## Défaut secondaire observé

Après l'unlock rel66:
- LIFT_NOW 22:55:53.390986
- Close tente SLEEP 0x60 à 22:55:53.546338
- soit ~155 ms plus tard
- GPIO IRQ encore HIGH
- gx_target_send_ack refuse d'écrire:
  pre-write-irq-high cmd=0x60
- warm stash refusé, fallback cold sûr.

Ce défaut ne casse pas l'unlock ni S3; il fait seulement perdre le prochain warm reopen.

## Recherche Windows

Trace:
tlambertz/goodix-fingerprint-reversing
logs/3_wbdi_singleunlock.log ref 0479ce91

Séquence Windows:
- EvtCancelPendingRequest finit à 10:17:20.516
- ReqOnActivate(false) commence 10:17:20.562
- FpMcuSwitchToSleepMode entre 10:17:20.594
- cmd 0x60 payload 01 00 envoyé 10:17:20.611
- ACK reçu immédiatement
- donc Windows laisse la requête précédente se quiescer avant SLEEP.

## rel67: changement minimal

Aucun changement:
- matcher / SIGFM
- threshold 7
- enrollments/templates
- GPIO reset 300/600 ms
- TLS
- cold prepare
- fresh background/FDT
- S3 cold-boundary rel66
- KDE/PAM
- boot-prewarm
- runtime PM

Seul gx_sensor_sleep() change:
- nouvelle constante GX_SLEEP_QUIESCE_MS = 400
- avant cmd 0x60, attendre IRQ LOW jusqu'à 400 ms
- aucun drain aveugle de paquet
- si IRQ ne descend pas: log REL67_TRACE + fallback rel66 inchangé
- si IRQ descend: cmd 0x60 puis ACK obligatoire comme rel66
- si IRQ est déjà LOW: pas de délai significatif.

Objectif:
récupérer le warm stash après unlock sans modifier le chemin d'auth ni le S3 validé.

## Validation software

PASS:
- research suite complète
- test_sleep_lifecycle_source_safety
- native resume recovery
- lifecycle recovery
- dual auth
- KScreen resume PAM
- GQ-SIGFM evaluator
- boot binding
- git diff --check
- full Meson/Ninja libfprint v1.94.100
- source manifest
- artifact gates
- release biometric dump absent

Package:
libfprint-goodix51a0-1.94.100.goodix51a0-67-x86_64.pkg.tar.zst

SHA256:
e883cdcf772269b04e69537b1ed8d8efd04bb1393ed49ed2dada8007ddf2e6da

## Gate humain

1. installer rel67, sans reboot/re-enrollment;
2. faire un lock/unlock fingerprint normal;
3. inspecter:
   - match >=7
   - LIFT_NOW
   - REL67_TRACE SLEEP ACK ou bounded skip
   - si ACK: prochain Claim doit WakeupMCU + WARM_REBASE rapidement;
4. seulement si normal lock OK, faire un deep S3 humain;
5. S3 doit conserver le gate rel66: unlock >=7.

Rel67 ne devient baseline que si normal lock ET deep S3 sont validés.
