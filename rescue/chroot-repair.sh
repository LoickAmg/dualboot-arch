#!/usr/bin/env bash
# rescue/chroot-repair.sh — niveau 3, depuis la clé live Arch : GRUB ne démarre plus.
#   ./chroot-repair.sh mount     monte l'arborescence sur $TARGET (comme à l'installation)
#   ./chroot-repair.sh shell     arch-chroot interactif
#   ./chroot-repair.sh grub      réinstalle GRUB sur l'ESP Linux + régénère grub.cfg
#   ./chroot-repair.sh umount    démonte tout
# Windows reste démarrable sans GRUB : touche F11 au démarrage (menu firmware MSI).
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root; require_uefi

do_mount() {
  local root esp; root="$(unique_dev "$ROOT_DEV")"; esp="$(unique_dev "$ESP_DEV")"
  mountpoint -q "$TARGET" && { info "$TARGET déjà monté."; return 0; }
  # monter n'écrit rien : exécuté même en DRY_RUN pour permettre l'inspection
  DRY_RUN=0 mount_layout "$root" "$esp" "$TARGET"
  findmnt -R "$TARGET"
}

do_grub() {
  do_mount
  [ "$(lsblk -no LABEL "$(findmnt -no SOURCE "$TARGET/efi")")" = "$ESP_FSLABEL" ] \
    || die "$TARGET/efi n'est pas l'ESP $ESP_FSLABEL : refus."
  banner_mode
  confirm_oui "Réinstaller GRUB ($BOOTLOADER_ID) sur l'ESP Linux et régénérer grub.cfg ?"
  run arch-chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id="$BOOTLOADER_ID"
  run arch-chroot "$TARGET" grub-mkconfig -o /boot/grub/grub.cfg
  [ "$DRY_RUN" = "0" ] && efibootmgr
  info "Si le firmware ignore l'entrée : relancer grub-install avec --removable (écrit EFI/BOOT/BOOTX64.EFI sur l'ESP Linux uniquement)."
}

case "${1:-}" in
  mount)  do_mount ;;
  shell)  do_mount; arch-chroot "$TARGET" ;;
  grub)   do_grub ;;
  umount) umount -R "$TARGET" ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
