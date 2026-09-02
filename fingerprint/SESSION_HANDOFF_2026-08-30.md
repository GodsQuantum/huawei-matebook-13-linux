# Prompt de handoff — nouvelle session ChatGPT

Tu reprends un projet de reverse engineering / driver Linux déjà très avancé pour le capteur d'empreintes Goodix `GXFP51A0` / GF3658 Milan d'un Huawei MateBook 13 2021.

## Mission

Continuer jusqu'à obtenir un support Linux stable, générique et upstream-friendly, idéalement via libfprint/fprintd en userspace, sans firmware flashing et sans transformer les expériences de recherche en séquences destructrices ou non maîtrisées.

Repo canonique :

`https://github.com/GodsQuantum/huawei-matebook-fingerprint-linux`

Au début de cette nouvelle session :

1. vérifie le `main` distant et le dernier commit ;
2. lis d'abord `SESSION_HANDOFF_2026-08-30.md` si présent ;
3. lis ensuite `docs/probe3-no-initial-reset-analysis.md`, `PROJECT_HANDOFF.md`, `docs/safety.md`, `docs/protocol.md`, `docs/windows-fallback.md` et la fin de `docs/research-log.md` ;
4. considère que `SESSION_HANDOFF_2026-08-30.md` et `docs/probe3-no-initial-reset-analysis.md` supersèdent l'ancienne section « Exact next engineering step » de `PROJECT_HANDOFF.md` si celle-ci n'a pas encore été réécrite.

Le code canonique avant les commits de documentation de handoff était :

`10f0cb97cd8199e1acdc827ee536179c768576c1` — `research: model DriverState ACK retry and reset`

Vérifie toujours le HEAD courant au lieu de supposer que ce SHA est encore `main`.

## Matériel / transport confirmé

- Huawei MateBook 13 2021, DMI `WRTB-WXX9`, version `M1020`, board `WRTB-WXX9-PCB`, BIOS Huawei 1.26.
- Capteur Goodix `GXFP51A0` / GF3658 Milan.
- ACPI : `\_SB.PCI0.SPI1.SPBA`.
- SPI1 CS0, mode 0, 8 bits, 10 MHz, four-wire.
- GPIO48 = data-ready/IRQ ACPI level-triggered ActiveHigh.
- GPIO264 = reset/control output.
- Reset HardwareID3 prouvé : GPIO264 HIGH 10 ms -> LOW 100 ms -> final LOW.

Ne confonds jamais GPIO48 avec le numéro d'IRQ virtuel Linux.

## Invariants de sécurité non négociables

- Aucun firmware flashing, UPFW, erase, bootloader programming ou firmware-management aveugle.
- Ne jamais lancer OpenGoodixSPI non modifié, goodix-fp-dump full-device, PopulusYang full_test/ProgramStart ou un flow firmware USB 27c6:5110/5117 sur ce capteur SPI.
- RX exact-length uniquement : attendre readiness -> lire exactement 4 octets d'outer header -> valider -> lire exactement la longueur annoncée.
- Après `FF FF FF FF` : arrêt immédiat, aucune seconde lecture.
- Cleanup/reset final obligatoire après toute future expérience active : HIGH 10 ms -> LOW 100 ms -> final LOW.
- Cleanup inconditionnel sur erreurs/signaux.
- GPIO48 : input-only, polling de niveau borné ; **ne jamais demander rising-edge detection**.
- GPIO264 : vérifier qu'il est déjà libre, OUTPUT, active-high, sans edge detection ; le demander avec `GPIOD_LINE_DIRECTION_AS_IS` et ne changer que sa valeur.
- Aucun pinmux write sur les pads firmware-locked.
- Pas de firmware/binaire Windows propriétaire, dump brut, ETL/PDB ou disassembly massif dans Git ; uniquement hashes et petits extraits techniques nécessaires.
- Un `ioctl` SPI réussi prouve une soumission au contrôleur Linux, jamais l'acceptation par le MCU.

## Protocole Milan confirmé

Une écriture logique est deux transactions SPI physiques / deux cycles CS :

1. outer header ;
2. délai 2 ms ;
3. inner packet.

Vecteurs :

```text
NOP outer: A0 08 00 A8
NOP inner: 00 05 00 00 00 00 00 A5

DriverState:Install outer: A0 06 00 A6
DriverState:Install inner: 96 03 00 01 00 10

A/4 fixture Linux outer: A0 06 00 A6
A/4 fixture Linux inner: A8 03 00 00 00 FF
```

Le payload A/4 `00 00` est une fixture Linux déterministe ; ce n'est pas une constante Windows prouvée.

## GetEvkVersion confirmé

- Une tentative : NOP -> 5 ms -> A/4.
- Timeout ACK demandé 100 ms mais clampé à >=1000 ms.
- Premier timeout ACK : retransmission exacte A/4 une seule fois.
- Second timeout ACK : échec de l'envoi.
- Après ACK : phase réponse séparée sur event logique 9, timeout demandé 500 ms également clampé à >=1000 ms.
- B/0 + `payload[0] == A8` = ACK de A/4.
- A/4 normal = réponse EVK.
- ACK et réponse peuvent être drainés dans la même fenêtre IRQ-high ; deux edges physiques ne sont pas requis.

Le fallback common-init complet Windows (3 tentatives + hard reset + tentative finale) existe mais **n'est pas autorisé** dans le prochain probe.

## DriverState corrigé

DriverState:Install est CHIP 9/3, packed command `0x96`.

- B/0 + `payload[0] == 0x96` => ACK(9,3).
- Timeout ACK effectif : 1000 ms minimum.
- Chaque wrapper peut envoyer Install deux fois max : envoi initial + retransmission exacte après premier timeout.
- Deux wrapper calls max.
- Donc quatre envois physiques Install max sur un chemin totalement silencieux.
- `HardResetMcu` DriverState uniquement après échec des deux wrapper calls.
- Pas de phase réponse séparée pour DriverState.

## Résultat du premier probe live

Le premier one-shot supervisé est négatif mais sûr : GPIO48 est resté LOW, aucun RX n'a été effectué tant que readiness était absent, aucun ACK n'a été observé, A/4 a utilisé son unique retransmission autorisée, le cleanup a restauré GPIO264 LOW et l'état spidev a été restauré. Aucune opération firmware.

Ce probe avait encore un préambule DriverState approximatif ; il ne permet donc pas de conclure sur A/4.

## Dernière correction statique importante : pas de reset initial prouvé

Le reset HIGH10/LOW100 est prouvé comme primitive Windows, mais sa présence **avant DriverState au démarrage normal** ne l'est plus.

- `MilanEvtDeviceD0Entry` ne contient pas d'appel direct à `HardResetMcu`.
- Le helper de D0Entry étudié ne remonte pas vers un reset inconditionnel.
- Le callsite `0x18000ea42` de `HardResetMcu` se trouve dans le thread d'initialisation et est conditionnel à un état de tentative ; il est sauté lorsque cet état vaut zéro.
- Il fait partie d'une logique de retry, pas d'un reset d'entrée systématique.

Conclusion actuelle : le prochain modèle doit **supprimer uniquement le reset initial**, mais préserver le reset fallback DriverState et le cleanup final.

## Probe #3 hors matériel déjà préparé localement

Patch SHA-256 :

`6d9f26183aa471ac569f845fcf20eace50fbab4e6b0344e82aed2285c1d3cebd`

Fichiers modifiés attendus :

```text
research/linux/live_probe_supervisor.sh
research/linux/probe_runtime.c
research/probe_harness.c
research/probe_harness.h
research/tests/test_live_probe_supervisor.sh
research/tests/test_probe_harness.c
research/tests/test_probe_runtime_source_safety.sh
```

Invariants du patch :

```text
INITIAL_RESET=NO
DRIVERSTATE_FALLBACK_RESET=PRESERVED
FINAL_CLEANUP_RESET=PRESERVED
DRIVERSTATE_ACK_TARGET=96
DRIVERSTATE_ACK_TIMEOUT_MS=1000
DRIVERSTATE_WRAPPER_CALLS=2
DRIVERSTATE_SENDS_PER_WRAPPER=2
DRIVERSTATE_MAX_INSTALL_SENDS=4
A4_FIXTURE=0000
SUPERVISOR_TOKEN=GXFP51A0_REVIEWED_PROBE_3
SUPERVISOR_TIMEOUT=12S
```

Le gate hors matériel rapporte GCC, Clang+ASan/UBSan, GCC fanalyzer et build/link libgpiod 2.3.1 OK, sans exécuter les vrais binaires ni aucune action hardware.

### Mais : bug du privacy gate

Le log montre que le scan `grep` privacy a cassé un chemin local contenant un métacaractère shell, puis a quand même affiché `PRIVACY_AUDIT=OK`.

Donc :

- tests/builds/invariants : exploitables ;
- verdict privacy de ce gate : **INVALIDE**, à corriger et rejouer ;
- ne publie pas le patch probe #3 tant que ce scan n'est pas corrigé.

Le tree GitHub courant a été contrôlé séparément sans retrouver les fragments personnels/local-path recherchés, mais cela ne constitue pas une garantie d'effacement absolu des objets Git historiques.

## Pinmux : conclusion actuelle

- Les quatre pads principaux GSPI1 CS/CLK/MISO/MOSI observés sont en mode natif SPI.
- Les transferts atteignent le contrôleur Linux sans erreur de soumission.
- Le pinmux SPI principal n'est donc plus l'hypothèse prioritaire.
- Un pad de clock-loopback Cannon Lake-LP apparaît comme différence potentielle, mais il est firmware full-locked et la représentation runtime du kernel rend son rôle ambigu.
- **Ne jamais le remuxer ou l'écrire** sans preuve beaucoup plus forte.

## Pourquoi le prochain live probe doit être fresh-boot et one-shot

Le probe #3 cherche précisément à tester l'état naturel sans reset initial.

Or chaque cleanup d'un probe précédent effectue volontairement le reset GPIO264 prouvé. Une seconde exécution dans le même boot ne serait donc plus une reproduction du même état initial.

Le prochain live test, seulement après publication canonique du modèle et revue finale, doit être :

1. cold/fresh boot ;
2. aucune opération protocole fingerprint ni GPIO264 avant le probe ;
3. préchecks passifs minimum ;
4. exécution du superviseur probe #3 exactement une fois ;
5. pas d'appel direct de `gxfp-live-probe` ;
6. pas de répétition dans le même boot ;
7. cleanup/reset final obligatoire malgré tout ;
8. restauration spidev/module inconditionnelle.

## Prochaine tâche exacte pour cette nouvelle session

Ne fais **aucune action hardware immédiatement**.

1. Inspecte le repo et confirme le HEAD courant.
2. Vérifie que le patch probe #3 local correspond toujours exactement aux 7 fichiers et au SHA ci-dessus si les artefacts sont fournis.
3. Corrige seulement le bug de quoting du privacy audit ; ne rechange pas le modèle protocolaire.
4. Rejoue le gate probe #3 entièrement off-hardware.
5. Si et seulement si tout est vert, publie le modèle probe #3 sur `main` avec un commit dédié et vérifie le remote.
6. Prépare ensuite un unique script/commande de fresh-boot one-shot, relis-le contre les invariants ci-dessus et seulement alors autorise un probe live.
7. Interprète le résultat au niveau IRQ + trames réelles ; ne prends jamais `SPI_XFER rc=0` comme preuve d'acceptation MCU.

Aucune firmware operation, enrollment, image capture, full common-init fallback ou intégration libfprint avant d'avoir obtenu une réponse protocolaire crédible et reproductible.

## Style de collaboration avec l'utilisateur

- Répondre en français, direct et technique.
- Pour les opérations terminal, grouper toutes les commandes dans **un seul bloc** afin de minimiser les copier-coller.
- Préférer un script/gate court produisant un log et un summary plutôt qu'un énorme paste terminal.
- Ne pas redemander des informations déjà fournies.
- Pousser régulièrement les avancées pertinentes sur Git, mais ne jamais pousser d'informations personnelles, de chemins locaux ou d'artefacts Windows propriétaires.
- Une seule hypothèse matérielle par expérience.
