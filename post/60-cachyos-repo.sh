#!/usr/bin/env bash
# post/60-cachyos-repo.sh — phase 6 (root). Surcouche dépôts CachyOS, par étapes :
#   check     LECTURE SEULE : niveau x86-64, jalon 02, état de pacman.conf
#   prepare   télécharge l'archive officielle dans un dossier dédié, l'extrait, AFFICHE le script
#   run       exécute le script officiel déjà lu (confirmation OUI)
#   kernel    installe linux-cachyos + headers + module NVIDIA open précompilé (garde linux et linux-lts)
#   remove    retrait officiel des dépôts (cachyos-repo.sh --remove)
# Source : https://wiki.cachyos.org/features/optimized_repos/ (lue le 2026-11-20)
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

URL="https://mirror.cachyos.org/cachyos-repo.tar.xz"
WORK="/root/cachyos-repo-audit"
KERNEL_PKGS="linux-cachyos linux-cachyos-headers linux-cachyos-nvidia-open"

do_check() {
  title "Niveau x86-64 (Intel 12e gen : v3 attendu, pas v4 — AVX-512 désactivé)"
  /lib/ld-linux-x86-64.so.2 --help | grep -E 'x86-64-v[234]'
  title "Jalons"; jalon_existe 02 && echo "JALON 02 présent" || echo "JALON 02 ABSENT : sudo DRY_RUN=0 ./post/jalon.sh 02 \"pre-cachy\""
  title "Dépôts actuels"; grep -n '^\[' /etc/pacman.conf
  title "pacman installé"; pacman -Qi pacman | grep -E '^(Version|Packager)'
  return 0
}

do_prepare() {
  require_root; require_cmd curl tar sha256sum
  banner_mode
  local d; d="$WORK/$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$d"
  run curl -fL --proto '=https' "$URL" -o "$d/cachyos-repo.tar.xz"
  run tar -xvf "$d/cachyos-repo.tar.xz" -C "$d"
  [ "$DRY_RUN" = "0" ] || return 0
  ( cd "$d" && sha256sum cachyos-repo.tar.xz && find . -type f | sort )
  title "Contenu de cachyos-repo.sh (À LIRE EN ENTIER)"
  less "$d/cachyos-repo/cachyos-repo.sh"
  ln -sfn "$d" "$WORK/latest"
  cat <<EOF

Résumer à l'utilisateur, avant « run » :
  - ce que le script change dans /etc/pacman.conf (sauvegarde .bak d'après le wiki)
  - les clés importées (wiki : F3B607488DB35A47) et les paquets installés
    (cachyos-keyring, cachyos-mirrorlist, cachyos-v3-mirrorlist, …)
  - le remplacement de pacman par la version CachyOS (dépôt [cachyos]) et des paquets
    fondamentaux (glibc, etc.) lors du -Syu qui suit
  - le niveau choisi (v3 attendu sur ce CPU)
Fichiers : $d
EOF
}

do_run() {
  require_root
  jalon_existe 02 || die "Jalon 02 absent : sudo DRY_RUN=0 ./post/jalon.sh 02 \"pre-cachy\""
  local s="$WORK/latest/cachyos-repo/cachyos-repo.sh"
  [ -f "$s" ] || die "Lancer « prepare » d'abord (et lire le script)."
  banner_mode
  confirm_oui "Le script $s a-t-il été lu en entier et validé ? Il modifie /etc/pacman.conf et remplace pacman."
  run bash -c "cd '$(dirname "$s")' && ./cachyos-repo.sh"
  [ "$DRY_RUN" = "0" ] && { grep -n '^\[' /etc/pacman.conf; pacman -Qi pacman | grep -E '^(Version|Packager)'; }
  journal "dépôts CachyOS ajoutés (script officiel)" "voir pacman.conf"
  info "Ensuite : pacman -Syu (complet), redémarrer, vérifier, puis « $0 kernel »."
}

do_kernel() {
  require_root
  local p; for p in $KERNEL_PKGS; do pacman -Si "$p" >/dev/null 2>&1 || die "Paquet $p introuvable dans les dépôts : vérifier son nom (pacman -Ss nvidia)."; done
  banner_mode
  confirm_oui "Installer $KERNEL_PKGS (linux et linux-lts restent installés) ?"
  # shellcheck disable=SC2086
  run pacman -S --needed $KERNEL_PKGS
  run grub-mkconfig -o /boot/grub/grub.cfg
  [ "$DRY_RUN" = "0" ] && ls -1 /boot/vmlinuz-* /boot/initramfs-*.img
  journal "noyau CachyOS + nvidia-open précompilé" "installé"
  cat <<'EOF'

Tester les TROIS noyaux, un démarrage chacun (GRUB > Advanced options) :
  linux, linux-lts, linux-cachyos  →  uname -r ; nvidia-smi ; prime-run glxinfo | grep renderer
Optionnel, un par un avec un snapshot entre chaque : cachyos-settings (lire « pacman -Ql » avant),
ananicy-cpp, scx. Puis : sudo DRY_RUN=0 ./post/jalon.sh 03 "post-cachy (3 noyaux OK)"
EOF
}

do_remove() {
  require_root
  local s="$WORK/latest/cachyos-repo/cachyos-repo.sh"
  [ -f "$s" ] || die "Script absent : lancer « prepare » (et le relire)."
  banner_mode
  confirm_oui "Retirer les dépôts CachyOS (script officiel --remove) ?"
  run bash -c "cd '$(dirname "$s")' && ./cachyos-repo.sh --remove"
  journal "retrait dépôts CachyOS" "fait"
}

case "${1:-check}" in
  check) do_check ;; prepare) do_prepare ;; run) do_run ;; kernel) do_kernel ;; remove) do_remove ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
