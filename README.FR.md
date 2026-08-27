# Goodix GXFP51A0 / GF3658 Milan sous Linux

> **Recherche expérimentale uniquement — sécurité d’abord.** Aucun pilote d’empreinte fonctionnel n’existe. Ne flashez aucun firmware, n’exécutez aucune sonde non revue et n’interagissez avec le capteur que dans le cadre d’une expérience minimale revue.

> English version: [README.md](README.md)

## État


**CONFIRMÉ :** aucun pilote d’empreinte fonctionnel n’existe encore. Le premier
probe one-shot supervisé a été exécuté sans aucune opération firmware. GPIO48
est resté LOW pendant les fenêtres ACK DriverState et A/4 ; le gate RX à
longueur exacte a donc effectué zéro lecture SPI. L’analyse statique qui a suivi
a établi que le préambule DriverState historique du probe était incomplet :
DriverState:Install utilise l’ACK générique B/0 pour CHIP 9/3, une fenêtre ACK
effective de 1000 ms, une retransmission exacte par appel transport, deux appels
wrapper, puis un hard reset uniquement si les deux appels échouent. Ce modèle
corrigé est maintenant validé hors matériel sur le portable cible. Aucun probe
#2 n’a été exécuté.

## Résumé confirmé de la plate-forme

Huawei MateBook 13 2021 : DMI `WRTB-WXX9`, version `M1020`, carte `WRTB-WXX9-PCB`, BIOS Huawei `1.26`, CachyOS, dernier noyau testé `7.2.0-1-cachyos`. Le Goodix `GXFP51A0` ACPI/SPI est un capteur GF3658 Milan. Voir les [preuves matérielles](docs/hardware.md).

## Correction de reset prouvée

**CONFIRMÉ :** le HardwareID Windows 3 emploie GPIO264 `HIGH` pendant 10 ms, puis `LOW` pendant 100 ms, avec un état final `LOW`. Cela remplace l’ancien récit LOW-vers-HIGH. La réponse électrique observée sur la ligne IRQ du pad GPIO48 ne prouve pas l’acceptation du protocole. Voir [matériel](docs/hardware.md) et [sécurité](docs/safety.md).

## Résumé prouvé du transport Milan

**CONFIRMÉ :** une écriture Windows utilise des transactions SPI distinctes pour l’en-tête externe et le paquet interne, des cycles chip-select distincts et un délai de 2 ms. Les lectures Milan sont déclenchées par IRQ et de longueur exacte ; voir les [preuves de protocole](docs/protocol.md).

## Dernier résultat en direct


**CONFIRMÉ :** le premier probe one-shot supervisé a terminé son chemin borné et
son cleanup. Douze transactions physiques d’écriture SPI ont été soumises : le
préambule DriverState historique, une tentative `GetEvkVersion` et l’unique
retransmission A/4 autorisée par le modèle. GPIO48 est resté LOW pendant toute
l’expérience ; le gate RX à longueur exacte a donc correctement effectué
**zéro lecture SPI**. A/4 s’est terminé en timeout ACK après son unique
retransmission. Le cleanup interne a restauré GPIO264 LOW et le superviseur a
restauré l’état spidev temporaire. Aucune opération firmware n’a eu lieu. Une
soumission contrôleur n’est pas une acceptation MCU.

## Limite actuelle


**CONFIRMÉ :** DriverState n’est plus représenté par de simples pauses fixes de
100 ms. Le traitement ACK générique B/0 correspond maintenant à la commande
packed acquittée ; DriverState:Install cible `0x96` (CHIP 9/3), attend la
fenêtre ACK effective de 1000 ms, autorise une retransmission exacte par appel
wrapper, effectue au maximum deux appels wrapper et n’exécute le hard reset
prouvé qu’après timeout des deux appels. Le gate hors matériel sur la machine
cible passe GCC, Clang+ASan/UBSan, GCC `-fanalyzer`, les contrôles
source/privacy et le build/link réel contre libgpiod 2.3.1 sans exécuter ces
binaires.

Le superviseur indépendant exige désormais le token
`GXFP51A0_REVIEWED_PROBE_2` et utilise un timeout global de 12 secondes tout en
conservant TERM/KILL, la validation des marqueurs de cleanup, le helper de
restauration limité à GPIO264 et la restauration inconditionnelle de spidev. La
prochaine étape est la revue finale de ce chemin de commande corrigé, puis au
maximum un probe #2 supervisé. Les opérations firmware et le fallback
common-init complet à trois tentatives restent exclus.

## Carte du dépôt

- [Preuves matérielles](docs/hardware.md) — ACPI, GPIO, reset.
- [Preuves de protocole](docs/protocol.md) — framing Milan et lectures bornées.
- [Analyse du repli Windows](docs/windows-fallback.md) — provenance des tentatives, gate D0Exit et ordre exact.
- [Cross-check Windows 1.1.141.36](docs/windows-14136-crosscheck.md) — corroboration indépendante A/4/ACK/RX.
- [Recherche cross-machine](docs/cross-machine-research.md) — appareils Huawei Goodix identiques/proches et priorités de comparaison.
- [Journal de recherche](docs/research-log.md) — chronologie append-only.
- [Politique de sécurité](docs/safety.md) — procédures interdites et gate d’expérience.
- [Architecture](docs/architecture.md) — intégration Linux par étapes.
- [Transport de recherche](research/README.md) — core Milan testé hors matériel et preflight passif spidev/libgpiod.
- [Contribution](CONTRIBUTING.md) — exigences de preuves et rapport.

## Feuille de route par étapes

Propriété ACPI → transport temporaire SPI/libgpiod minimal → machine d’état Milan validée → libfprint → fprintd → connexion et sudo KDE/GNOME/PAM. Voir l’[architecture](docs/architecture.md).

## Projets de référence

- [berkekbgz/libfprint-goodix-spi](https://github.com/berkekbgz/libfprint-goodix-spi) est un précédent de transport.
- [buxel/libfprint-27c6-5110](https://github.com/buxel/libfprint-27c6-5110) ne concerne que les couches supérieures GF3658 d’image/matcher/TLS, jamais son flux firmware USB.

## Licence

Documentation de recherche et futur travail d’intégration Linux sous GPL-2.0-only. Voir [LICENSE](LICENSE).
