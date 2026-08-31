# Goodix GXFP51A0 / GF3658 Milan sous Linux

> Recherche expérimentale de rétro-ingénierie. Il n'existe pas encore de pilote Linux fonctionnel pour ce capteur. Aucun firmware ne doit être flashé.

> English version: [README.md](README.md)

## État actuel

Le projet a maintenant établi les ressources ACPI/SPI/GPIO, le framing Milan, le reset Windows réellement utilisé, le RX à longueur exacte, le modèle DriverState ACK/retry/reset, le modèle ACK + réponse de `GetEvkVersion`, les probes Linux jusqu'au probe #3 corrigé, le `_DSM` Goodix et le chemin de démarrage Windows jusqu'à DriverState et `init_MCU`.

**Dernier résultat matériel :** le probe #3 reste totalement silencieux côté capteur. GPIO48 reste LOW et aucune lecture RX n'est déclenchée. La suppression du reset initial non prouvé n'a pas restauré la communication.

État canonique détaillé :

**[État de la recherche — 2026-08-31](docs/state-of-research-2026-08-31.md)**

## Ordre Windows établi

```text
MilanEvtDeviceD0Entry
  -> _StartInitThread
      -> InitThread
          -> _DeviceInit
              -> send_driver_install_to_MCU
                  -> SetDriverState(9,3 / 0x96)
              -> init_MCU
                  -> GetEvkVersionWithRetry
          -> étapes SGX/TLS/PSK ultérieures
```

DriverState est donc bien envoyé avant la requête EVK visible et avant les étapes TLS/PSK ultérieures.

## `_DSM` ACPI Goodix

UUID :

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

La fonction 1 renvoie un buffer `HWFP/FPDT` de 2048 octets. Linux sait le lire correctement et le pilote Windows identifie ce chemin comme source de PSK.

**Le blob brut et toute PSK sont des données privées propres à la machine et ne doivent jamais être ajoutés au dépôt.**

## Question actuelle

Le problème principal est désormais de comprendre pourquoi des transactions SPI Linux correctement soumises ne provoquent aucune readiness/ACK.

Le chemin Windows précédant DriverState est maintenant suffisamment fermé pour isoler une seule variable expérimentale. Linux résout également le `GpioInt[0]` ACPI de la cible vers l'IRQ matériel 48 avec la sémantique `LEVEL_HIGH`.

**Prochaine étape contrôlée :** le probe #4 est préparé mais n'a pas été exécuté. Il conserve le protocole et la politique de reset du probe #3 et remplace uniquement le polling userspace de GPIO48 par l'attente de l'IRQ ACPI native du noyau. Un boot frais, une exécution unique et le superviseur indépendant de 12 secondes sont obligatoires.

Aucune commande wake Goodix générique ne doit être ajoutée sans preuve sur ce modèle.

## Carte du dépôt

- [État actuel](docs/state-of-research-2026-08-31.md)
- [Handoff](PROJECT_HANDOFF.md)
- [Matériel](docs/hardware.md)
- [Protocole](docs/protocol.md)
- [Journal](docs/research-log.md)
- [Sécurité](docs/safety.md)
- [Architecture](docs/architecture.md)
- [Transport de recherche](research/README.md)

## Objectif

```text
transport Milan Linux validé
-> libfprint
-> fprintd
-> KDE/GNOME/PAM / sudo
```

## Sécurité

Aucun flash firmware, UPFW, erase, bootloader ou flux firmware USB Goodix étranger au GXFP51A0 n'est autorisé.

Voir [docs/safety.md](docs/safety.md).

## Licence

GPL-2.0-only. Voir [LICENSE](LICENSE).
