# Goodix GXFP51A0 / GF3658 Milan sous Linux

> **Recherche expérimentale uniquement — sécurité d’abord.** Aucun pilote d’empreinte fonctionnel n’existe. Ne flashez aucun firmware, n’exécutez aucune sonde non revue et n’interagissez avec le capteur que dans le cadre d’une expérience minimale revue.

> English version: [README.md](README.md)

## État

**CONFIRMÉ :** aucun pilote d’empreinte fonctionnel n’existe encore. La machine d’état Windows common-init/ACK/réponse est suffisamment résolue pour modéliser une tentative `GetEvkVersion`, le gate matériel passif spidev/libgpiod a réussi avec zéro transfert SPI, et le parser RX restreint ainsi que la machine d’état de drain IRQ/RX à longueur exacte sont validés hors matériel sur le portable cible. Aucune nouvelle commande Milan active n’est encore autorisée.

## Résumé confirmé de la plate-forme

Huawei MateBook 13 2021 : DMI `WRTB-WXX9`, version `M1020`, carte `WRTB-WXX9-PCB`, BIOS Huawei `1.26`, CachyOS, dernier noyau testé `7.2.0-1-cachyos`. Le Goodix `GXFP51A0` ACPI/SPI est un capteur GF3658 Milan. Voir les [preuves matérielles](docs/hardware.md).

## Correction de reset prouvée

**CONFIRMÉ :** le HardwareID Windows 3 emploie GPIO264 `HIGH` pendant 10 ms, puis `LOW` pendant 100 ms, avec un état final `LOW`. Cela remplace l’ancien récit LOW-vers-HIGH. La réponse électrique observée sur la ligne IRQ du pad GPIO48 ne prouve pas l’acceptation du protocole. Voir [matériel](docs/hardware.md) et [sécurité](docs/safety.md).

## Résumé prouvé du transport Milan

**CONFIRMÉ :** une écriture Windows utilise des transactions SPI distinctes pour l’en-tête externe et le paquet interne, des cycles chip-select distincts et un délai de 2 ms. Les lectures Milan sont déclenchées par IRQ et de longueur exacte ; voir les [preuves de protocole](docs/protocol.md).

## Dernier résultat en direct

**CONFIRMÉ :** chaque soumission SPI Linux contrôlée a retourné `0`, mais GPIO48 n’a pas changé d’état, l’IRQ est restée basse et l’unique lecture de quatre octets était `FF FF FF FF`. Aucune seconde lecture ni aucune opération firmware n’a eu lieu. Une soumission contrôleur n’est pas une acceptation MCU.

## Limite actuelle

**CONFIRMÉ :** le harness de probe unique et son filet de sécurité externe
indépendant sont maintenant validés hors matériel sur le portable cible. Le
superviseur possède le bind/unbind spidev temporaire, impose un timeout global
de 8 secondes avec TERM puis KILL après 2 secondes, exige les marqueurs de
cleanup/LOW final du probe et appelle un helper séparé limité à GPIO264 si ces
marqueurs manquent. Ce helper réutilise le reset prouvé HIGH 10 ms -> LOW 100 ms
-> état final LOW et ne contient aucune logique SPI/Milan. Les binaires réels se
compilent contre libgpiod 2.3.1 mais n'ont pas été exécutés. La prochaine étape
est la revue finale du chemin de commande puis au maximum un probe hardware
revu ; aucune opération firmware ni fallback common-init complet n'est
autorisé.

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
