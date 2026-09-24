[Reading 208 lines from start (total: 208 lines, 0 remaining)]

# Goodix GXFP51A0 / GF3658 ST411 sous Linux

Pilote libfprint natif expérimental pour le Goodix SPI GXFP51A0 présent dans la
famille Huawei MateBook 13 2021.

> English: [README.md](README.md) · 简体中文: [README.ZH-CN.md](README.ZH-CN.md)

## État — 24 septembre 2026

Cible matériellement validée :

- ACPI HID : `GXFP51A0`
- Goodix GF3658 / ST411, chip ID `0x2504`
- firmware validé : `GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`, 1 MHz
- GPIO48 readiness/IRQ et GPIO264 reset MCU actif HIGH
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- image active 80×64
- base libfprint épinglée : `v1.94.100`

Chemin de production :

```text
GXFP51A0 → libfprint → fprintd → PAM du bureau / CLI
```

### Base validée en conditions réelles : rel40

Un vrai login graphique après cold boot sur le MateBook 13 2021 de référence a
réussi avec les enrollments existants. Plasma Login Manager a utilisé
`Identify` : première pose `2/3/3`; sur la pose suivante, la première image a
été rejetée par le quality gate et la **deuxième image de la même pose physique
a obtenu 7/7**, ouvrant la session.

rel40 valide donc ensemble :

- le `WakeupMCU` Windows exact : SPI brut `0f 00 00 0e` + 5 ms ;
- la revalidation hardware du contexte warm et `WARM_REBASE` ;
- `Verify` et `Identify` multi-empreintes ;
- jusqu'à 3 images indépendantes sur une même pose via `RetryCaptureIMG` ;
- seuil fixe **7**, sans addition ni fusion de scores ;
- jusqu'à 3 poses physiques avant rejet terminal ;
- enrollment 20 vues et compatibilité template-v4/SIGFM-v3 ;
- récupération transport bornée, prewarm boot et prewarm après deep sleep ;
- aucun keepalive Claim périodique ;
- aucun writer de dump biométrique dans les builds release.

### Candidat rel42 : adaptation rapide en RAM + installation Linux portable

rel42 conserve intégralement le chemin biométrique rel40 validé. Il supprime les
fichiers de timing persistants rel24–rel40, car un échec lifecycle/prewarm
pouvait faire grimper définitivement le pacing au fil des boots. Après une
frontière lifecycle fraîche, le timing repart toujours à 100 % et ne s'adapte
qu'en RAM :

- un échec lifecycle/prewarm ne modifie jamais le pacing capture ;
- 3 captures réussies consécutives ayant nécessité le retry GET_IMAGE montent
  le pacing d'un pas de 50 points pour le daemon courant ;
- 8 captures propres redescendent d'un pas vers la valeur nominale ;
- une vraie désynchronisation biométrique peut augmenter le pacing de session
  et déclenche la récupération complète déjà validée ;
- le timing protocole/TLS peut aussi s'assouplir en session, sans persistance.

La suite logicielle rel42 et le build libfprint reproductible passent. Le gate build/ABI portable passe aussi dans des conteneurs propres Debian stable, Fedora current, openSUSE Tumbleweed, Arch Linux et Alpine edge/musl. rel42 ne remplace pas encore la validation humaine rel40 tant qu'il n'a pas reçu son propre test cold boot.

## Installation

Depuis un checkout du dépôt :

```bash
./fingerprint/install-linux.sh
```

L'installateur détecte Arch/CachyOS, Debian/Ubuntu, Fedora/RHEL, openSUSE et
Alpine. Arch/CachyOS délègue au paquet pacman natif. Avec systemd, le libfprint
local sous `/usr/local` n'est visible **que par fprintd** via un
`LD_LIBRARY_PATH` de service. Sans systemd, la même isolation passe par un
wrapper d'activation D-Bus prioritaire sous `/etc/dbus-1/system-services` :
aucun `ld.so.conf` global n'est modifié. Le `libdir` Meson réel est détecté
dynamiquement (multiarch Debian, `lib64`, `lib`) et l'ABI du fprintd de la
distribution est validée contre le candidat stagé avant toute modification
système.

Modes utiles :

```bash
./fingerprint/install-linux.sh --build-only
./fingerprint/install-linux.sh --no-install-deps
./fingerprint/install-linux.sh --no-desktop-integration
```

Rollback :

```bash
sudo /var/lib/gxfp51a0-local-install/uninstall.sh
```

Arch/CachyOS peut appeler directement :

```bash
./fingerprint/install-arch.sh
```

L'installation ne supprime jamais les enrollments ni le cache PMK validé.
L'upgrade rel42 ne retire que les anciens entiers de timing non secrets.

Pour Plasma Login Manager 6.7.5, le dépôt contient aussi le paquet de
compatibilité validé qui sépare l'authentification fingerprint et mot de passe :
saisir le mot de passe n'attend plus l'expiration d'une tentative empreinte.
Les autres bureaux conservent leur intégration fprintd/PAM native.

### Validation matcher optionnelle et respectueuse des données biométriques

Benjamin Allègre (Sigfrodr) publie tools/eval/fp_eval.py dans Sigfrodr/libfprint-goodixtls : un évaluateur local commun à la famille Milan-SPI avec séparation enrol/probe disjointe. Il ne sort que des agrégats EER, FAR/FRR, distributions de scores et d-prime ; captures et templates restent sur la machine du testeur. C'est utile pour une validation multi-utilisateur défendable en upstream de SIGFM face à des références neutres descriptor/géométriques et NBIS optionnel. Ce n'est pas une dépendance runtime et les builds release restent incapables de dumper les captures biométriques.

## Historique technique

### rel24-rc1 : candidat de compatibilité transport lent

Le premier retour confirmé sur un MateBook 13 2020 ST411/14115 montre que rel23 peut authentifier correctement cette révision tout en subissant parfois un état transport dégradé avec des retries GET_IMAGE/FDT très lents. rel24-rc1 conserve le gap capture validé de 30 ms par défaut, mais apprend séparément un pacing capture de 100 à 300 % uniquement après un échec GET_IMAGE complet. Cette valeur est indépendante du timing TLS/init existant et n'est persistée qu'après une capture de doigt complète réussie. Les deux signatures `no ACK/TLS` et `ACK mais aucune image TLS après retry` déclenchent une récupération MCU/session complète ; un échec transport ne consomme jamais une tentative biométrique.

Le prewarm d'énumération devient également volontairement court : une seule tentative externe, au plus deux essais TLS avec le PMK en cache et aucun fallback fresh-staging. Si cette optimisation échoue, fprintd devient quand même disponible et la vraie ouverture biométrique conserve sa récupération bornée complète. rel24-rc1 ne change ni template v4, ni SIGFM v3, ni le seuil 7, ni les 20 vues d'enrollment, ni les trois presses indépendantes maximum.


### Arch / CachyOS

Depuis la racine du dépôt :

```bash
./fingerprint/install-arch.sh
```

L'installateur vérifie la présence du `GXFP51A0`, compile le patch libfprint, installe `libfprint-goodix51a0` et `fprintd`, ajoute uniquement l'accès gpiochip nécessaire et installe les prewarm boot/resume. Sur Plasma 6.7.5 uniquement, il applique aussi les intégrations KDE/Plasma Login Manager package-managed, idempotentes et réversibles ; les autres bureaux gardent leur intégration fprintd/PAM native.

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

### Debian / Ubuntu / Fedora / openSUSE / Alpine / autres Linux

L'installateur source portable reconstruit exactement le candidat libfprint
épinglé et garde le remplacement isolé sous `/usr/local` :

```bash
./fingerprint/install-linux.sh
```

Il sait installer les dépendances sur Arch/CachyOS, Debian/Ubuntu, Fedora,
openSUSE et Alpine. Arch/CachyOS délègue au paquet pacman natif. Ailleurs, le
candidat est stagé, l'ABI du fprintd de la distribution est vérifiée, puis le
libfprint local est isolé à fprintd via un drop-in systemd ou un wrapper
d'activation D-Bus. Un manifeste de rollback est conservé.

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

Le cache PMK validé reste un état runtime protégé sous `/var/lib/fprint/`. rel42 ne persiste plus aucun timing adaptatif ; les anciens fichiers de timing non secrets sont supprimés à la migration.

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

[executed on device: Pegasus (8a6eeb21-0158-4e6d-b3ea-91d580f8a223)]