#!/usr/bin/env bash
# post/50-hardware-laptop.sh — phase 5 (root). Graphique hybride Intel + NVIDIA, audio, énergie.
#   check       LECTURE SEULE : GPU, PCI, état RTD3, modules
#   install     paquets (Intel, NVIDIA open pour linux + linux-lts, PipeWire, Bluetooth, énergie)
#   udev        liens stables /dev/dri/intel-igpu et /dev/dri/nvidia-dgpu (pour AQ_DRM_DEVICES)
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

# Doc vérifiée le 2026-11-20 (wiki.archlinux.org/title/NVIDIA) : Ada → nvidia-open (linux)
# et nvidia-open-lts (linux-lts). DRM modeset activé par défaut depuis nvidia-utils 560.35.03-5.
GPU_PKGS="mesa vulkan-intel intel-media-driver nvidia-open nvidia-open-lts nvidia-utils nvidia-prime mesa-utils vulkan-tools"
AUDIO_PKGS="pipewire pipewire-pulse wireplumber sof-firmware"
MISC_PKGS="bluez bluez-utils power-profiles-daemon"

pci_of() { lspci -D -d ::03xx | awk -v v="$1" 'tolower($0) ~ v {print $1; exit}'; }

do_check() {
  title "Contrôleurs graphiques"; lspci -D -nnk -d ::03xx
  local ig nv; ig="$(pci_of intel)"; nv="$(pci_of nvidia)"
  echo "iGPU Intel : ${ig:-non trouvé}   dGPU NVIDIA : ${nv:-non trouvé}"
  title "/dev/dri"; ls -l /dev/dri/by-path/ 2>/dev/null; ls -l /dev/dri/intel-igpu /dev/dri/nvidia-dgpu 2>/dev/null || true
  if [ -n "$nv" ]; then
    title "Énergie dGPU (RTD3)"
    echo "runtime_status : $(cat "/sys/bus/pci/devices/$nv/power/runtime_status" 2>/dev/null)  (suspended = éteinte)"
    cat "/proc/driver/nvidia/gpus/$nv/power" 2>/dev/null || echo "module nvidia non chargé"
    echo "modeset : $(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo '-')  (Y attendu)"
  fi
  title "Services"; systemctl is-enabled power-profiles-daemon bluetooth tlp 2>/dev/null || true
  command -v nvidia-smi >/dev/null && nvidia-smi -L
  return 0
}

do_install() {
  require_root
  jalon_existe 00 || die "Jalon 00 absent : terminer la phase 4 d'abord."
  systemctl is-enabled tlp >/dev/null 2>&1 && die "tlp est actif : ne pas l'utiliser avec power-profiles-daemon."
  banner_mode
  # shellcheck disable=SC2086
  { printf '  %s\n' $GPU_PKGS $AUDIO_PKGS $MISC_PKGS; }
  confirm_oui "Installer ces paquets (snap-pac fera un snapshot avant/après) ?"
  # shellcheck disable=SC2086
  run pacman -S --needed $GPU_PKGS $AUDIO_PKGS $MISC_PKGS
  run systemctl enable --now power-profiles-daemon.service bluetooth.service
  run grub-mkconfig -o /boot/grub/grub.cfg
  journal "pilotes Intel + NVIDIA open (linux, linux-lts), audio, bluetooth, ppd" "installé"
  cat <<'EOF'

Ne PAS définir __GLX_VENDOR_LIBRARY_NAME / GBM_BACKEND=nvidia-drm globalement (portable hybride).
Redémarrer, puis contrôler :
  nvidia-smi ; prime-run glxinfo | grep "OpenGL renderer" ; glxinfo | grep "OpenGL renderer" (Intel)
  post/50-hardware-laptop.sh check  → runtime_status = suspended quand la dGPU est inutilisée
  Sur Ampere et plus récent, RTD3 est actif par défaut (wiki PRIME) : rien à ajouter si « suspended ».
  Répéter nvidia-smi après avoir démarré sur linux-lts.
Puis : sudo DRY_RUN=0 ./post/jalon.sh 01 "arch-config (reseau, audio, pilotes OK)"
EOF
}

do_udev() {
  require_root
  local ig nv; ig="$(pci_of intel)"; nv="$(pci_of nvidia)"
  [ -n "$ig" ] || die "iGPU Intel introuvable."
  banner_mode
  {
    echo "# Liens stables vers les cartes DRM (les /dev/dri/cardN changent entre deux démarrages,"
    echo "# et les chemins by-path contiennent des « : », séparateur de AQ_DRM_DEVICES)."
    echo "KERNEL==\"card*\", KERNELS==\"$ig\", SUBSYSTEM==\"drm\", SUBSYSTEMS==\"pci\", SYMLINK+=\"dri/intel-igpu\""
    if [ -n "$nv" ]; then
      echo "KERNEL==\"card*\", KERNELS==\"$nv\", SUBSYSTEM==\"drm\", SUBSYSTEMS==\"pci\", SYMLINK+=\"dri/nvidia-dgpu\""
    fi
  } | write_file /etc/udev/rules.d/61-dri-stable-names.rules
  run udevadm control --reload
  run udevadm trigger --subsystem-match=drm
  [ "$DRY_RUN" = "0" ] && { sleep 1; ls -l /dev/dri/intel-igpu /dev/dri/nvidia-dgpu 2>&1; }
  journal "règle udev liens DRM stables" "OK"
}

case "${1:-check}" in
  check) do_check ;; install) do_install ;; udev) do_udev ;;
  *) sed -n '2,6p' "$0"; exit 2 ;;
esac
