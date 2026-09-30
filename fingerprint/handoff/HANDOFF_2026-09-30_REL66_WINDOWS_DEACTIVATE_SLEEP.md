# HANDOFF — rel66 Windows deactivate sleep

Date: 2026-09-30
Machine: Pegasus uniquement
Branch: fingerprint-rel66-windows-deactivate-sleep
Base: rel65 / 1615284

## rel65: diagnostic du dernier échec S3

Deep S3 humain:
- suspend entry 21:23:35.326
- suspend exit 21:23:52.602
- KScreen PAM rearm 21:23:52.607
- READY 21:24:05.522
- first true DETECTED 21:24:06.407
- first image score 3/7
- pose suivante rejetée par quality gate.

Aucun S3_CLEAN driver n'a été exécuté: le device Goodix était déjà fermé
avant le suspend. Le cas dominant est donc:
device fermé avant S3 -> premier cold Open post-resume -> mauvaise imagerie.

Le background contaminé par le doigt a bien été détecté et jeté.

## Runtime PM LPSS: testé et réfuté

Chemin matériel:
PCI Intel LPSS 0000:00:1e.3 -> pxa2xx-spi.4 -> spi-GXFP51A0:00.

En auto, runtime_status oscille active/suspended et les cold opens ont des
no-irq retry. Le repo GXFP51A0 de référence force power/control=on pendant
ses sessions de RE.

A/B réel Pegasus effectué via systemd-run root:
- PCI + pxa2xx forcés on;
- cold restart + prewarm;
- no-irq retry toujours présents, pas d'amélioration utile.

Conclusion: runtime PM n'est pas retenu comme cause primaire.
Les deux power/control ont été restaurés à auto.
Ne pas intégrer de force-on permanent.

## Nouvelle preuve Windows

Source inspectée:
tlambertz/goodix-fingerprint-reversing,
logs/3_wbdi_singleunlock.log, ref 0479ce91...

Pile Goodix Windows 1.1.141.36 lors d'une désactivation normale:
1. ReqOnActivate activate=0
2. attend la fin TLS
3. FpMcuSwitchToSleepMode
4. commande 0x60 payload 01 00
5. ACK de 0x60
6. plusieurs secondes après seulement: D0Exit / WdfPowerDeviceD3.

Donc Windows ne laisse pas le ST411 actif quand l'usage biométrique s'arrête.
Le MCU est déjà quiescé avant une transition D3/S3.

Linux rel61-rel65 fermait SPI/IRQ sans envoyer ce SLEEP.

Le vieux rel57 avait codé un sleep analogue, mais son test humain n'avait
jamais réellement exécuté le marqueur SLEEP. Il n'avait donc ni validé ni
réfuté cette hypothèse.

## rel66: changement minimal

Inchangés:
- GQ-SIGFM, threshold 7
- templates/enrollments
- reset GPIO 300/600 ms
- cold prepare
- TLS retry/recovery
- fresh background/FDT
- rel59 pacing
- rel60 pose rearm
- rel65 KDE/PAM lifecycle.

Ajouts:
- gxfp_build_sleep produit exactement:
  60 03 00 01 00 46
  soit cmd 0x60 + payload 01 00 + checksum.
- Healthy Close:
  send SLEEP, exiger ACK; stash warm uniquement si ACK OK.
  Si ACK échoue, warm context est abandonné.
- No-S3 warm Open:
  si sensor_sleeping, WakeupMCU raw 0f 00 00 0e,
  puis gx_warm_validate / WARM_REBASE.
- True S3:
  comportement rel65 conservé: host warm abandonné, GPIO reset,
  full cold prepare. Aucun ancien background/TLS ne traverse le S3.
- Pas de SLEEP ajouté au callback gx_dev_suspend pour rel66.
  Le cas idle/closed observé est testé en premier.

## Validation software et live

Package:
libfprint-goodix51a0 1.94.100.goodix51a0-66

Final package SHA256:
1707d74452eb6e02ffaab1a8eed6550271f9a10b24148258e127d87aa53049bb

Autres paquets:
- kscreenlocker 6.7.5-1.5
- plasma-login-manager 6.7.5-3.9
- fprintd 1.94.5-2.1 --no-timeout

Boot-prewarm:
- présent
- disabled
- inactive
- aucun graphical.target auto-link.

Enrollments intacts:
- right-index
- left-index
- right-middle.

Validation:
- research suite PASS
- target exact sleep bytes PASS
- lifecycle/native resume PASS
- warm sleep/wake handoff PASS
- GQ-SIGFM evaluator PASS
- dual auth PASS
- boot binding PASS
- git diff --check PASS
- full Meson/Ninja PASS
- artifact gates PASS
- release biometric dump absent.

Live cycle #1:
fprintd restart -> cold prewarm -> Close.
21:50:20.451702:
GXFP51A0 REL66_TRACE Windows deactivate SLEEP 0x60/01 00 acknowledged

Live cycle #2, no restart / no S3:
21:50:36.987233 WakeupMCU raw SPI write complete
21:50:38.726442 WARM_REBASE background+FDT in 1739 ms
21:50:38.730896 REL66_TRACE SLEEP 0x60/01 00 acknowledged

Cycle réel prouvé:
SLEEP ACK -> WakeupMCU -> WARM_REBASE -> SLEEP ACK.

Après validation, aucun fd n'est ouvert sur /dev/spidev1.0.
Le capteur est fermé et a reçu son dernier SLEEP ACK.

## Prochain gate humain

Faire UN deep S3 manuel maintenant.
Ne pas reboot, ne pas ré-enrôler.

Au retour lire les logs avant tout code:
- dernier REL66_TRACE SLEEP avant suspend
- PM suspend entry/exit
- premier cold Open post-resume
- TLS
- fresh background/FDT
- READY
- DETECTED_HOLD
- scores.

Priorité: retrouver une vraie image >=7, idéalement 9-20+.
N'optimiser la latence qu'après fiabilité.
