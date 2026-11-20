# dualboot-arch

Dual boot **Windows + Arch Linux** (dépôts CachyOS en surcouche, Hyprland) sur un MSI Cyborg 15 A12VF : un NVMe unique, graphique hybride Intel + NVIDIA.

Objectifs : ne jamais toucher à Windows, prendre des snapshots Btrfs automatiques, pouvoir revenir à n'importe quel jalon (y compris l'Arch de base), tout scripter et tout documenter.

## Démarrer

Depuis la clé live Arch (après `loadkeys fr-latin9` et la connexion réseau) :

```
cd /root
git clone https://github.com/LoickAmg/dualboot-arch.git
cd dualboot-arch
./guide.sh
```

`guide.sh` affiche l'étape en cours, la suivante et les commandes exactes. Il suit la progression, y compris après l'installation : le dépôt est alors dans `~/dualboot-arch`.

| Document | Pour quoi |
|---|---|
| [docs/GUIDE.md](docs/GUIDE.md) | le pas à pas complet, étape 0 (Windows) à 12 (maintenance) : commandes, résultat attendu, point de contrôle |
| [docs/DEPANNAGE.md](docs/DEPANNAGE.md) | environ 60 problèmes connus, classés par code (`[P3]`, `[S5]`…) |
| [docs/COMPRENDRE-SNAPSHOTS.md](docs/COMPRENDRE-SNAPSHOTS.md) | les snapshots expliqués simplement |
| [docs/RECOVERY.md](docs/RECOVERY.md) | secours sans le dépôt (à garder sur le téléphone) |
| [docs/VM.md](docs/VM.md) | répétition complète en VM |
| [docs/DECISIONS.md](docs/DECISIONS.md) | choix techniques et écarts avec le brief |

## Principes de sécurité

- **Simulation par défaut** : chaque script affiche ses commandes sans rien exécuter. Pour l'exécution réelle, le mode se donne à chaque appel, sur la ligne de commande : `DRY_RUN=0 ./script.sh …`. Avec sudo, la variable va après sudo : `sudo DRY_RUN=0 …`.
- **Confirmation `OUI`** avant chaque opération destructive (partitionnement, formatage, GRUB, suppression de sous-volume, dépôts tiers).
- **Windows intouchable** : l'ESP Windows n'est montée qu'en lecture seule (pour la sauvegarder), et aucune partition préexistante ne peut être formatée : le contrôle se fait par PARTUUID.
- Après le partitionnement, chaque partition existante est comparée **octet pour octet** (`sfdisk --dump`) à son état d'avant.
- Pas de `curl | bash`. Le script CachyOS est téléchargé, extrait, affiché, puis lancé seulement après lecture.
- Les écarts entre le brief et la doc officielle sont dans [docs/DECISIONS.md](docs/DECISIONS.md).

## Arborescence

```
guide.sh                 tableau de bord : où j'en suis, prochaine commande
config.env               paramètres (disque, tailles, utilisateur, clavier, fuseau)
config.vm.env            surcharge pour la répétition en VM
lib/common.sh            DRY_RUN, confirmations, journal, montage de l'arborescence
install/
  00-preflight-live.sh   phase 1 : état machine (lecture seule) + sauvegarde GPT / ESP Windows
  10-partition.sh        phase 2 : plan → create → format → subvols → mount
  20-base-install.sh     phase 3 : pacstrap, fstab (sans subvolid=)
  30-chroot-config.sh    phase 3 : locales, comptes, zram, initramfs, GRUB
post/
  40-snapper.sh          phase 4 : snapper, snap-pac, grub-btrfsd
  jalon.sh               snapshots de jalon permanents (00 à 06)
  50-hardware-laptop.sh  phase 5 : Intel + NVIDIA open (offload), audio, liens DRM stables
  60-cachyos-repo.sh     phase 6 : dépôts CachyOS par étapes, noyau linux-cachyos
  70-hyprland.sh         phase 7 : Hyprland via uwsm sur tty1, sway en secours
  80-maintenance.sh      phase 9 : informant, paccache, scrub, smartd
maintenance/maj-systeme.sh   mise à jour encadrée (actualités, snapshot, -Syu, pacnew)
rescue/
  restore-snapshot.sh    retour arrière permanent de @ (depuis la clé live)
  chroot-repair.sh       montage, chroot, réinstallation de GRUB
vm/make-fake-windows.sh  phase 0 : faux disque Windows dans la VM (refuse hors VM)
docs/                    JOURNAL, DECISIONS, HARDWARE, RECOVERY, VM
dotfiles/                (prévu : dépôt séparé pour ~/.config)
```

## Déroulé

Même numérotation que `guide.sh` et [docs/GUIDE.md](docs/GUIDE.md) (étapes 0 à 12).

| Étape | Où | Commandes | Contrôle avant de continuer |
|---|---|---|---|
| 0 | Windows | Clonezilla, BitLocker, `powercfg /h off`, UTC, réduire C: ; répétition conseillée : [docs/VM.md](docs/VM.md) | image vérifiée, ≥ 250 Go non alloués |
| 1 | clé live | réseau, `git clone`, `config.env`, `install/00-preflight-live.sh` | UEFI, une seule ESP Windows, ≥ 250 Go libres, pas de BitLocker |
| 2 | clé live | `install/00-preflight-live.sh backup` | GPT + ESP Windows copiées et vérifiées sur le support externe |
| 3 | clé live | `install/10-partition.sh plan`, puis `create`, `format`, `subvols`, `mount` | `lsblk -f` conforme, Windows inchangé |
| 4 | clé live | `install/20-base-install.sh` | fstab : 5 sous-volumes, aucun `subvolid=` |
| 5 | clé live (chroot) | `arch-chroot /mnt … 30-chroot-config.sh` | GRUB installé sur l'ESP Linux |
| 6 | Arch | premier démarrage, `grub-mkconfig` | Arch démarre, Windows démarre (GRUB **et** F11) |
| 7 | Arch | `post/40-snapper.sh`, tests, `post/jalon.sh 00 …` | snapshot démarrable + restauration prouvée → jalon 00 |
| 8 | Arch | `post/50-hardware-laptop.sh install`, `udev`, `check` | `nvidia-smi`, `prime-run`, dGPU `suspended` au repos → jalon 01 |
| 9 | Arch | jalon 02 ; `post/60-cachyos-repo.sh check / prepare / run / kernel` | 3 noyaux démarrent, `nvidia-smi` sur chacun → jalon 03 |
| 10 | Arch | jalon 04 ; `post/70-hyprland.sh packages` puis `user-setup` | Hyprland sur tty1, secours sur tty2 → jalon 05 |
| 11 | Arch | rice choisi (snapshot avant, script lu) | → jalon 06 |
| 12 | Arch | `post/80-maintenance.sh` ; ensuite `sudo DRY_RUN=0 maj-systeme` | |

Les scripts gardent des noms de « phase » dans leurs commentaires (phase 1 à 9, ceux du brief) : seule la numérotation en étapes ci-dessus sert de référence.

Un changement à la fois, puis un test, puis un snapshot de jalon.

## Avant la phase 1 : informations à fournir

Dans `config.env` : `HOSTNAME_NEW`, `USERNAME_NEW`, `KEYMAP`, `XKB_LAYOUT`, `BACKUP_DIR` (support externe), à confirmer : `TIMEZONE`, `ROOT_SIZE_GIB`. Les scripts refusent de tourner tant qu'une valeur requise vaut `A_COMPLETER`.

À décider aussi (voir brief §7) : rice Hyprland, partition exFAT partagée, emplacement de la bibliothèque Steam, support de sauvegarde externe.

## Journal

Les scripts lancés en mode réel ajoutent une ligne à `docs/JOURNAL.md`. Attention : après `20-base-install.sh`, les scripts tournent depuis la copie `/root/dualboot-arch` du système installé, dont le journal est distinct. Il faut reporter les lignes de la live dans cette copie.

## Secours

[docs/RECOVERY.md](docs/RECOVERY.md) : en garder une copie sur la clé Ventoy et sur le téléphone. Windows démarre toujours par **F11** sans passer par GRUB.
