# Goodix GXFP51A0 / GF3658 Milan sous Linux

Pilote libfprint natif expérimental pour le Goodix SPI GXFP51A0 présent dans la
famille Huawei MateBook 13 2021.

> English: [README.md](README.md)

## État — 19 septembre 2026

Cible validée matériellement :

- ACPI HID : `GXFP51A0`
- Goodix GF3658 / Milan, ST411
- firmware : `GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`, 1 MHz validé
- GPIO48 readiness/IRQ, GPIO264 reset MCU
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- capture/matching 80x64 côté hôte via libfprint

Chemin de production :

```text
GXFP51A0 → libfprint → fprintd → KDE / GNOME / PAM / CLI
```

Il n’existe aucune interface graphique spécifique au capteur et aucun patch de
protocole KDE/GNOME.

Validé sur la machine de référence :

- enrollment fprintd standard terminé ;
- index droit reconnu ;
- deux doigts non enregistrés différents refusés ;
- le driver demande 15 acquisitions biométriques d’enrollment ; fprintd expose
  16 étapes au frontend quand `identify` est disponible car il ajoute une étape
  interne liée à l’identification ; il expose aussi `press`, `finger-needed` et
  `finger-present` ;
- le candidat actuel implémente `identify` libfprint standard pour le
  multi-doigts et `VerifyStart("any")` ;
- verify/identify renvoie la décision biométrique avant le nettoyage lié au
  relâchement du doigt afin de ne pas ralentir le login manager.

Un timeout TLS/image transitoire pendant le préchauffage n’annule plus
`open` : l’action biométrique dispose d’un retry de session complet et borné.

## Installation Arch / CachyOS

Depuis la racine du dépôt :

```bash
./fingerprint/install-arch.sh
```

L’installateur compile localement, installe le paquet et fprintd, recharge udev
et redémarre fprintd. Il ne modifie **ni PAM, ni KDE, ni GNOME**.

Outils Linux standards après installation :

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
fprintd-list "$USER"
```

La politique d’authentification du bureau reste celle de la distribution.

## Diagnostic guidé de vérification

Pour les tests interactifs, utilise le harness local plutôt que des consignes
synchronisées par le chat :

```bash
./fingerprint/tools/gxfp51a0-verify-diagnostic.py
```

Il attend les états fprintd standards `finger-needed` / `finger-present`,
affiche localement un compte à rebours 3-2-1 puis les ordres explicites
`POSE`, `GARDE` et `RETIRE`. Le nom du doigt physique est affiché en MAJUSCULES.
Les logs driver ne servent qu’aux détails optionnels de score/timing ; le
guidage dépend uniquement de l’état D-Bus standard de fprintd.

Pour comparer plusieurs doigts contre un template enregistré :

```bash
./fingerprint/tools/gxfp51a0-compare-fingers.py
```

La séquence par défaut effectue trois scans `INDEX DROIT` puis trois contrôles
négatifs : `INDEX GAUCHE`, `MAJEUR GAUCHE`, `MAJEUR DROIT`. Un rapport JSON
agrégé contient scores, seuils, verdicts et temps de capture.

## Validation contributeur

```bash
make -C fingerprint verify
```

Cette commande exécute les tests déterministes/sécurité, vérifie le manifeste,
clone exactement libfprint `v1.94.100`, compile le driver et contrôle le
binaire final.

Gates release :

```text
SOURCE_MANIFEST=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES
RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT
SOFTWARE_BUILD_READY=YES
```

La validation software n’effectue aucun transfert capteur actif, aucune écriture
GPIO/MMIO et aucune action firmware.

## Sécurité et confidentialité

Le build release ne compile pas le writer de dump biométrique. Les diagnostics
capables de traiter des captures sont réservés au build développeur.

Ne jamais publier :

- captures ou templates biométriques ;
- PMK/PSK/clés ou fixtures privées par unité ;
- binaires/firmwares Goodix ou Huawei propriétaires ;
- numéros de série ou identifiants privés de machine.

Le pilote ne flashe pas le firmware du capteur.

## Périmètre

La cible prouvée est la combinaison GXFP51A0/ST411/firmware ci-dessus. Un autre
portable avec le même ACPI HID peut avoir un câblage GPIO ou un firmware
différent et doit être validé avant d’être déclaré supporté.

Voir [intégration desktop native](docs/native-desktop-integration.md),
[provenance](PROVENANCE.md), [source driver](driver/goodix51a0/) et
[handoff actuel](HANDOFF_CURRENT.md).

Le sous-arbre source du driver est `LGPL-2.1-or-later`. Les documents de
recherche historiques et le reste du dépôt peuvent avoir une licence distincte.
