# Phase 0 — Répétition complète en VM

But : dérouler **toute** l'installation sur un disque virtuel qui imite le vrai (ESP Windows + NTFS + espace libre), puis prouver qu'un snapshot démarre et que `restore-snapshot.sh` fonctionne. Le vrai NVMe n'est jamais concerné.

## 1. Créer la VM (VMware Workstation, déjà installé)

1. Nouvelle VM → *Custom* → *I will install the operating system later* → Linux / Other Linux 6.x 64-bit.
2. Firmware : **UEFI** (*Options → Advanced → Firmware type : UEFI*), Secure Boot décoché.
3. RAM 4 Go minimum, 2 vCPU au moins, réseau NAT.
4. Disque : type **NVMe**, 120 Go, *Store as a single file*, non préalloué. Dans la VM, il apparaît en `/dev/nvme0n1`, comme sur le vrai PC.
5. CD/DVD : l'ISO Arch officielle (vérifier sa signature ou sa somme SHA256 depuis archlinux.org/download).

Alternative : QEMU avec OVMF (`-machine q35 -bios OVMF.fd -drive file=disk.qcow2,if=none,id=d0 -device nvme,drive=d0,serial=vm0`).

## 2. Amener le dépôt dans la live

Au choix :
- `git clone` du dépôt (s'il est publié) ;
- ou un dossier partagé VMware / une seconde image disque contenant le dépôt.

```bash
loadkeys fr-latin9
cd dualboot-arch
```

## 3. Dérouler

```bash
export CONFIG_FILE=./config.vm.env
mkdir -p /root/vm-backup
DRY_RUN=0 ./vm/make-fake-windows.sh          # refuse hors VM
./install/00-preflight-live.sh               # lecture seule
DRY_RUN=0 ./install/00-preflight-live.sh backup
./install/10-partition.sh plan
DRY_RUN=0 ./install/10-partition.sh create
DRY_RUN=0 ./install/10-partition.sh format
DRY_RUN=0 ./install/10-partition.sh subvols
DRY_RUN=0 ./install/10-partition.sh mount
DRY_RUN=0 ./install/20-base-install.sh
arch-chroot /mnt env DRY_RUN=0 CONFIG_FILE=/root/dualboot-arch/config.vm.env /root/dualboot-arch/install/30-chroot-config.sh
umount -R /mnt ; reboot
```

Dans l'Arch de la VM (root) :

```bash
cd /root/dualboot-arch ; export CONFIG_FILE=./config.vm.env
DRY_RUN=0 ./post/40-snapper.sh
```

Les phases 5 (NVIDIA) et 6 (CachyOS) ne sont pas représentatives en VM, sauf l'ajout des dépôts CachyOS, qu'on peut y répéter pour lire le script et voir ce qu'il change.

## 4. Points de contrôle de la phase 0

| # | Test | Attendu | OK ? |
|---|---|---|---|
| 1 | `10-partition.sh create` | 2 partitions ajoutées, « partitions existantes identiques » | |
| 2 | `cat /etc/fstab` | 5 sous-volumes, aucun `subvolid=` | |
| 3 | Démarrage | menu GRUB, Arch démarre | |
| 4 | os-prober | entrée Windows visible après `grub-mkconfig` (elle ne démarre pas : faux chargeur, c'est normal) | |
| 5 | `pacman -S tree` | 2 snapshots pre/post (`snapper list`) | |
| 6 | Menu « Arch Linux snapshots » | un snapshot démarre (lecture seule + overlay) | |
| 7 | Casser : `rm /usr/bin/nano` (ou autre fichier non critique) | | |
| 8 | Live : `DRY_RUN=0 ./rescue/restore-snapshot.sh N` | redémarre, fichier revenu, `/home` et `/.snapshots` montés | |
| 9 | Live : `DRY_RUN=0 ./rescue/chroot-repair.sh grub` | GRUB réinstallé, démarre | |
| 10 | Supprimer l'entrée UEFI dans le firmware de la VM, puis niveau 3 de RECOVERY.md **sans le dépôt** | redémarre | |

Faire un snapshot VMware de la VM après le test 3 : on peut ainsi rejouer les tests 6 à 10 autant de fois que nécessaire.

Noter le résultat de chaque test dans `docs/JOURNAL.md`. **La phase 1 sur la vraie machine ne commence que si les 10 tests sont OK.**
