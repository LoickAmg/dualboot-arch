#!/usr/bin/env bash
# post/80-maintenance.sh — phase 9 (root). Outils et timers de maintenance.
#   - informant   : bloque pacman tant qu'une actualité Arch n'est pas lue
#   - paccache    : purge hebdomadaire du cache (garde 3 versions)
#   - btrfs scrub : vérification mensuelle des sommes de contrôle de /
#   - smartd      : surveillance SMART du NVMe
# fstrim.timer n'est pas activé : discard=async est déjà dans les options de montage.
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root
banner_mode
PKGS="pacman-contrib informant smartmontools"
confirm_oui "Installer $PKGS et activer paccache.timer, btrfs-scrub@-.timer, smartd ?"
# shellcheck disable=SC2086
run pacman -S --needed $PKGS
run systemctl enable --now paccache.timer smartd.service
if systemctl cat btrfs-scrub@.timer >/dev/null 2>&1; then
  run systemctl enable --now btrfs-scrub@-.timer      # « - » = chemin « / » échappé
else
  warn "btrfs-scrub@.timer absent de btrfs-progs : planifier « btrfs scrub start / » autrement."
fi
run ln -sf "$REPO_DIR/maintenance/maj-systeme.sh" /usr/local/bin/maj-systeme
journal "timers maintenance (paccache, scrub, smartd) + informant" "activés"
info "Mise à jour du système désormais : sudo DRY_RUN=0 maj-systeme"
