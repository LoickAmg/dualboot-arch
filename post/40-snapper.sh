#!/usr/bin/env bash
# post/40-snapper.sh — phase 4, dans l'Arch installé (root).
# Config snapper « root » sur le layout plat : @snapshots monté sur /.snapshots.
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root
[ "$(findmnt -no FSTYPE /)" = "btrfs" ] || die "/ n'est pas en Btrfs."
findmnt -no OPTIONS / | grep 'subvol=/@\(,\|$\)' >/dev/null || die "/ n'est pas le sous-volume @."
grep -Eq 'subvol=/@snapshots(,|[[:space:]])' /etc/fstab || die "Pas d'entrée @snapshots dans /etc/fstab."
snapper list-configs 2>/dev/null | grep -E '^root\b' >/dev/null && die "La config snapper « root » existe déjà."
banner_mode

title "Création de la config root"
# snapper create-config veut créer lui-même /.snapshots : on lui laisse la place,
# puis on remplace son sous-volume imbriqué par le montage de @snapshots.
if mountpoint -q /.snapshots; then run umount /.snapshots; fi
[ "$DRY_RUN" = "0" ] && [ -n "$(ls -A /.snapshots 2>/dev/null)" ] && die "/.snapshots démonté mais non vide : vérifier à la main."
[ -d /.snapshots ] && run rmdir /.snapshots     # rmdir : refuse tout dossier non vide
run snapper -c root create-config /
confirm_oui "Supprimer le sous-volume imbriqué /.snapshots créé par snapper (vide) pour monter @snapshots à sa place ?"
run btrfs subvolume delete /.snapshots
run mkdir /.snapshots
run mount /.snapshots
run chmod 750 /.snapshots
[ "$DRY_RUN" = "0" ] && findmnt /.snapshots

title "Limites (brief §3.3)"
run snapper -c root set-config \
  TIMELINE_CREATE=yes TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 \
  TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_YEARLY=0 NUMBER_LIMIT=15 NUMBER_LIMIT_IMPORTANT=10
[ "$USERNAME_NEW" != "A_COMPLETER" ] && run snapper -c root set-config "ALLOW_USERS=$USERNAME_NEW"

title "Services"
run systemctl enable --now snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service
run grub-mkconfig -o /boot/grub/grub.cfg
journal "snapper config root + timers + grub-btrfsd" "OK"

cat <<'EOF'

Point de contrôle phase 4 (dans cet ordre) :
  1. sudo pacman -S --needed tree      → snap-pac doit créer 2 snapshots (snapper list)
  2. Redémarrer, menu GRUB « Arch Linux snapshots » : démarrer un snapshot (lecture seule + overlay)
  3. Depuis la clé live : rescue/restore-snapshot.sh (test réel, voir docs/RECOVERY.md)
  4. Seulement alors : sudo DRY_RUN=0 ./post/jalon.sh 00 "arch-base valide (Arch + Windows demarrent)"
EOF
