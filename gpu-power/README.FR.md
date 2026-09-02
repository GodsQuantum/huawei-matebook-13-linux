# GPU & alimentation — NVIDIA MX250 à la demande

> **English: [README.md](README.md)**

Cette section résout un problème précis des Huawei MateBook 13 équipés d'un iGPU Intel et d'une NVIDIA GeForce MX250 : **garder réellement le GPU dédié hors circuit au repos tout en lançant certaines applications sur NVIDIA, sans déconnexion ni redémarrage.**

## Pourquoi ne pas rester en Hybrid ?

Sur la configuration MateBook 13/MX250 validée, laisser la NVIDIA disponible en permanence réduit sensiblement l'autonomie même lorsqu'elle semble idle. L'état de repos visé est donc plus strict qu'un simple PRIME Hybrid :

```text
iGPU Intel : présent et utilisé par le bureau
MX250 :      retirée du bus PCI
NVIDIA :     modules déchargés
port PCIe :  suspendu lorsque le matériel le permet
```

Quand une application gérée démarre, le GPU est réénuméré à chaud, NVIDIA R580 est chargé, l'application reçoit les variables PRIME Render Offload et le compositeur reste sur Intel. À la fermeture de la dernière charge, les modules NVIDIA sont déchargés puis la MX250 est à nouveau retirée du PCI.

## Configuration validée

Validation de bout en bout sur :

- Huawei MateBook 13 avec Intel + NVIDIA GeForce MX250 ;
- MX250 PCI `10de:1d13` / GP108M (Pascal) ;
- KDE Plasma Wayland ;
- pilote propriétaire NVIDIA de branche R580.

Le script détecte dynamiquement les adresses PCI de l'Intel, de la MX250 et du root-port. Il refuse par défaut le matériel non-Huawei et exige toujours l'identifiant PCI de la MX250.

### Pilote requis : R580

NVIDIA 590 et les branches suivantes ont abandonné Pascal. Une MX250 doit rester sur la branche propriétaire legacy R580.

Le script connaît les familles de paquets suivantes :

- **Arch / CachyOS** — `nvidia-580xx-dkms` + `nvidia-580xx-utils` ;
- **Fedora** — RPM Fusion `akmod-nvidia-580xx` / `xorg-x11-drv-nvidia-580xx` si le dépôt est déjà activé ;
- **Debian / Ubuntu** — `nvidia-driver-580` lorsqu'il existe dans les dépôts activés.

Le script n'active jamais silencieusement un dépôt tiers.

### Ne pas empiler plusieurs switchers GPU

Ce gestionnaire contrôle le cycle PCI/modules de la MX250 tant qu'il est installé. N'effectuez pas en parallèle de changements de mode avec `optimus-manager`, EnvyControl, un bouton supergfxctl ou un autre outil qui charge/décharge/retire également la NVIDIA. Si supergfxctl est déjà présent, laissez-le en **Integrated** et ne changez pas de mode pendant une charge GPU on-demand.

## Architecture

### Au repos / au boot

L'installation crée :

- une politique modprobe empêchant le chargement automatique de NVIDIA/nouveau ;
- un helper root minimal ;
- un service de boot qui décharge NVIDIA et retire la MX250 avant la session graphique lorsque possible ;
- un alias DRM stable pour l'Intel ;
- un drop-in systemd utilisateur pour verrouiller KWin sur Intel ;
- un timer de nettoyage pour les processus crashés ou qui survivent brièvement à leur launcher.

### Lancement d'une application gérée

`huawei-matebook-dgpu-run` prend un lease. Le premier lease :

1. lance un PCI rescan ;
2. retrouve dynamiquement `10de:1d13` ;
3. charge `nvidia`, `nvidia_modeset`, `nvidia_drm` et `nvidia_uvm` ;
4. vérifie qu'aucun compositeur/bureau n'a accroché NVIDIA ;
5. lance l'application avec PRIME Render Offload.

Plusieurs applications gérées peuvent partager la MX250 simultanément grâce aux leases.

### Fermeture

La MX250 n'est coupée que lorsqu'il ne reste :

- aucun lease valide ;
- aucun processus utilisant encore les devices/render nodes NVIDIA.

Le helper décharge alors les modules NVIDIA puis retire la fonction PCI. Un timer utilisateur retente le nettoyage en cas de crash ou d'application qui se détache de son launcher.

## Installation

À lancer avec l'**utilisateur normal**, pas root :

```bash
chmod +x huawei-matebook-13-gpu-manager.sh
./huawei-matebook-13-gpu-manager.sh --lang fr install
```

Un redémarrage est attendu après la première installation.

### Mise à niveau / réparation

Relancer `install` est idempotent et effectue également les mises à niveau. La v3 sait importer l’état v1/v2 pris en charge depuis les launchers existants, sauvegardes, Launch Options Steam et manifestes portables voisins. La migration utilise un snapshot avec rollback ; les anciens helpers ne sont supprimés qu’après validation du nouveau smoke-test GPU et retour en full Integrated.

Sur CachyOS/Arch utilisant réellement Limine, le gestionnaire appelle directement `limine-mkinitcpio` afin de reconstruire ensemble les initramfs et les entrées Limine. Les autres systèmes utilisent selon le cas `mkinitcpio`, `dracut` ou `update-initramfs`.

## Ajouter ou retirer des applications

Menu :

```bash
./huawei-matebook-13-gpu-manager.sh --lang fr
```

CLI :

```bash
./huawei-matebook-13-gpu-manager.sh --lang fr add
./huawei-matebook-13-gpu-manager.sh --lang fr add DaVinciResolve.desktop
./huawei-matebook-13-gpu-manager.sh --lang fr remove DaVinciResolve.desktop
./huawei-matebook-13-gpu-manager.sh --lang fr list
```

Le script crée un override `.desktop` utilisateur et préserve un éventuel launcher local préexistant. Il impose `DBusActivatable=false` sur les applications gérées afin que l'environnement de bureau exécute bien la ligne `Exec=` modifiée.

Depuis la v3, l’état utilisateur canonique est versionné dans le répertoire de configuration XDG (`~/.config/huawei-matebook-gpu-manager/state.json` par défaut), tandis que le script conserve un manifeste portable pour récupérer la sélection après réinstallation. `install` sert aussi de commande de mise à niveau/réparation : il détecte et importe les générations précédentes prises en charge, réconcilie l’installation de façon transactionnelle, valide le cycle MX250, puis seulement supprime l’ancienne infrastructure. Un schéma d’installation plus récent n’est jamais écrasé par une ancienne version du gestionnaire.

## Commande ponctuelle

```bash
./huawei-matebook-13-gpu-manager.sh run -- glxinfo -B
./huawei-matebook-13-gpu-manager.sh run -- blender
```

## Steam

Le client Steam doit rester sur Intel. Les jeux sélectionnés peuvent être enveloppés par le runner GPU :

```bash
./huawei-matebook-13-gpu-manager.sh steam-add 730
./huawei-matebook-13-gpu-manager.sh steam-remove 730
```

Steam doit être complètement fermé lors de la modification de `localconfig.vdf`. Un backup horodaté est créé avant chaque modification et les Launch Options préexistantes sont restaurées au retrait.

L'édition directe du VDF étant plus fragile que les `.desktop`, le support Steam reste **expérimental**.

## Diagnostic et test

```bash
./huawei-matebook-13-gpu-manager.sh --lang fr status
./huawei-matebook-13-gpu-manager.sh --lang fr doctor
./huawei-matebook-13-gpu-manager.sh --lang fr test
```

Au repos, la MX250 doit être absente. Le test doit afficher brièvement un renderer NVIDIA puis revenir à une dGPU absente, sans module ni utilisateur NVIDIA restant.

## Détail Plasma / KWin

Plasma Wayland moderne peut ouvrir automatiquement les nouveaux render nodes. Si KWin ouvre la MX250, les modules NVIDIA ne peuvent plus être déchargés.

Le script installe donc :

```text
KWIN_DRM_DEVICES=/dev/dri/huawei-matebook-intel
KWIN_RENDER_NODES=
```

Le second réglage est particulièrement pertinent avec le gestionnaire GPU de Plasma 6.7+. Le helper vérifie aussi le résultat à chaque hot-add et **échoue par sécurité** si le compositeur accroche NVIDIA.

## Autres environnements de bureau

Le cœur PCI/NVIDIA/PRIME n'est pas intrinsèquement spécifique à KDE, mais le comportement du compositeur l'est. Plasma Wayland constitue le chemin validé. Sur un autre desktop, le helper refuse le lancement s'il détecte un processus inattendu utilisant NVIDIA juste après l'activation.

## Désinstallation

```bash
./huawei-matebook-13-gpu-manager.sh --lang fr uninstall
```

Les launchers gérés sont restaurés, les services/helpers et le verrou KWin sont supprimés, mais les paquets NVIDIA restent installés. Redémarrer ensuite.

## Sécurité

Le script ne flashe aucun firmware, ne touche pas à la ROM GPU et ne modifie pas les tables ACPI. Les opérations privilégiées sont limitées au chargement/déchargement de modules, au rescan/remove PCI et à la configuration udev/systemd/sudoers nécessaire.

Si le bureau accroche la NVIDIA de manière inattendue, le helper refuse de lancer l'application au lieu de forcer le déchargement d'un GPU vivant.

## Rapports de test

Merci de fournir : révision MateBook si connue **sans numéro de série**, distro/kernel, desktop Wayland/X11, lignes `lspci -nn` Intel + MX250, sortie `status` et retour ou non à une MX250 absente après la dernière application.

Ne joignez pas de numéro de série DMI, UUID, chemins de dossier personnel ou dumps système sans rapport avec le problème.
