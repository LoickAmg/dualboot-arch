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
[ -d "$TOP/@" ] || die "Sous-volume @ introuvable (une restauration précédente a-t-elle échoué ? voir docs/RECOVERY.md, « @ a disparu »)."
btrfs subvolume show "$SRC" >/dev/null 2>&1 || die "$SRC n'est pas un sous-volume Btrfs lisible."
[ -s "$SRC/etc/fstab" ] && ls "$SRC"/boot/vmlinuz-* >/dev/null 2>&1 \
  || die "Le snapshot $SNAP ne contient pas de système complet (fstab ou noyau absent)."

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

[ -e "$TOP/@broken-$STAMP" ] && die "@broken-$STAMP existe déjà : relancer dans une seconde."

if [ "$DRY_RUN" != "0" ]; then
  run mount -o remount,rw "$TOP"
  run mv "$TOP/@" "$TOP/@broken-$STAMP"
  run btrfs subvolume snapshot "$SRC" "$TOP/@"
  info "(simulation) Seul un montage en LECTURE SEULE a été fait pour lister les snapshots ; rien n'a été écrit."
  exit 0
fi

# --- Exécution réelle, en transaction : si la création du nouveau @ échoue, l'ancien est remis en place.
remettre_ancien() {
  warn "Échec : remise en place de l'ancien @."
  if [ ! -e "$TOP/@" ] && [ -d "$TOP/@broken-$STAMP" ]; then
    if mv "$TOP/@broken-$STAMP" "$TOP/@"; then
      warn "Ancien @ remis en place : le système est revenu à son état d'avant. Rien n'a été restauré."
    else
      warn "IMPOSSIBLE de remettre l'ancien @. À la main, depuis la live :"
      warn "  mount -o subvolid=5 $DEV /mnt/top && mv /mnt/top/@broken-$STAMP /mnt/top/@"
    fi
  fi
}
mount -o remount,rw "$TOP"
mv "$TOP/@" "$TOP/@broken-$STAMP"
if ! btrfs subvolume snapshot "$SRC" "$TOP/@"; then
  remettre_ancien; die "La copie du snapshot $SNAP a échoué (voir le message ci-dessus)."
fi
# Les sous-volumes imbriqués ne sont pas dans un snapshot : recréer le point de montage si besoin
[ -d "$TOP/@/.snapshots" ] || mkdir "$TOP/@/.snapshots"

# Contrôles du nouveau @ avant d'annoncer la réussite
ok=1
[ -s "$TOP/@/etc/fstab" ]                          || { warn "nouveau @ : /etc/fstab absent"; ok=0; }
grep -q 'subvol=/@[[:space:],]' "$TOP/@/etc/fstab" || { warn "nouveau @ : fstab sans subvol=/@"; ok=0; }
grep -q 'subvolid=' "$TOP/@/etc/fstab"             && { warn "nouveau @ : fstab contient subvolid="; ok=0; }
ls "$TOP"/@/boot/vmlinuz-* >/dev/null 2>&1        || { warn "nouveau @ : aucun noyau dans /boot"; ok=0; }
[ -f "$TOP/@/boot/grub/grub.cfg" ]                 || { warn "nouveau @ : /boot/grub/grub.cfg absent"; ok=0; }
if [ "$ok" = 0 ]; then
  btrfs subvolume delete "$TOP/@"
  remettre_ancien
  die "Le snapshot $SNAP n'est pas un système démarrable : restauration annulée, rien n'a changé."
fi
btrfs subvolume show "$TOP/@" | grep -E 'Name|Flags|Snapshot\(s\)' || true
echo "restore $SNAP le $STAMP (ancien @ = @broken-$STAMP)" >>"$TOP/@snapshots/RESTAURATIONS.txt"
sync
journal "restauration du snapshot $SNAP (ancien @ = @broken-$STAMP)" "OK, contrôles fstab/noyau/grub" "$SNAP"

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
