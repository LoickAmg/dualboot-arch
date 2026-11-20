#!/usr/bin/env bash
# post/70-hyprland.sh — phase 7.
#   packages    (root)        paquets Hyprland + session de secours sway
#   user-setup  (utilisateur) variables uwsm, lancement depuis tty1, agent polkit
#
# Doc vérifiée le 2026-11-20 (wiki.hypr.land, version 0.57.0 ; Arch fournit 0.57.2) :
#  - la configuration est en Lua : ~/.config/hypr/hyprland.lua ; Hyprland génère un exemple
#    au premier lancement. Ce script n'écrit PAS de configuration Hyprland.
#  - avec uwsm : HYPR* et AQ_* dans ~/.config/uwsm/env-hyprland, le reste dans ~/.config/uwsm/env
#  - AQ_DRM_DEVICES : liste séparée par « : », d'où les liens udev de 50-hardware-laptop.sh udev
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

HYPR_PKGS="hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent uwsm libnewt
waybar kitty hyprlock hypridle hyprpaper mako fuzzel brightnessctl grim slurp wl-clipboard
ttf-jetbrains-mono-nerd qt5ct qt6ct nwg-look"
RESCUE_PKGS="sway foot"   # session de secours : config sway par défaut (/etc/sway/config)

do_packages() {
  require_root
  jalon_existe 04 || die "Jalon 04 absent : sudo DRY_RUN=0 ./post/jalon.sh 04 \"pre-hyprland\""
  [ -e /dev/dri/intel-igpu ] || warn "/dev/dri/intel-igpu absent : lancer d'abord « post/50-hardware-laptop.sh udev »."
  banner_mode
  # shellcheck disable=SC2086
  printf '  %s\n' $HYPR_PKGS $RESCUE_PKGS
  confirm_oui "Installer Hyprland et la session de secours sway ?"
  # shellcheck disable=SC2086
  run pacman -S --needed $HYPR_PKGS $RESCUE_PKGS
  journal "paquets Hyprland + sway (secours)" "installé"
  info "Ensuite, en tant que $USERNAME_NEW (sans sudo) : post/70-hyprland.sh user-setup"
}

do_user_setup() {
  [ "$(id -u)" -ne 0 ] || die "À lancer en utilisateur normal, pas en root."
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" devs="/dev/dri/intel-igpu"
  [ -e /dev/dri/nvidia-dgpu ] && devs="$devs:/dev/dri/nvidia-dgpu"
  banner_mode

  # iGPU en premier = rendu principal (batterie). dGPU incluse : une sortie HDMI/USB-C
  # câblée sur la NVIDIA ne fonctionne que si sa carte figure dans la liste.
  write_file "$cfg/uwsm/env-hyprland" <<EOF
# Variables HYPR* et AQ_* (lues par uwsm). Format : export CLE=VALEUR
export AQ_DRM_DEVICES="$devs"
EOF
  write_file "$cfg/uwsm/env" <<EOF
# Thème, curseur, toolkits. Ne PAS forcer ici les variables NVIDIA (portable hybride :
# la dGPU sert en offload via prime-run).
export XCURSOR_SIZE=24
export QT_QPA_PLATFORMTHEME=qt6ct
EOF

  local prof="$HOME/.bash_profile" marker="# dualboot-arch: uwsm tty1"
  if grep -qF "$marker" "$prof" 2>/dev/null; then
    info "Lancement uwsm déjà présent dans $prof."
  else
    backup_file "$prof"
    run_sh "cat >> '$prof' <<'EOF'

$marker — Hyprland seulement sur tty1 ; tty2 reste un shell de secours (lancer « sway » à la main)
if [ \"\$(tty)\" = /dev/tty1 ] && uwsm check may-start; then
    exec uwsm start hyprland.desktop
fi
EOF"
  fi
  if systemctl --user cat hyprpolkitagent.service >/dev/null 2>&1; then
    run systemctl --user enable hyprpolkitagent.service
  else
    warn "Unité utilisateur hyprpolkitagent.service introuvable : voir la page hyprpolkitagent du wiki Hyprland."
  fi
  cat <<'EOF'

Contrôle phase 7 :
  1. Se déconnecter, se connecter sur tty1 → Hyprland démarre (config d'exemple générée).
  2. Ctrl+Alt+F2 → connexion texte OK ; « sway » s'y lance (session de secours).
     Si sway refuse le pilote NVIDIA : « sway --unsupported-gpu » (à vérifier, voir DECISIONS.md).
  3. Mettre ~/.config/hypr sous Git (dépôt dotfiles séparé, stow).
  4. sudo DRY_RUN=0 ./post/jalon.sh 05 "hyprland-ok (secours inclus)"
Quitter Hyprland avec « uwsm stop », pas avec le dispatcher exit.
EOF
}

case "${1:-}" in
  packages) do_packages ;; user-setup) do_user_setup ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
