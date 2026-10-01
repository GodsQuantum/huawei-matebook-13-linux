# PROMPT À COPIER-COLLER — installer rel72 et terminer le gate S3 GXFP51A0

Tu reprends le chantier **Huawei MateBook 13 2021 / Goodix GXFP51A0 / GF3658 ST411**
sur **Pegasus uniquement**.

## 1. AVANT TOUT

Utilise Remote Desktop Commander sur Pegasus:
device id 8a6eeb21-0158-4e6d-b3ea-91d580f8a223

Lis EN ENTIER:
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/HANDOFF_REL72_FULL_2026-10-01.md`

Puis lis:
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/handoff/HANDOFF_2026-10-01_REL72_S3_HARDWARE_PARK.md`

Ne redécouvre pas l’enquête. Le handoff contient l’état, les preuves, les échecs,
les recherches GitHub, les règles de sécurité et l’arbre de décision.

## 2. CONTRAINTES ABSOLUES

- Pegasus uniquement.
- Aucun reboot automatique.
- Aucun suspend/S3 automatique.
- Aucun lock/unlock automatique.
- Aucun poweroff.
- Les tests physiques sont déclenchés par Arezki.
- Ne jamais ré-enrôler.
- Threshold SIGFM = 7, ne jamais le baisser.
- Ne jamais toucher GPIO112/GPP_D16.
- Ne jamais exposer PMK/PSK/templates/captures biométriques/serials.
- Pas de heartbeat ni keepalive périodique.
- Pas de fichier de timing persistant.
- Pas de hook system-sleep externe pour le fingerprint.
- Password et fingerprint doivent rester parallèles.
- Si une action physique est nécessaire, arrête-toi et indique exactement ce que
  l’utilisateur doit faire; ne la déclenche jamais toi-même.

## 3. ÉTAT EXACT DE DÉPART

Git:
branch fingerprint-rel72-s3-hardware-park
HEAD 547b75b — fix(fingerprint): rel72 hardware park before S3
origin synchronisé
worktree propre au moment du handoff

Live:
- libfprint-goodix51a0 1.94.100.goodix51a0-71
- fprintd 1.94.5-2.1
- 3 enrollments intact
- rel72 NOT installed
- aucun reboot effectué

Rel72 packages were built previously but their artifact files were cleaned.
Recorded SHA256:
fprintd-1.94.5-72-x86_64.pkg.tar.zst
9f45604f88d28aaf014ff85940f783411a83d8c8ed635e6ba1b19ab6ed4321e0

libfprint-goodix51a0-1.94.100.goodix51a0-72-x86_64.pkg.tar.zst
7adc8c66389a76c87c35960ede04f0adaf1108745d7ac1c0714554cea3fc5c01

If artifacts are absent, rebuild them from the checked-in source/PKGBUILD and
verify the resulting SHA256 before installing.

## 4. WHAT REL72 ACTUALLY CHANGES

Rel72 deliberately preserves the proven rel60/61 biometric driver.

Only the true S3 lifecycle changes.

Driver:
- sends Windows-compatible SLEEP command 0x60 payload 01 00 with ACK
- ONLY inside the real libfprint suspend callback
- closes stale transport/TLS state
- next Claim/Open is a fresh cold boundary
- normal gx_dev_close does NOT send 0x60

fprintd 1.94.5-72:
- listens to PrepareForSleep
- if exact driver is goodix51a0 and device is closed, opens it temporarily
- this lets libfprint reach its suspend callback while SPI/TLS is alive
- after resume, closes the temporary sleep-opened device
- next PAM Claim/Open rebuilds cleanly


[executed on device: Pegasus (8a6eeb21-0158-4e6d-b3ea-91d580f8a223)]