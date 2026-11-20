# Voie manuelle — étapes 3 à 5 sans les scripts

À utiliser **seulement si un script plante** : message d'erreur incompréhensible, commande introuvable, comportement inattendu. Ces commandes font la même chose que `10-partition.sh`, `20-base-install.sh` et `30-chroot-config.sh`, mais une par une, sans garde-fou automatique. **Les contrôles deviennent ta responsabilité** : chaque bloc se termine par une vérification à faire **avant** de passer au suivant.

Tu peux reprendre la voie manuelle à n'importe quelle sous-étape : il suffit de vérifier que la sous-étape précédente est bien faite (son contrôle).

Conventions dans ce document :
- `X` = numéro de la partition **ARCH-ESP** (1 GiB), `Y` = numéro de la partition **ARCH-ROOT** (250 GiB). Ils ne sont connus qu'après 3.1 : les relire à chaque fois.
- Tout se tape en root dans la clé live, sauf indication contraire.

---

## 3. Partitionner, formater, monter

### 3.0 Avant toute écriture

```
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,PARTUUID
sfdisk --dump /dev/nvme0n1 > /root/avant.txt
cat /root/avant.txt
```
La sauvegarde de l'étape 2 doit exister sur le support externe (`nvme0n1-gpt.bak`). **Sans elle, ne pas continuer.**

### 3.1 Créer les deux partitions

Si `10-partition.sh plan` a fonctionné, utiliser ses secteurs exacts :
```
cat /mnt/usb/dualboot-backup/plan-partition/plan.env      # ESP_START, ESP_END, ROOT_START, ROOT_END
sgdisk -n 0:ESP_START:ESP_END   -t 0:ef00 -c 0:ARCH-ESP  /dev/nvme0n1
sgdisk -n 0:ROOT_START:ROOT_END -t 0:8300 -c 0:ARCH-ROOT /dev/nvme0n1
```
(remplacer les noms par les nombres du fichier)

Sinon, laisser sgdisk choisir. Un début à `0` signifie « début du plus grand bloc libre » :
```
sgdisk -F /dev/nvme0n1 ; sgdisk -E /dev/nvme0n1   # début / fin du plus grand bloc libre : il doit faire ≥ 251 GiB
sgdisk -n 0:0:+1GiB   -t 0:ef00 -c 0:ARCH-ESP  /dev/nvme0n1
sgdisk -n 0:0:+250GiB -t 0:8300 -c 0:ARCH-ROOT /dev/nvme0n1
```
Puis :
```
partprobe /dev/nvme0n1
sfdisk --dump /dev/nvme0n1 > /root/apres.txt
grep '^/dev/' /root/avant.txt | grep -Fxv -f /root/apres.txt     # DOIT n'afficher RIEN
lsblk -o NAME,SIZE,PARTLABEL
```
**Contrôle** :
- la commande `grep` n'affiche **rien** (aucune partition existante n'a changé). Si elle affiche une ligne : **arrêt**, voir DEPANNAGE [P8] ;
- `lsblk` montre exactement 2 nouvelles partitions : ARCH-ESP de 1G (numéro `X`) et ARCH-ROOT de 250G (numéro `Y`).

### 3.2 Formater (UNIQUEMENT les deux nouvelles)

```
lsblk -o NAME,SIZE,PARTLABEL /dev/nvme0n1pX /dev/nvme0n1pY     # relire : ARCH-ESP 1G et ARCH-ROOT 250G ?
grep -i "$(lsblk -no PARTUUID /dev/nvme0n1pX)" /root/avant.txt  # DOIT n'afficher RIEN
grep -i "$(lsblk -no PARTUUID /dev/nvme0n1pY)" /root/avant.txt  # DOIT n'afficher RIEN
mkfs.fat -F 32 -n ARCHESP /dev/nvme0n1pX
mkfs.btrfs -L archroot /dev/nvme0n1pY
```
**Contrôle** : `lsblk -f` montre `vfat ARCHESP` sur X et `btrfs archroot` sur Y. Les partitions Windows sont inchangées.

### 3.3 Sous-volumes

```
mount /dev/nvme0n1pY /mnt
for s in @ @home @snapshots @var_log @pkg; do btrfs subvolume create /mnt/$s; done
btrfs subvolume list /mnt
umount /mnt
```
**Contrôle** : 5 lignes, de `path @` à `path @pkg`.

### 3.4 Monter l'arborescence

```
O=noatime,compress=zstd:1,discard=async
mount -o $O,subvol=@ /dev/nvme0n1pY /mnt
mkdir -p /mnt/home /mnt/.snapshots /mnt/var/log /mnt/var/cache/pacman/pkg /mnt/efi
mount -o $O,subvol=@home      /dev/nvme0n1pY /mnt/home
mount -o $O,subvol=@snapshots /dev/nvme0n1pY /mnt/.snapshots
mount -o $O,subvol=@var_log   /dev/nvme0n1pY /mnt/var/log
mount -o $O,subvol=@pkg       /dev/nvme0n1pY /mnt/var/cache/pacman/pkg
mount -o umask=0077 /dev/nvme0n1pX /mnt/efi
findmnt -R /mnt
```
**Contrôle** : 6 montages. `/mnt/efi` est **ARCHESP** (la nouvelle partition X), **jamais** l'ESP Windows.

---

## 4. Installer la base

```
pacstrap -K /mnt base linux linux-lts linux-firmware intel-ucode btrfs-progs grub efibootmgr os-prober networkmanager sudo git base-devel neovim nano snapper snap-pac grub-btrfs inotify-tools zram-generator openssh man-db
genfstab -U /mnt >> /mnt/etc/fstab
sed -i -E 's/(,)?subvolid=[0-9]+//' /mnt/etc/fstab
cat /mnt/etc/fstab
```
**Contrôle** :
- 5 lignes `btrfs` avec `subvol=/@`, `/@home`, `/@snapshots`, `/@var_log` et `/@pkg`, plus une ligne `vfat` pour `/efi` ;
- **aucun** `subvolid=` ;
- aucune ligne en double. Si `genfstab` a tourné deux fois : `nano /mnt/etc/fstab` et supprimer les doublons.

Copier le dépôt pour la suite (si tu l'avais cloné) :
```
cp -a /root/dualboot-arch /mnt/root/
```

---

## 5. Configurer dans le chroot

```
arch-chroot /mnt
```
Tout ce qui suit se tape **dans le chroot** (l'invite change). Remplacer `MONPC` et `moi` par tes valeurs.

**Heure, langue, clavier**
```
ln -sf /usr/share/zoneinfo/Africa/Porto-Novo /etc/localtime
hwclock --systohc
sed -i 's/^#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/; s/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo LANG=fr_FR.UTF-8 > /etc/locale.conf
echo KEYMAP=fr-latin9 > /etc/vconsole.conf
```

**Nom de machine et réseau**
```
echo MONPC > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 MONPC.localdomain MONPC\n' > /etc/hosts
systemctl enable NetworkManager
```

**Comptes**
```
passwd                                  # mot de passe root (le noter : utile en mode secours)
useradd -m -G wheel -s /bin/bash moi
passwd moi
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel      # doit afficher « parsed OK »
cp -a /root/dualboot-arch /home/moi/ && chown -R moi:moi /home/moi/dualboot-arch
```

**zram**
```
printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf
```

**initramfs** (les hooks `udev`, et non `systemd`, sont indispensables pour démarrer les snapshots)
```
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.orig
sed -i -E 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems grub-btrfs-overlayfs)/' /etc/mkinitcpio.conf
grep ^HOOKS /etc/mkinitcpio.conf
mkinitcpio -P
```
Contrôle : `mkinitcpio` génère 4 images sans `ERROR`. Les avertissements « Possibly missing firmware » sont sans gravité.

**GRUB**
```
findmnt /efi                            # DOIT être ARCHESP (lsblk -no LABEL $(findmnt -no SOURCE /efi))
sed -i -E 's/^#?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grep OS_PROBER /etc/default/grub        # GRUB_DISABLE_OS_PROBER=false
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH-GRUB
grub-mkconfig -o /boot/grub/grub.cfg
efibootmgr                              # une entrée ARCH-GRUB
```
Contrôle :
- `grub-install` se termine par `No error reported` ;
- `grub-mkconfig` liste `linux` et `linux-lts`. Windows peut manquer à ce stade : c'est normal, on corrige à l'étape 6.

**Sortir et redémarrer**
```
exit
umount -R /mnt
reboot
```

Ensuite : GUIDE.md, étape 6. À partir de là, les scripts `post/` reprennent normalement. S'ils plantent aussi : noter l'erreur dans JOURNAL.md, faire un snapshot (`sudo snapper -c root create -d "avant manuel"`, une fois l'étape 7 faite) et suivre la section correspondante de GUIDE.md commande par commande.
