# Goodix GXFP51A0 / GF3658 Milan sous Linux

> Recherche expérimentale de rétro-ingénierie. Il n'existe pas encore de pilote Linux fonctionnel pour ce capteur. Aucun firmware ne doit être flashé.

> English version: [README.md](README.md)

## État actuel

<!-- current-status-2026-09-07 -->
### Frontière actuelle — 7 septembre 2026

Le common-init complet, la comparaison DMA/PIO, la trace DMA normale, le test
runtime-PM maintenu actif et l'observation MISO sur les mêmes clocks sont
terminés. Le contrôleur a exécuté les 34 transferts et 34 IRQ `idma64.4`
concrètes attendues, mais Goodix a produit 0 IRQ et les 180 octets RX déjà
clockés sont tous `0xFF`.

Ne pas rejouer de probes Linux actifs simplement pour varier DMA/runtime-PM,
timing ou emprunter une commande à un Goodix voisin. Le travail actuel est
statique, avant la première commande acceptée.

Un driver GXFP3200 Milan fonctionnel est apparu en septembre 2026, mais son
protocole F0/F1 et son reset LOW->HIGH/final-HIGH diffèrent du GXFP51A0 : c'est
une référence, pas un driver à forcer sur la cible.

Voir [`docs/current-boundary-2026-09-07.md`](docs/current-boundary-2026-09-07.md).

<!-- controller-status-2026-09-03 -->
### Résultat contrôleur — 3 septembre 2026

Le discriminant PXA2xx DMA contre PIO est terminé.

Un boot frais a prouvé le fallback PIO natif avant tout trafic fingerprint :
IDMA64 était absent, le contrôleur correspondant a journalisé
`no DMA channels available, using PIO` et les statistiques SPI de la cible
étaient à zéro. Le common-init Windows inchangé a ensuite de nouveau effectué
34 transferts SPI physiques et 12 attentes avec 0 événement IRQ Goodix,
0 lecture RX et 0 octet EVK. Les deux resets de fallback ont réussi, aucune
erreur/timeout SPI n'a été signalée et le nettoyage final a laissé GPIO264 à
LOW.

Un baseline passif séparé sur boot normal confirme IDMA64 chargé et lié, deux
canaux DMAengine associés au même parent PCI LPSS, aucun fallback PIO et aucun
trafic SPI GXFP51A0 antérieur.

DMA contre PIO est donc fermé comme explication principale du silence actuel.
La prochaine frontière logicielle est l'instrumentation runtime-PM / LPSS /
PXA2xx et des transferts.

Voir
[`docs/controller-boundary-2026-09-03.md`](docs/controller-boundary-2026-09-03.md)
et
[`SESSION_HANDOFF_2026-09-03.md`](SESSION_HANDOFF_2026-09-03.md).


Le projet a établi les ressources ACPI/SPI/GPIO, le framing Milan, le reset Windows réellement utilisé, le RX à longueur exacte, le modèle DriverState ACK/retry/reset, le modèle ACK + réponse de `GetEvkVersion`, le mapping IRQ ACPI natif, les probes Linux jusqu'au Probe #4, le `_DSM` Goodix, le démarrage Windows et un cross-check bas niveau du transport GF3658.

**Dernier résultat matériel :** le chemin common-init Windows corrigé a maintenant été exécuté intégralement une fois sur un boot frais : 34 transferts SPI, 12 attentes IRQ, 0 événement IRQ Goodix, 0 lecture et 0 octet de réponse EVK. Les deux resets de fallback ont réussi, le contrôleur n'a signalé aucune erreur ni timeout SPI, et le nettoyage final a confirmé GPIO264 à LOW.

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

Ces tâches statiques de transport sont maintenant fermées pour cette cible : GXFP51A0 sélectionne le mode 5 et le chemin Windows final utilise deux écritures SPB synchrones séparées pour les 4 octets externes puis le reste du paquet, avec 2 ms d'intervalle.

## `_DSM` ACPI Goodix

UUID :

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

La fonction 1 renvoie un buffer `HWFP/FPDT` de 2048 octets. Linux sait le lire correctement et le pilote Windows identifie ce chemin comme source de PSK.

**Le blob brut et toute PSK sont des données privées propres à la machine et ne doivent jamais être ajoutés au dépôt.**

## Question actuelle

Pourquoi une séquence GXFP51A0 fidèle à Windows et validée jusqu'au contrôleur ne produit-elle aucune donnée MISO informative ni IRQ de readiness ?

Priorité : analyse statique avant la première commande dans Goodix FP 1.1.141.36 et comparaison uniquement appuyée par des preuves avec les drivers voisins fonctionnels. Aucun force-bind et aucun nouveau probe actif sans hypothèse précise sur le même matériel.

Voir [`docs/current-boundary-2026-09-07.md`](docs/current-boundary-2026-09-07.md).

## Carte du dépôt

- [État actuel](docs/state-of-research-2026-08-31.md)
- [Réévaluation 2026-09-01](docs/reassessment-2026-09-01.md)
- [Réévaluation DMA / PIO — 2026-09-02](docs/dma-pio-reassessment-2026-09-02.md)
- [Handoff projet](PROJECT_HANDOFF.md)
- [Handoff session](SESSION_HANDOFF_2026-09-02.md)
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

GPL-2.0-only. Voir [LICENSE](../LICENSE).

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
