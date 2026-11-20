#!/usr/bin/env bash
# install/20-base-install.sh — phase 3a, depuis la clé live, après « 10-partition.sh mount ».
# pacstrap + fstab + copie du dépôt dans le futur système.
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root; require_uefi
mountpoint -q "$TARGET"     || die "$TARGET n'est pas monté (lancer 10-partition.sh mount)."
mountpoint -q "$TARGET/efi" || die "$TARGET/efi n'est pas monté."
findmnt -no OPTIONS "$TARGET" | grep 'subvol=/@\(,\|$\)' >/dev/null || die "$TARGET n'est pas le sous-volume @."
banner_mode

title "Paquets"
# shellcheck disable=SC2086
printf '  %s\n' $BASE_PACKAGES
confirm_oui "Lancer pacstrap sur $TARGET ?"
# shellcheck disable=SC2086
run pacstrap -K "$TARGET" $BASE_PACKAGES

title "fstab"
[ "$DRY_RUN" = "0" ] && grep -Eq '^[^#[:space:]]' "$TARGET/etc/fstab" 2>/dev/null \
  && die "$TARGET/etc/fstab contient déjà des entrées : ne pas l'écraser à l'aveugle."
run_sh "genfstab -U '$TARGET' >> '$TARGET/etc/fstab'"
# Le brief impose subvol= seul : genfstab ajoute subvolid=, qui casserait un retour arrière de @.
run sed -i -E 's/(,)?subvolid=[0-9]+//' "$TARGET/etc/fstab"
if [ "$DRY_RUN" = "0" ]; then
  cat "$TARGET/etc/fstab"
  grep -q 'subvolid=' "$TARGET/etc/fstab" && die "subvolid= encore présent dans fstab."
  for s in /@ /@home /@snapshots /@var_log /@pkg; do
    grep -Eq "subvol=${s}(,|[[:space:]])" "$TARGET/etc/fstab" || die "Entrée subvol=$s absente de fstab."
  done
  info "fstab : 5 sous-volumes présents, aucun subvolid=."
fi

title "Copie du dépôt dans le système installé"
run mkdir -p "$TARGET/root/dualboot-arch"
run cp -a "$REPO_DIR/." "$TARGET/root/dualboot-arch/"
journal "pacstrap + genfstab" "OK"
info "Suite : arch-chroot $TARGET /root/dualboot-arch/install/30-chroot-config.sh"
