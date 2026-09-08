# Huawei MateBook 13 sous Linux

> Notes pratiques, correctifs et rétro-ingénierie pour rendre les Huawei MateBook 13 pleinement exploitables sous Linux.
>
> **English: [README.md](README.md)**

Le MateBook 13 est déjà très utilisable sous Linux, mais sur les modèles testés avec Intel + NVIDIA MX250, deux points concentrent l'essentiel des difficultés lors du passage depuis Windows :

1. **Gestion GPU et alimentation** — utiliser la NVIDIA MX250 uniquement quand une application en a besoin, sans laisser le GPU dédié consommer en permanence et sans déconnexion/reconnexion pour changer de mode.
2. **Capteur d'empreinte** — le Goodix GXFP51A0 / GF3658 Milan ne dispose pas encore d'un pilote Linux de production et nécessite toujours de la rétro-ingénierie.

Le dépôt est désormais organisé autour de ces deux écueils.

## État en un coup d'œil

| Domaine | État | Ce que fournit le dépôt |
| --- | --- | --- |
| **GPU & alimentation — NVIDIA MX250** | **Fonctionnel sur la configuration validée** | Vrai état Integrated au repos, activation à la volée par application, PRIME Render Offload, déchargement/retrait PCI automatique, isolation Plasma/KWin, gestion Desktop et Steam |
| **Empreinte — Goodix GXFP51A0 / GF3658** | **Recherche / candidat compilable, pas encore utilisable pour la connexion** | Candidat libfprint v1.94.100 reproductible, first-contact corrigé, frontière matérielle silencieuse à 34 transferts ; prochaine frontière : observabilité physique/plateforme |

### Configuration GPU validée

Le mécanisme GPU à la demande a été validé sur un Huawei MateBook 13 avec :

- iGPU Intel ;
- NVIDIA GeForce MX250 / GP108M (`10de:1d13`) ;
- KDE Plasma Wayland ;
- pilote propriétaire NVIDIA de branche **R580**.

Le script détecte le matériel dynamiquement et contient des chemins d'installation pour les familles Arch/CachyOS, Fedora et Debian/Ubuntu. **Plasma Wayland est le chemin validé ; les autres compositeurs sont volontairement bloqués si le script détecte qu'ils accrochent la NVIDIA.**

Les branches NVIDIA 590+ ne prennent plus en charge les GPU Pascal comme la MX250 ; le projet cible donc explicitement la branche legacy R580.

## 1. GPU & alimentation — MX250 à la demande

**Commencer ici :** [`gpu-power/`](gpu-power/)

Le but n'est pas de simuler un mode Hybrid permanent. Au repos, la MX250 est retirée du bus PCI et la machine fonctionne uniquement sur l'Intel. Lorsqu'une application gérée démarre :

```text
vrai Integrated au repos
        ↓
PCI rescan
        ↓
chargement NVIDIA R580
        ↓
PRIME Render Offload pour l'application
        ↓
fermeture de l'application
        ↓
déchargement NVIDIA
        ↓
PCI remove
        ↓
vrai Integrated à nouveau
```

KWin est verrouillé sur l'iGPU Intel afin qu'il n'ouvre pas le render node NVIDIA ajouté à chaud et ne maintienne pas la MX250 éveillée.

### Démarrage rapide

```bash
cd gpu-power
chmod +x huawei-matebook-13-gpu-manager.sh
./huawei-matebook-13-gpu-manager.sh --lang fr install
```

Après le redémarrage demandé :

```bash
# menu interactif
./huawei-matebook-13-gpu-manager.sh --lang fr

# ou CLI
./huawei-matebook-13-gpu-manager.sh --lang fr add
./huawei-matebook-13-gpu-manager.sh --lang fr status
./huawei-matebook-13-gpu-manager.sh --lang fr test
```

Voir [`gpu-power/README.FR.md`](gpu-power/README.FR.md) pour l'architecture, les distributions, Steam, le rollback et le dépannage.

## 2. Capteur d'empreinte — Goodix GXFP51A0 / GF3658 Milan

**Commencer ici :** [`fingerprint/`](fingerprint/)

Tout le projet de recherche initial sur le capteur d'empreinte est conservé dans ce dossier : protocole, ressources ACPI/SPI/GPIO, probes supervisées, cross-checks du pilote Windows et documentation de sécurité.

État actuel : **il n'existe toujours pas de pilote Linux fonctionnel pour ce capteur.** Le candidat compile désormais de manière reproductible contre libfprint v1.94.100 et son first-contact est aligné sur le chemin Windows reconstruit, mais la séquence Linux déjà testée reste silencieuse (34 transferts SPI, 0 IRQ Goodix, 180/180 octets RX retenus à `0xFF`). DMA/PIO et les autres hypothèses côté contrôleur sont fermés ; la frontière actuelle est l'observabilité physique/plateforme. Un nouveau contributeur peut reproduire tout le baseline logiciel avec `make -C fingerprint verify`.

Architecture cible :

```text
transport Milan Linux validé
-> libfprint
-> fprintd
-> KDE/GNOME/PAM / sudo
```

## Matériel pris en charge et périmètre

Huawei a commercialisé plusieurs révisions sous le nom MateBook 13. Elles ne partagent pas nécessairement le même GPU NVIDIA, le même ACPI ni le même capteur biométrique.

L'outil GPU exige une MX250 avec l'identifiant PCI `10de:1d13` et refuse par défaut le matériel non reconnu. La recherche fingerprint vise spécifiquement `ACPI\GXFP51A0` / GF3658 Milan.

Si votre révision diffère, ouvrez une issue avec uniquement des **identifiants matériels génériques**. Ne publiez pas de numéro de série ni de données de sécurité propres à votre machine.

## Vie privée et sécurité

Ne publiez pas dans ce dépôt public :

- noms d'utilisateur, chemins de dossier personnel ou hostnames ;
- numéros de série ou UUID propres à la machine ;
- adresses IP privées/publiques non nécessaires à la reproduction ;
- mots de passe, tokens API, clés privées ou identifiants ;
- payloads `_DSM` Goodix bruts, PSK ou autre matériel biométrique propre à la machine ;
- binaires Windows propriétaires, firmwares ou désassemblage brut.

Préférez les hashes, identifiants PCI/ACPI et extraits minimaux reproductibles. Toute expérimentation fingerprint doit également respecter [`fingerprint/docs/safety.md`](fingerprint/docs/safety.md).

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Les résultats doivent distinguer **CONFIRMED**, **INFERRED** et **HYPOTHESIS** et fournir un contexte système générique suffisant pour la reproduction.

Pour les problèmes de sécurité, voir [SECURITY.md](SECURITY.md).

## Licence

GPL-2.0-only. Voir [LICENSE](LICENSE).
