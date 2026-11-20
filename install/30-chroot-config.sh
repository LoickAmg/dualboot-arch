#!/usr/bin/env bash
# install/30-chroot-config.sh — phase 3b, DANS le chroot :
#   arch-chroot /mnt /root/dualboot-arch/install/30-chroot-config.sh
# Les mots de passe sont saisis par l'utilisateur au clavier (passwd), jamais stockés.
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root
require_set HOSTNAME_NEW USERNAME_NEW KEYMAP TIMEZONE
[ -f "/usr/share/zoneinfo/$TIMEZONE" ] || die "Fuseau inconnu : $TIMEZONE"
mountpoint -q /efi || die "/efi n'est pas monté dans le chroot."
banner_mode

title "Heure et fuseau"
run ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
run hwclock --systohc          # horloge matérielle en UTC : Windows doit avoir RealTimeIsUniversal=1

title "Locales"
backup_file /etc/locale.gen
for l in $LOCALES; do run sed -i "s/^#\s*\(${l//./\\.} UTF-8\)/\1/" /etc/locale.gen; done
run locale-gen
write_file /etc/locale.conf <<EOF
LANG=$LANG_DEFAULT
EOF
write_file /etc/vconsole.conf <<EOF
KEYMAP=$KEYMAP
EOF

title "Réseau et nom de machine"
write_file /etc/hostname <<EOF
$HOSTNAME_NEW
EOF
write_file /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME_NEW.localdomain $HOSTNAME_NEW
EOF
run systemctl enable NetworkManager.service

title "Comptes"
info "Mot de passe root (utile pour le shell de secours systemd) :"
run passwd
if id "$USERNAME_NEW" >/dev/null 2>&1; then warn "Utilisateur $USERNAME_NEW déjà présent."
else run useradd -m -G wheel -s /bin/bash "$USERNAME_NEW"; fi
info "Mot de passe de $USERNAME_NEW :"
run passwd "$USERNAME_NEW"
write_file /etc/sudoers.d/10-wheel 0440 <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
[ "$DRY_RUN" = "0" ] && { visudo -cf /etc/sudoers.d/10-wheel || die "sudoers invalide"; }

title "Copie du dépôt dans le dossier de l'utilisateur"
# Après le premier démarrage, tout se lance depuis ~/dualboot-arch (git pull possible).
if [ -e "/home/$USERNAME_NEW/dualboot-arch" ]; then
  warn "/home/$USERNAME_NEW/dualboot-arch existe déjà : copie ignorée."
else
  run cp -a "$REPO_DIR" "/home/$USERNAME_NEW/dualboot-arch"
fi
run chown -R "$USERNAME_NEW:$USERNAME_NEW" "/home/$USERNAME_NEW/dualboot-arch"

title "zram (pas de partition swap, pas d'hibernation)"
write_file /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF

title "initramfs"
# Hooks « udev » (busybox) et non « systemd » : les hooks d'exécution mkinitcpio,
# dont grub-btrfs-overlayfs, sont des scripts busybox (voir docs/DECISIONS.md).
[ -f /usr/lib/initcpio/install/grub-btrfs-overlayfs ] || [ -f /etc/initcpio/install/grub-btrfs-overlayfs ] \
  || die "Hook grub-btrfs-overlayfs introuvable (paquet grub-btrfs installé ?)."
grep -n '^HOOKS=' /etc/mkinitcpio.conf || true
backup_file /etc/mkinitcpio.conf
run sed -i -E "s/^HOOKS=.*/HOOKS=(${MKINIT_HOOKS})/" /etc/mkinitcpio.conf
[ "$DRY_RUN" = "0" ] && grep -n '^HOOKS=' /etc/mkinitcpio.conf
run mkinitcpio -P

title "GRUB (ESP Linux /efi uniquement ; l'ESP Windows n'est pas montée)"
backup_file /etc/default/grub
if grep -q '^#\?GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
  run sed -i -E 's/^#?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
  run_sh "echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
fi
info "Sur l'ESP Linux : $(findmnt -no SOURCE /efi) ($(lsblk -no LABEL "$(findmnt -no SOURCE /efi)"))"
[ "$(lsblk -no LABEL "$(findmnt -no SOURCE /efi)")" = "$ESP_FSLABEL" ] || die "/efi n'est pas l'ESP $ESP_FSLABEL : refus d'installer GRUB."
confirm_oui "Installer GRUB sur /efi (bootloader-id $BOOTLOADER_ID) et créer l'entrée UEFI ?"
run grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id="$BOOTLOADER_ID"
run grub-mkconfig -o /boot/grub/grub.cfg
if [ "$DRY_RUN" = "0" ]; then
  grep -q 'menuentry .*Windows' /boot/grub/grub.cfg \
    && info "Windows détecté par os-prober." \
    || warn "Windows non détecté dans le chroot (fréquent) : relancer « grub-mkconfig -o /boot/grub/grub.cfg » après le premier démarrage."
  efibootmgr | grep -i "$BOOTLOADER_ID" || warn "Entrée UEFI $BOOTLOADER_ID non visible : voir docs/RECOVERY.md (option --removable)."
fi
journal "configuration chroot + GRUB" "OK"

cat <<EOF

Point de contrôle phase 3 :
  exit ; umount -R $TARGET ; reboot
  1. Arch démarre via GRUB      2. Windows démarre via GRUB
  3. Windows démarre via F11 (menu firmware MSI), sans GRUB
Ne pas créer le jalon 00 avant la phase 4.
EOF
