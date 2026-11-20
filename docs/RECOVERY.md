# RECOVERY — procédures de secours

> Ce document doit être lisible **sans que le système démarre**. Il faut en garder une copie sur la clé Ventoy et sur le téléphone.
> Toutes les commandes ci-dessous fonctionnent **sans le dépôt**, depuis la clé live Arch.

Repères :

| Élément | Valeur |
|---|---|
| Disque | `/dev/nvme0n1` |
| Racine Linux (Btrfs) | label `archroot` → `/dev/disk/by-label/archroot` |
| ESP Linux (GRUB seul) | label `ARCHESP` → `/dev/disk/by-label/ARCHESP` |
| ESP Windows | **ne jamais y écrire** |
| Sous-volumes | `@` (système) `@home` `@snapshots` `@var_log` `@pkg` |
| Démarrer Windows sans GRUB | **F11** au logo MSI (menu de démarrage du firmware) |

Clavier AZERTY dans la live : `loadkeys fr-latin9`.

---

## Quel niveau ?

| Symptôme | Niveau |
|---|---|
| Arch démarre mais est cassé (mise à jour ratée, pilote) | **1**, puis **2** |
| Arch ne démarre plus, le menu GRUB s'affiche | **1** (snapshot ou noyau `linux-lts`), puis **2** |
| Pas de menu GRUB du tout | **3** |
| Windows ne démarre plus | **4** |

---

## Niveau 1 — Démarrer un snapshot (sans rien modifier)

1. Redémarrer. Dans GRUB : **Arch Linux snapshots** → choisir un snapshot (le dernier jalon `JALON NN`, ou le snapshot « pre » de la mise à jour fautive).
2. Le snapshot démarre en lecture seule avec une surcouche en RAM (hook `grub-btrfs-overlayfs`) : les modifications sont perdues au redémarrage.
3. Autre option : GRUB → *Advanced options* → noyau **linux-lts**.
4. Si le snapshot fonctionne, le rendre permanent avec le niveau 2.

## Niveau 2 — Restauration permanente de `@`

Depuis la clé live. Avec le dépôt (copié sur la clé) :

```bash
cd dualboot-arch
./rescue/restore-snapshot.sh                 # liste numéros + descriptions
./rescue/restore-snapshot.sh 42              # simulation
DRY_RUN=0 ./rescue/restore-snapshot.sh 42    # réel, demande OUI
```

**Sans le dépôt** (procédure manuelle équivalente) :

```bash
mkdir -p /mnt/top
mount -o subvolid=5 /dev/disk/by-label/archroot /mnt/top
ls /mnt/top/@snapshots/                              # numéros
grep -h description /mnt/top/@snapshots/*/info.xml   # descriptions
N=42                                                 # <- numéro choisi
STAMP=$(date +%Y%m%d-%H%M%S)
mv /mnt/top/@ /mnt/top/@broken-$STAMP                # l'ancien système est GARDÉ
btrfs subvolume snapshot /mnt/top/@snapshots/$N/snapshot /mnt/top/@
mkdir -p /mnt/top/@/.snapshots
umount /mnt/top
reboot
```

Après le redémarrage :

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
snapper -c root list
findmnt /home /.snapshots /var/log
```

`@home` n'est **pas** restauré (les données restent). Supprimer `@broken-…` seulement une fois le système validé, quelques jours plus tard.

## Niveau 3 — GRUB ne s'affiche plus

1. Démarrer **Windows par F11** si besoin : il ne dépend pas de GRUB.
2. Clé live Arch, puis monter et chrooter :

```bash
mount -o noatime,compress=zstd:1,subvol=@          /dev/disk/by-label/archroot /mnt
mount -o noatime,compress=zstd:1,subvol=@home      /dev/disk/by-label/archroot /mnt/home
mount -o noatime,compress=zstd:1,subvol=@snapshots /dev/disk/by-label/archroot /mnt/.snapshots
mount -o noatime,compress=zstd:1,subvol=@var_log   /dev/disk/by-label/archroot /mnt/var/log
mount -o noatime,compress=zstd:1,subvol=@pkg       /dev/disk/by-label/archroot /mnt/var/cache/pacman/pkg
mount /dev/disk/by-label/ARCHESP /mnt/efi
lsblk -f                                   # VÉRIFIER : /mnt/efi = ARCHESP, pas l'ESP Windows
arch-chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH-GRUB
grub-mkconfig -o /boot/grub/grub.cfg
exit
umount -R /mnt
reboot
```

Avec le dépôt : `DRY_RUN=0 ./rescue/chroot-repair.sh grub`.

Si le firmware MSI n'affiche toujours pas `ARCH-GRUB` : refaire `grub-install` en ajoutant `--removable`. Cela écrit `EFI/BOOT/BOOTX64.EFI` sur l'ESP **Linux** (montée sur `/efi`), jamais sur celle de Windows. Puis sélectionner ce disque/partition dans F11.

Si `/` refuse de monter (`@` cassé) : faire d'abord le niveau 2 manuel, puis le niveau 3.

## Niveau 4 — Windows ne démarre plus

- Vérifier d'abord avec **F11** : choisir *Windows Boot Manager*.
- Clé Windows de secours (sur la Ventoy) → Invite de commandes → `bootrec /scanos`, `bootrec /rebuildbcd`. Ne pas lancer `bootrec /fixmbr` (disque GPT).
- Dernier recours : restaurer l'**image Clonezilla** faite en phase 0.

## Table de partitions endommagée

Sauvegardes dans `BACKUP_DIR/preflight-DATE/` :

- `nvme0n1-sfdisk.txt` : version texte, à **lire** et comparer avec `sfdisk --dump /dev/nvme0n1`.
- `nvme0n1-gpt.bak` : restauration binaire. Elle écrase la GPT actuelle, et toute partition créée après la sauvegarde disparaît de la table (ses données restent sur le disque) :
  `sgdisk --load-backup=nvme0n1-gpt.bak /dev/nvme0n1` (seulement si la table est réellement cassée, après avoir comparé).

## Après chaque restauration

Noter dans `docs/JOURNAL.md` : date, niveau utilisé, snapshot restauré, cause.
