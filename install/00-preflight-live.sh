#!/usr/bin/env bash
# install/00-preflight-live.sh — phase 1, depuis la clé live Arch.
#
#   ./00-preflight-live.sh            LECTURE SEULE : état machine + disque, rapport
#   ./00-preflight-live.sh backup     sauvegarde GPT + copie de l'ESP Windows vers BACKUP_DIR
#                                     (le NVMe n'est lu qu'en lecture seule ; écrit sur le support externe)
set -uo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"
set +e   # un contrôle qui échoue ne doit pas interrompre le rapport

ESP_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

report() {
  title "Firmware";   [ -d /sys/firmware/efi ] && echo "UEFI OK" || echo "PAS EN UEFI : arrêter ici"
  [ -r /sys/firmware/efi/efivars ] && echo "efivars accessibles"
  echo -n "Secure Boot : "; (od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | awk '{print ($NF==1)?"ACTIVÉ (le désactiver)":"désactivé"}') || echo "inconnu"
  title "Machine";    dmidecode -s system-product-name 2>/dev/null; dmidecode -s bios-version 2>/dev/null
  title "CPU";        lscpu | grep -E 'Model name|Architecture'
  /lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -E 'x86-64-v[234]'
  title "RAM";        free -h | head -2
  title "Disques";    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,PARTUUID,MOUNTPOINTS
  title "Table GPT de $DISK"; sgdisk -p "$DISK"
  title "Espace libre (MiB)"; parted -s "$DISK" unit MiB print free
  title "Plus grand bloc libre (secteurs)"
  echo "début : $(sgdisk -F "$DISK" 2>/dev/null | tail -1)  fin : $(sgdisk -E "$DISK" 2>/dev/null | tail -1)  taille secteur : $(blockdev --getss "$DISK") o"
  title "Partitions ESP (type EF00)"
  lsblk -rno PATH,PARTTYPE,SIZE,FSTYPE,LABEL "$DISK" | awk -v g="$ESP_GUID" 'tolower($2)==g {print}'
  title "Entrées UEFI"; efibootmgr -v
  title "BitLocker ?"; blkid | grep -i bitlocker || echo "aucun détecté"
  title "GPU";         lspci -nnk | grep -EA3 'VGA|3D|Display'
  title "Réseau";      ping -c1 -W3 archlinux.org >/dev/null && echo "réseau OK" || echo "pas de réseau"
  title "À contrôler"
  cat <<'EOF'
  [ ] NVMe visible            [ ] une seule ESP Windows (EF00) identifiée
  [ ] >= 250 Go libres contigus (bloc libre ci-dessus)   [ ] pas de BitLocker
  [ ] Secure Boot désactivé   [ ] réseau OK
  [ ] noter dans docs/HARDWARE.md : modèle, CPU, niveau x86-64, PARTUUID des partitions Windows
  Ensuite : ./00-preflight-live.sh backup   (DRY_RUN=0)
EOF
}

backup() {
  require_root; require_set BACKUP_DIR
  [ -d "$BACKUP_DIR" ] || die "BACKUP_DIR n'existe pas : $BACKUP_DIR (monter le support externe)"
  local stamp out win_esp mnt n
  stamp="$(date +%Y%m%d-%H%M%S)"; out="$BACKUP_DIR/preflight-$stamp"
  run mkdir -p "$out"
  info "Rapport complet"
  run_sh "bash '$0' > '$out/rapport.txt' 2>&1"
  info "Table de partitions (binaire sgdisk + texte sfdisk)"
  run sgdisk --backup="$out/$(basename "$DISK")-gpt.bak" "$DISK"
  run_sh "sfdisk --dump '$DISK' > '$out/$(basename "$DISK")-sfdisk.txt'"
  mapfile -t win_esp < <(lsblk -rno PATH,PARTTYPE "$DISK" | awk -v g="$ESP_GUID" 'tolower($2)==g {print $1}')
  n=${#win_esp[@]}
  [ "$n" -eq 1 ] || { warn "$n ESP trouvées : copie de l'ESP Windows ignorée, à faire à la main."; return 0; }
  info "Copie de l'ESP Windows ${win_esp[0]} en LECTURE SEULE"
  mnt="/tmp/winesp-ro"
  run mkdir -p "$mnt"
  run mount -o ro "${win_esp[0]}" "$mnt"
  if [ "$DRY_RUN" = "0" ] && [ ! -d "$mnt/EFI/Microsoft" ]; then warn "Pas de EFI/Microsoft sur ${win_esp[0]} : est-ce bien l'ESP Windows ?"; fi
  run cp -r "$mnt/EFI" "$out/esp-windows-EFI"
  run umount "$mnt"
  run_sh "cd '$out' && find . -type f -exec sha256sum {} + > SHA256SUMS"
  journal "sauvegarde GPT + ESP Windows vers $out" "OK"
  info "Terminé. Vérifier le contenu de $out avant de passer à la phase 2."
}

case "${1:-report}" in
  report) report ;;
  backup) banner_mode; backup ;;
  *) echo "Usage : $0 [report|backup]"; exit 2 ;;
esac
