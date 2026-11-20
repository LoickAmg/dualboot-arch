#!/usr/bin/env bash
# maintenance/maj-systeme.sh — mise à jour encadrée (root) :
#   1. actualités Arch non lues   2. snapshot nommé   3. pacman -Syu
#   4. .pacnew et orphelins (liste seulement)   5. noyaux / initramfs / GRUB
#   sudo DRY_RUN=0 maj-systeme
# AUR : paru/yay seulement, PKGBUILD lus, jamais dans ce script.
SELF="$(readlink -f "$0")"
# shellcheck source=../lib/common.sh
. "$(dirname "$SELF")/../lib/common.sh"

require_root
banner_mode

title "1. Actualités Arch"
if command -v informant >/dev/null; then
  if ! informant check; then
    informant list --unread || true
    warn "Actualités non lues : les lire (informant read) et appliquer toute intervention manuelle AVANT de continuer."
    confirm_oui "Les actualités ont été lues et traitées ?"
  fi
else
  warn "informant absent : lire https://archlinux.org/news/ avant de continuer."
  confirm_oui "Les actualités Arch ont été lues ?"
fi

title "2. Snapshot avant mise à jour"
if [ "$DRY_RUN" = "0" ]; then
  num="$(snapper -c root create -d "avant maj $(date +%F)" -c number --print-number)"
  info "Snapshot n° $num"
else
  run snapper -c root create -d "avant maj $(date +%F)" -c number --print-number
fi

title "3. Mise à jour complète (jamais -Sy seul)"
run pacman -Syu

title "4. Fichiers .pacnew et orphelins (à traiter à la main)"
pacdiff -o 2>/dev/null || true
orph="$(pacman -Qtdq 2>/dev/null || true)"
[ -n "$orph" ] && { echo "Orphelins :"; printf '  %s\n' "$orph"; echo "Supprimer seulement après relecture : pacman -Rns <paquet>"; }

title "5. Noyaux, initramfs, GRUB"
need_grub=0
for k in /boot/vmlinuz-*; do
  [ -e "$k" ] || continue
  n="${k#/boot/vmlinuz-}"
  [ -f "/boot/initramfs-$n.img" ] && echo "OK  $n" || { warn "initramfs manquant pour $n → mkinitcpio -p $n"; }
  grep -q "vmlinuz-$n" /boot/grub/grub.cfg || need_grub=1
done
for must in linux linux-lts; do [ -e "/boot/vmlinuz-$must" ] || warn "Noyau de secours $must ABSENT."; done
if [ "$need_grub" = "1" ]; then run grub-mkconfig -o /boot/grub/grub.cfg; else info "grub.cfg connaît tous les noyaux."; fi
journal "maj-systeme : pacman -Syu" "voir sortie" "${num:--}"
