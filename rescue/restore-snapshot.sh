#!/usr/bin/env bash
# rescue/restore-snapshot.sh — retour arrière PERMANENT de @ (niveau 2), depuis la clé live Arch.
#   ./restore-snapshot.sh              liste les snapshots (lecture seule)
#   DRY_RUN=0 ./restore-snapshot.sh N  remplace @ par une copie inscriptible du snapshot N
# L'ancien @ est renommé @broken-DATE (rien n'est supprimé). @home, @snapshots, @var_log
# et @pkg ne sont pas touchés.
# Version autonome de secours (sans le dépôt) : voir docs/RECOVERY.md.
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root
DEV="$(unique_dev "$ROOT_DEV")"
TOP=/mnt/top

[[ "$(findmnt -no SOURCE /)" == "$DEV"* ]] && die "$DEV est monté comme / : lancer depuis la clé live, pas depuis le système."
findmnt "$TOP" >/dev/null && die "$TOP est déjà monté."
mkdir -p "$TOP"
mount -o subvolid=5,ro "$DEV" "$TOP"
trap 'umount "$TOP" 2>/dev/null || true' EXIT

list() {
  title "Snapshots de @ (n° / date / description)"
  local d n
  for d in "$TOP"/@snapshots/*/; do
    n="$(basename "$d")"
    [ -f "$d/info.xml" ] || continue
    printf '%5s  %s  %s\n' "$n" \
      "$(sed -n 's:.*<date>\(.*\)</date>.*:\1:p' "$d/info.xml")" \
      "$(sed -n 's:.*<description>\(.*\)</description>.*:\1:p' "$d/info.xml")"
  done | sort -n
}

if [ -z "${1:-}" ]; then list; echo; echo "Usage : DRY_RUN=0 $0 <numéro>"; exit 0; fi

SNAP="$1"
[[ "$SNAP" =~ ^[0-9]+$ ]] || die "Numéro invalide : $SNAP"
SRC="$TOP/@snapshots/$SNAP/snapshot"
[ -d "$SRC" ] || die "Snapshot $SNAP introuvable dans @snapshots."
[ -d "$TOP/@" ] || die "Sous-volume @ introuvable."

def="$(btrfs subvolume get-default "$TOP")"
case "$def" in *"ID 5 "*) ;; *) warn "Sous-volume par défaut ≠ 5 ($def) : GRUB et fstab utilisent subvol=@, vérifier à la main." ;; esac

banner_mode
title "Snapshot cible"
cat "$TOP/@snapshots/$SNAP/info.xml"
STAMP="$(date +%Y%m%d-%H%M%S)"
echo
echo "  @            → @broken-$STAMP   (conservé)"
echo "  snapshot $SNAP → nouveau @        (copie inscriptible)"
confirm_oui "Restaurer le snapshot $SNAP comme système (@) ?"

run mount -o remount,rw "$TOP"
run mv "$TOP/@" "$TOP/@broken-$STAMP"
run btrfs subvolume snapshot "$SRC" "$TOP/@"
# Les sous-volumes imbriqués ne sont pas dans un snapshot : recréer le point de montage si besoin
[ "$DRY_RUN" = "0" ] && [ ! -d "$TOP/@/.snapshots" ] && mkdir "$TOP/@/.snapshots"
if [ "$DRY_RUN" = "0" ]; then
  btrfs subvolume show "$TOP/@" | grep -E 'Name|Flags|Snapshot\(s\)' || true
  echo "restore $SNAP le $STAMP (ancien @ = @broken-$STAMP)" >>"$TOP/@snapshots/RESTAURATIONS.txt"
fi

cat <<EOF

Restauré. Redémarrer sans la clé.
Après le démarrage :
  sudo grub-mkconfig -o /boot/grub/grub.cfg     (menu des snapshots à jour)
  snapper -c root list                           (les snapshots sont toujours là)
  findmnt /home /.snapshots /var/log             (montages OK)
Noter la restauration dans docs/JOURNAL.md.
Supprimer @broken-$STAMP plus tard seulement, une fois le système validé :
  (live) mount -o subvolid=5 $DEV /mnt/top ; btrfs subvolume delete /mnt/top/@broken-$STAMP
EOF
