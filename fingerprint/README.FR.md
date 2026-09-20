# Goodix GXFP51A0 / GF3658 ST411 sous Linux

Pilote libfprint natif expérimental pour le Goodix SPI GXFP51A0 présent dans la
famille Huawei MateBook 13 2021.

> English: [README.md](README.md)

## État — 20 septembre 2026

Cible matériellement validée :

- ACPI HID : `GXFP51A0`
- Goodix GF3658 / ST411, chip ID `0x2504`
- firmware validé : `GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`, 1 MHz
- GPIO48 readiness/IRQ et GPIO264 reset MCU
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- image active 80×64
- base libfprint : `v1.94.100`

Chemin de production :

```text
GXFP51A0 → libfprint → fprintd → KDE / GNOME / PAM / CLI
```

Aucune UI spécifique, réécriture PAM, modification de firmware ou runtime
Goodix propriétaire n'est nécessaire.

### Ce qui est validé

Sur l'unité de référence GXFP51A0/GF3658/ST411 :

- l'enrollment KDE/fprintd standard termine avec **20 poses acceptées** ;
- le matching FAST-9 + BRIEF-256 + RANSAC rigide est entièrement exécuté côté
  hôte en C ;
- le seuil d'acceptation reste fixe à **7 inliers RANSAC** ;
- un succès est renvoyé immédiatement ;
- un no-match peut demander jusqu'à **3 poses complètes et indépendantes**
  avant le refus terminal. Le nombre d'essais est fixe et ne dépend jamais de
  la proximité du score avec le seuil ;
- `identify` reste mono-capture ;
- les désynchronisations target/TLS disposent d'une récupération bornée avec
  timing d'initialisation appris et persisté ;
- la recette de capture conserve son gap nominal validé de 30 ms, séparé du
  timing plus conservateur d'initialisation ;
- le build release ne contient aucun writer de dump biométrique.

Ces 3 poses compensent les variations de placement d'un très petit capteur
partiel sans baisser le seuil biométrique ni additionner des scores faibles.

## Installation

### Arch / CachyOS

Depuis la racine du dépôt :

```bash
./fingerprint/install-arch.sh
```

L'installateur vérifie la présence du `GXFP51A0`, compile le patch libfprint,
installe `libfprint-goodix51a0` et `fprintd`, ajoute uniquement l'accès
gpiochip nécessaire, recharge udev puis redémarre fprintd.

Il ne modifie **ni PAM, ni KDE, ni GNOME**.

Ensuite utilise les réglages standards du bureau ou :

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
fprintd-list "$USER"
```

Le pilote demande 20 poses. Déplace légèrement le doigt entre les poses afin de
couvrir plusieurs zones du doigt.

### Anciens templates de développement

Le format courant est template driver v4 / SIGFM v3. Une personne venant d'une
ancienne révision de développement de ce dépôt peut devoir supprimer une fois
ses anciens templates puis ré-enroller :

```bash
fprintd-delete "$USER"
```

Une installation neuve n'a pas cette étape.

### Debian / Ubuntu / Fedora / autres Linux

L'installateur source portable reconstruit exactement le candidat libfprint
épinglé et garde le remplacement isolé sous `/usr/local` :

```bash
./fingerprint/install-linux.sh
```

Il sait installer les dépendances sur les familles Arch/CachyOS,
Debian/Ubuntu, Fedora et openSUSE. Sur Arch/CachyOS il délègue au paquet pacman
natif. Sur les autres familles supportées il relie uniquement fprintd au
libfprint local via un drop-in systemd et conserve un manifeste de rollback.

Rollback :

```bash
sudo /var/lib/gxfp51a0-local-install/uninstall.sh
```

`./fingerprint/install-linux.sh --build-only` permet de vérifier la compilation
sans rien installer.

## Matcher

Le chemin de production utilise :

- soustraction adaptative du fond ;
- normalisation percentile + unsharp ;
- FAST-9 multi-échelle à deux niveaux ;
- descripteurs BRIEF-256 non orientés ;
- cross-check mutuel + ratio test ;
- RANSAC rigide 200 itérations, tolérance 2 px ;
- raffinement rigide par moindres carrés ;
- meilleur score parmi 20 vues d'enrollment.

Le pilote ne baisse pas le seuil après un échec, n'additionne pas plusieurs
scores faibles et n'apprend pas depuis des vérifications échouées.

Le score pixel/ZNCC reste disponible uniquement avec le flag de recherche
explicite `GXFP_MATCH_DIAGNOSTICS`. Il ne participe pas à la décision
d'authentification.

## Validation contributeur

```bash
make -C fingerprint verify
```

La suite valide les tests déterministes/sécurité, le manifeste source, compile
libfprint `v1.94.100` et contrôle le binaire final.

Gates principales :

```text
SOURCE_MANIFEST=PASS
LIBFPRINT_BUILD=PASS
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_FASTBRIEF_RANSAC_IN_LIBRARY=YES
GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES
RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT
SOFTWARE_BUILD_READY=YES
ACTIVE_SENSOR_IO=NONE
GPIO_WRITES=NONE
MMIO_WRITES=NONE
FIRMWARE_ACTIONS=NONE
```

Les diagnostics locaux de maintenance sont optionnels ; un utilisateur normal
n'en a pas besoin.

## Sécurité et confidentialité

Ne jamais publier :

- captures ou templates d'empreinte ;
- PMK/PSK/clés ou fixtures propres à une unité ;
- binaires/firmwares Goodix ou Huawei propriétaires ;
- numéros de série ou identifiants privés.

Le cache PMK et le timing appris sont des états runtime sous
`/var/lib/fprint/` et ne sont ni packagés ni versionnés.

Le template fprintd v4 local est une donnée biométrique et doit être protégé
comme tel.

Le pilote ne flashe pas le firmware du capteur.

## Périmètre

La cible prouvée est la combinaison exacte GXFP51A0 / GF3658 / ST411 ci-dessus.
Un autre appareil avec le même ACPI HID peut néanmoins avoir un câblage GPIO,
un firmware ou une intégration carte mère différents.

Ce logiciel biométrique reste reverse-engineered et expérimental. La validation
est aujourd'hui la plus forte sur l'unité de référence et sur des contrôles
négatifs inter-doigts du même utilisateur ; elle ne remplace pas une
certification biométrique sur un grand corpus inter-personnes. Ne considère pas
l'empreinte seule comme un facteur de sécurité haute assurance.

Voir [intégration desktop](docs/native-desktop-integration.md),
[provenance](PROVENANCE.md), [source](driver/goodix51a0/) et
[research log](docs/research-log.md) et [handoff actuel](HANDOFF_CURRENT.md).

Le sous-arbre de production du pilote est `LGPL-2.1-or-later`.
