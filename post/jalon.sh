#!/usr/bin/env bash
# post/jalon.sh NN "description" — crée un snapshot de jalon PERMANENT.
# Sans algorithme de nettoyage : snapper-cleanup ne le supprime jamais.
#   sudo DRY_RUN=0 ./post/jalon.sh 02 "pre-cachy"
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root
NN="${1:?Usage : $0 NN \"description\"}"; DESC="${2:?description manquante}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || die "NN doit faire 2 chiffres (00 à 06)."
jalon_existe "$NN" && die "Le jalon $NN existe déjà (snapper -c root list)."
banner_mode
LABEL="JALON $NN - $DESC"
if [ "$DRY_RUN" = "0" ]; then
  num="$(snapper -c root create -d "$LABEL" --print-number)"
  info "Jalon créé : n° $num ($LABEL)"
  journal "jalon : $LABEL" "créé" "$num"
  run grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
else
  run snapper -c root create -d "$LABEL" --print-number
fi
