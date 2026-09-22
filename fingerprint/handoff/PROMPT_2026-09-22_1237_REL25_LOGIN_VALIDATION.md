Reprends le chantier **Huawei MateBook 13 2021 / Goodix GXFP51A0 / GF3658 ST411** exactement là où la session précédente l’a laissé.

Utilise @Remote Desktop Commander sur Pegasus.

Workspace canonique :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/`

Repo canonique :
`/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/`

RDC Pegasus :
`8a6eeb21-0158-4e6d-b3ea-91d580f8a223`

Commence impérativement par lire EN ENTIER, dans cet ordre :
1. `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/HANDOFF_CURRENT.md`
2. `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/HANDOFF_CURRENT.md`
3. `/home/arezki/Projets/Workstations/Capteur Empreinte Huawei/repo/huawei-matebook-13-linux/fingerprint/handoff/HANDOFF_2026-09-22_1237_GXFP51A0_REL25_LOGIN_INTEGRATION_READY.md`

État à préserver :
- branche candidate : `fingerprint-rel25-login-integration`
- HEAD attendu : `d455738ab4254ecb170fe8e3b909587306310b7b`
- remote de branche attendu au même commit
- `libfprint-goodix51a0 1.94.100.goodix51a0-25`
- `fprintd 1.94.5-2.1`
- `plasma-login-manager 6.7.4-3.2`
- les 3 enrollments existants doivent rester intacts
- ne jamais ré-enroller sans preuve explicite que les templates sont perdus.
Diagnostic déjà établi :
- les empreintes n’ont jamais été supprimées ;
- PAM/fprintd émettait bien « Placez votre doigt sur le lecteur d’empreintes » ;
- Plasma Login Manager 6.7.4 ne rendait pas ce message dans son QML ;
- rel23 avait aussi perdu la garantie réelle d’ordre `fprintd -> display-manager`.
- rel25 corrige l’ordre avec `Before=display-manager.service`.
- le package PLM 6.7.4-3.2 applique les deux correctifs KDE de message PAM, ajoute le profil PAM fprintd package-managed, et un patch borné qui lance UNE tentative fingerprint automatiquement quand le greeter devient visible avec mot de passe vide.

État machine déjà audité :
- aucun `/etc/pam.d/plasmalogin` local ;
- aucun binder/service GXFP51A0 hérité ;
- aucun orphan pacman ;
- aucun build/src/pkg/tmp du chantier ;
- aucun failed systemd unit ;
- packages libfprint, fprintd et PLM : 0 fichier altéré ;
- `fprintd.service` résout `Before=plasmalogin.service`;
- repo propre et pushé ;
- kit de réinstallation rel25-rc1 présent dans `~/Téléchargements/OS et Drivers/`.

NE REBOOTE PAS Pegasus toi-même.

Prochaine étape humaine prioritaire si elle n’a pas déjà été faite :
1. demander à Arezki de se déconnecter de KDE, pas de reboot ;
2. sur le greeter frais, il ne doit rien taper ni appuyer sur Entrée ;
3. vérifier que la petite ligne d’invite empreinte apparaît automatiquement sous le champ mot de passe ;
4. poser un doigt déjà enregistré et vérifier que la session s’ouvre sans mot de passe ;
5. récupérer ensuite les logs `plasmalogin` + `fprintd` pour documenter le succès/échec.

Si le logout test réussit :
- demander ensuite à Arezki de faire lui-même un reboot manuel ;
- répéter exactement le test au cold boot ;
- seulement après succès des deux tests, finaliser la publication/promotion rel25 selon le handoff.

Si le test échoue :
- NE PAS ré-enroller ;
- NE PAS modifier le matcher, threshold 7, template v4/SIGFM v3 ni firmware ;
- collecter d’abord `journalctl -b -u plasmalogin.service -u fprintd.service --no-pager`, état PAM/package/systemd et comparer au handoff ;
- corriger la couche greeter/PAM/order uniquement si les logs le justifient.

À la fin de toute intervention : maintenir Pegasus pur, supprimer tous builds/tests/tmp/deps temporaires, vérifier `pacman -Qdtq`, `systemctl --failed`, `pacman -Qkk`, `git status`, puis mettre à jour le handoff avant toute promotion.