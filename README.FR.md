# Goodix GXFP51A0 / GF3658 Milan sous Linux

> Recherche expérimentale de rétro-ingénierie. Il n'existe pas encore de pilote Linux fonctionnel pour ce capteur. Aucun firmware ne doit être flashé.

> English version: [README.md](README.md)

## État actuel

Le projet a établi les ressources ACPI/SPI/GPIO, le framing Milan, le reset Windows réellement utilisé, le RX à longueur exacte, le modèle DriverState ACK/retry/reset, le modèle ACK + réponse de `GetEvkVersion`, le mapping IRQ ACPI natif, les probes Linux jusqu'au Probe #4, le `_DSM` Goodix, le démarrage Windows et un cross-check bas niveau du transport GF3658.

**Dernier résultat matériel :** le Probe #4 a remplacé le polling userspace de GPIO48 par l'IRQ ACPI native du noyau et reste totalement silencieux : 16 transactions SPI, 6 attentes IRQ, 0 événement IRQ Goodix, 0 lecture et aucun ACK. L'hypothèse du polling GPIO raté est donc rejetée.

Voir :

- **[État de la recherche — 2026-08-31](docs/state-of-research-2026-08-31.md)**
- **[Réévaluation — 2026-09-01](docs/reassessment-2026-09-01.md)**

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

## Cross-check transport GF3658

Goodix FP `1.1.141.36` contient un chemin de transport qui effectue :

```text
transfert des 4 premiers octets
attente 2 ms
transfert du reste
```

pour les modes de transport `2`, `3` et `5`. Cela corrobore indépendamment le modèle Milan outer/inner existant.

Il reste à rattacher GXFP51A0 à son mode runtime exact et à suivre le helper SPB commun jusqu'à la primitive I/O Windows finale.

## `_DSM` ACPI Goodix

UUID :

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

La fonction 1 renvoie un buffer `HWFP/FPDT` de 2048 octets. Linux sait le lire correctement et le pilote Windows identifie ce chemin comme source de PSK.

**Le blob brut et toute PSK sont des données privées propres à la machine et ne doivent jamais être ajoutés au dépôt.**

## Question actuelle

Le problème principal est maintenant situé sous la couche readiness/ordonnancement protocolaire : pourquoi des transactions SPI soumises au contrôleur Linux ne provoquent aucun IRQ/RX Goodix observable.

Les Probes #3 et #4 sont terminés et ne doivent pas être rejoués.

Priorité actuelle :

1. fermer le mapping du mode de transport Windows pour GXFP51A0 ;
2. fermer la primitive SPB Windows finale sous le helper split-write ;
3. si les frontières de transaction Linux restent correctes, passer à l'observabilité SPI physique plutôt que d'ajouter des commandes spéculatives.

Aucune commande wake Goodix générique ne doit être ajoutée sans preuve sur ce modèle.

## Carte du dépôt

- [État actuel](docs/state-of-research-2026-08-31.md)
- [Réévaluation 2026-09-01](docs/reassessment-2026-09-01.md)
- [Handoff projet](PROJECT_HANDOFF.md)
- [Handoff session](SESSION_HANDOFF_2026-09-01.md)
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

<!-- current-boundary-2026-09-02 -->
## Frontière de recherche actuelle — 2 septembre 2026

La reconstruction du démarrage Windows a été corrigée :
`DriverState:Install` n'est pas le gate fatal de `_DeviceInit`.
Le premier véritable gate de réponse du capteur est
`GetEvkVersionWithRetry`, avec un défaut compilé de 3 tentatives externes dans
Goodix FP 1.1.141.36, puis un reset de fallback distinct et une dernière
tentative.

Un traçage Linux réel confirme également que les transferts testés atteignent
le chemin LPSS `lpss_ssp_cs_control`.

Voir [`docs/software-boundary-2026-09-02.md`](docs/software-boundary-2026-09-02.md).
