# Goodix GXFP51A0 / GF3658 Milan sous Linux

> Projet expérimental de rétro-ingénierie. Le candidat public compile dans
> libfprint, mais le capteur d'empreinte **ne fonctionne pas encore sous Linux**.
> Aucun flash firmware ni flux constructeur non revu n'est autorisé.

> English: [README.md](README.md)

## État actuel — 8 septembre 2026

Le projet dispose maintenant d'un **candidat GXFP51A0 reproductible pour
libfprint v1.94.100**. L'intégration logicielle n'est plus le blocage.

```text
build/intégration libfprint          PASS
régression first-contact             PASS
tests recherche/sécurité             PASS
modèle first-contact Windows         reconstruit
modèle first-contact Linux           aligné
soumissions contrôleur SPI           prouvées
premier ACK capteur                  NON OBSERVÉ
A8 / EVK                             NON OBSERVÉ
capture/enroll/verify                NON ATTEINT
fprintd/PAM                          NON ATTEINT
```

Le point de reprise canonique est [HANDOFF_CURRENT.md](HANDOFF_CURRENT.md).
Le checkpoint détaillé de rétro-ingénierie reste dans
[FINAL_HANDOFF_2026-09-08.md](FINAL_HANDOFF_2026-09-08.md).

## Validation contributeur en une commande

Après clonage :

```bash
make -C fingerprint verify
```

Cette commande :

1. vérifie la syntaxe Bash des scripts publics ;
2. lance la régression GXFP51A0 first-contact ;
3. lance toute la suite de tests/sécurité software-only ;
4. vérifie le manifest SHA-256 du candidat ;
5. crée un venv isolé pour les outils de build ;
6. fixe Meson 1.12.0 et Ninja 1.13.2 ;
7. clone exactement libfprint v1.94.100 ;
8. applique le patch d'intégration revu ;
9. injecte uniquement les sources GXFP51A0 revues ;
10. compile et vérifie objet/type/chaîne du driver.

**Aucun transfert SPI capteur, aucune écriture GPIO/MMIO et aucune action
firmware ne sont effectués.**

Autres commandes :

```bash
make -C fingerprint build
make -C fingerprint research
make -C fingerprint passive-audit
```

Voir [scripts/README.md](scripts/README.md).

## Faits cible confirmés

- ACPI HID `GXFP51A0`
- Goodix GF3658 / famille Milan
- parent actif SPI1 ; enfant fingerprint SPI2 désactivé
- SPI1 CS0, mode 0, 8 bits, 10 MHz, four-wire
- GPIO48 : readiness/IRQ level ActiveHigh
- GPIO264 : HIGH 10 ms -> LOW 100 ms -> LOW final
- écriture Milan : 4 octets externes -> environ 2 ms -> reste
- DriverState Install : `(9,3)` / `0x96`
- checksum NOP : `0xA5`
- GetEvkVersion : NOP -> 5 ms -> A8, une retransmission A8 identique après
  le premier timeout ACK
- vecteur ST411 exact : SP `0x20020000`, Reset_Handler `0x08033198`,
  base `0x08020000`

## Frontière Linux silencieuse exacte

Le common-init fidèle à Windows a déjà été exécuté :

```text
transferts SPI            34
octets TX                 180
attentes IRQ              12
événements IRQ Goodix     0
octets RX retenus         180
octets RX à 0xFF          180
complétions contrôleur    prouvées
erreurs contrôleur        aucune
GPIO264 final             LOW
```

Ne pas rejouer cette expérience active inchangée.

## Hypothèses fermées

- DMA contre PIO déterministe
- runtime PM comme cause principale
- mapping IRQ Linux
- polling GPIO userspace contre attente IRQ native
- timing split mode-5 / frontière SPB first-contact
- permutations de reset déjà revues
- conservation MISO same-wire
- hypothèse GPIO112 / GPP_D16
- switch fingerprint LPSS caché
- action DeviceInit intermédiaire comme I/O capteur manquante
- hypothèse PSK GXFP51A0 fixe de 48 octets
- replay inchangé du common-init

## Encore non résolu

- premier ACK réel sous Linux
- première réponse A8/EVK
- réalité électrique CS/SCLK/MOSI/MISO versus simple complétion contrôleur
- comportement physique GPIO48
- config exacte GXFP51A0 / `Milan_DlCfg`
- sémantique/longueur DSM/TLS/PSK exacte
- capture image
- enroll / verify
- fprintd / PAM / desktop

## Frontière suivante

La machine de développement principale ne possède actuellement **pas de boot
Windows**. La comparaison WDF/SpbCx ne peut donc pas être capturée localement.

Sous Linux :

```bash
make -C fingerprint passive-audit
```

Le script collecte uniquement des informations ACPI/SPI/PCI/runtime-PM/IRQ/
pinctrl en lecture seule.

Un contributeur avec un GXFP51A0 fonctionnel sous Windows peut utiliser
[scripts/windows/gxfp51a0_windows_observability.ps1](scripts/windows/gxfp51a0_windows_observability.ps1).

Si ces observations software ne discriminent pas le problème, la preuve la plus
utile devient une comparaison avec analyseur logique/oscilloscope de :

```text
CS / SCLK / MOSI / MISO / GPIO48
```

## Carte du dépôt

- [Handoff actuel](HANDOFF_CURRENT.md)
- [Handoff détaillé 2026-09-08](FINAL_HANDOFF_2026-09-08.md)
- [Candidat driver](driver/goodix51a0/)
- [Scripts contributeur](scripts/)
- [Contrat de validation](docs/contributor-validation-2026-09-08.md)
- [Frontière technique](docs/current-boundary-2026-09-08.md)
- [Clôture DeviceInit/BESD/SPB](docs/deviceinit-besd-spb-closure-2026-09-08.md)
- [Différentiel Windows .36 -> .40](docs/windows-14136-14140-differential-2026-09-08.md)
- [Matériel](docs/hardware.md)
- [Protocole](docs/protocol.md)
- [Journal](docs/research-log.md)
- [Sécurité](docs/safety.md)
- [Implémentation recherche](research/README.md)
- [Contribuer](CONTRIBUTING.md)

## Objectif

```text
premier ACK
-> A8/EVK
-> config cible exacte
-> DSM/TLS/PSK exact
-> capture image
-> enroll
-> verify
-> fprintd
-> PAM/desktop
```

## Sécurité du dépôt public

Ne jamais publier CAB/DLL/firmware propriétaires, payload `_DSM` brut, PSK,
clés dérivées, numéros de série, chemins/utilisateurs locaux, IP privées ou
inventaire matériel personnel sans rapport.

Aucun flash/erase firmware, écriture MMIO/pinmux spéculative, écriture GPIO112
ou commande wake générique empruntée n'est autorisé sans nouvelle preuve
exact-target.

Voir [docs/safety.md](docs/safety.md).
