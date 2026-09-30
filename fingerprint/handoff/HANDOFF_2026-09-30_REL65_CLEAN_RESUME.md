# HANDOFF — rel65 clean-resume architecture

Date: 2026-09-30
Machine: Pegasus uniquement
Branche: `fingerprint-rel65-clean-resume`
Base driver: commit rel61 humain-validé `0e8a50a`

## Pourquoi rel62–64 sont abandonnés

Rel61 deep-S3 humain a réussi:
- resume hook: 01:26:39.755
- READY: 01:27:01.260
- first true DETECTED: 01:27:01.744
- première vraie image: **20/7**
- unlock réussi.

Rel62:
- optimisation fast-resume / TLS borné / DriverState once-per-daemon
- S3 FAIL; READY ~17.37 s; scores répétés 3/7.

Rel63:
- epoch BOOTTIME-MONOTONIC conservée
- transport/TLS amélioré
- S3 FAIL; READY ~8.48 s; scores 3–4/7.

Rel64:
- reset+A8 pré-TLS confirmé par S3_TRACE
- DriverState Install rejoué après vrai S3
- S3 FAIL malgré séquence correctement exécutée
- dernier cycle: suspend exit 20:36:03.818, READY ~20:36:10.427,
  puis vraies poses 3/3/3, 4/4/3, 2/3.
- hypothèse "reset+A8 + DriverState suffit à restaurer l'imagerie" réfutée.

Conclusion: le défaut n'est ni PAM, ni matcher, ni seuil, ni simple TLS.
La régression vient du fait que rel62–64 tentent encore de reconstruire/continuer
une vie de device/action autour de S3 au lieu de créer une vraie frontière
Release/Close/Open.

## Recherche externe septembre 2026

### berkekbgz/libfprint-goodix-spi — GDIX51C0 SPI
Révision inspectée: `010a665f54089a1632b1ab7be588b316ace934e2`.

Points pertinents:
- lifecycle hardware suspend/resume annoncé validé;
- cold-open marque ImageBase/FDT comme à rafraîchir;
- suspend marque session désynchronisée/cold boundary;
- suspend se termine avec `fpi_device_suspend_complete(dev, NULL)`;
- le pilote NE cancel PAS l'action pendant que libfprint est encore suspendu;
- resume appelle d'abord `fpi_device_resume_complete(dev,NULL)`;
- seulement ensuite l'ancien cancellable est annulé;
- fprintd peut alors Release/Close proprement et un nouvel Open refait une vraie activation;
- cold hardware handle refait un T0/ImageBase finger-off protégé.

### AndyHazz/goodix53x5-libfprint
Révision inspectée: `309d4c6999a1cdce172c1ca1ee81387b5078d38f`.

Points pertinents:
- tout sleep marque `needs_reinit = TRUE`;
- le prochain chemin exécute une full open-time reinitialization;
- la documentation source dit explicitement que sleep peut invalider claim + session TLS
  et que la séquence complète d'initialisation doit être rejouée.

### Logs Windows Goodix
Les traces D0Entry montrent reprise depuis D3 puis retour dans le flux startup/init.
Ce n'est pas une preuve ST411 byte-for-byte, mais cela va dans le même sens:
une transition de puissance est une frontière d'initialisation, pas un warm handoff.

## Architecture rel65

Rel65 repart du driver rel61 fonctionnel et NE cherry-pick PAS les optimisations
driver rel62–64.

Conservé exactement de rel61:
- threshold GQ-SIGFM = 7;
- template v4 / enrollments existants;
- warm TTL 5 min;
- reset GPIO 300/600 ms;
- DriverState Install sur cold prepare;
- jusqu'à 5 essais TLS;
- reset + Stage2E/A8 entre échecs TLS;
- fresh background/FDT;
- rel59 retry-assisted pacing;
- rel60 WakeupMCU entre poses;
- accepted GET_IMAGE timeout => rebuild, jamais blind replay.

Changement lifecycle:
1. `gx_dev_suspend()`
   - marque `force_cold_reset`;
   - invalide warm/production/FDT;
   - conserve une référence au cancellable de l'action;
   - appelle `fpi_device_suspend_complete(dev,NULL)`;
   - ne cancel rien pendant l'état suspended.

2. `gx_dev_resume()`
   - appelle EN PREMIER `fpi_device_resume_complete(dev,NULL)`;
   - puis cancel l'ancienne action;
   - fprintd peut Release/Close;
   - le prochain PAM Claim obtient un vrai `gx_dev_open()`;
   - cold prepare complet rel61 => TLS + fresh background + FDT.

3. Fallback BOOTTIME-MONOTONIC
   - si un S3 échappe au callback suspend, `gx_active_sleep_recovery()`
     ne saute plus vers GX_ST_SESSION;
   - il termine l'action stale avec G_IO_ERROR_CANCELLED;
   - même résultat: Close/Open frais.

4. Epoch S3
   - process-local;
   - initialisée à la création du device;
   - n'est plus effacée par `gx_warm_abandon()`;
   - aucun fichier persistant.

5. Boot-prewarm
   - unité/helper restent installés;
   - aucun symlink auto-start dans graphical.target.wants;
   - reste explicitement disabled tant que le S3 n'est pas validé.

## KDE / PAM conservés

La branche rel65 réimporte uniquement les améliorations déjà live/validées:
- kscreenlocker 6.7.5-1.5
  - restart fingerprint-only après resume;
  - reset unavailable;
  - stale fail-delay hardware indisponible ignoré au resume;
- plasma-login-manager 6.7.5-3.9
  - fingerprint/password parallèles;
  - pam_fprintd max-tries=1 timeout=30.

Aucun downgrade vers les fichiers rel61 1.4 / 3.8.

## Validation software rel65

PASS:
- `make -C fingerprint/research test`
- lifecycle recovery
- native resume recovery
- stale-background bootstrap absent
- boot-prewarm packaging
- accepted GET_IMAGE timeout recovery
- TLS safety
- same-press
- retry pacing
- GQ-SIGFM evaluator
- dual auth
- KScreenLocker resume PAM
- `python3 tests/test-goodix51a0-boot-binding.py`
- `git diff --check`
- full Meson/Ninja libfprint v1.94.100
- source manifest
- artifact gates
- release biometric dump hook absent

Package:
`libfprint-goodix51a0-1.94.100.goodix51a0-65-x86_64.pkg.tar.zst`

SHA256:
`7a6fef3eac19700f0e84e9885c0a7159647f2b064cce32a9b0c0a7557e67e909`

Package contents:
- fprintd auto-linked before graphical login;
- boot-prewarm unit/helper present mais non auto-linked;
- aucun system-sleep hook;
- aucun warm keepalive.

## Gate humain suivant

1. installer rel65;
2. pas de ré-enrôlement;
3. normal lock rapide si souhaité;
4. un deep S3 humain;
5. après reprise, logs attendus:
   - `S3_CLEAN suspend: parked action`
   - PM suspend exit
   - `S3_CLEAN resume complete; cancelling parked action`
   - fprintd Release/Close
   - nouveau Claim/Open
   - cold init complet
   - fresh background/FDT
   - READY
   - DETECTED_HOLD
   - score.

Succès prioritaire = retour d'une vraie image >=7 (idéalement profils rel61 9–20+).
Ensuite seulement, optimiser la latence sans raccourcir la frontière cold qui a
rétabli la fiabilité.
