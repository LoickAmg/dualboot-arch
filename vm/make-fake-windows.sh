#!/usr/bin/env bash
# vm/make-fake-windows.sh — phase 0 : prépare un disque de VM qui imite le vrai :
#   ESP 100 MiB (FAT32, EFI/Microsoft/Boot/bootmgfw.efi factice) + MSR 16 MiB
#   + « C: » NTFS 40 GiB + récupération 700 MiB + espace libre pour Linux.
# REFUSE de tourner hors d'une machine virtuelle.
#   DRY_RUN=0 CONFIG_FILE=../config.vm.env ./make-fake-windows.sh
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

require_root; require_uefi
virt="$(systemd-detect-virt 2>/dev/null || true)"
prod="$(dmidecode -s system-product-name 2>/dev/null || true)"
case "$virt" in
  none|"") die "Pas dans une VM (systemd-detect-virt=$virt, machine=$prod). Refus." ;;
esac
case "$prod" in *Cyborg*|*MSI*) die "Matériel MSI détecté ($prod) : refus." ;; esac
info "VM détectée : $virt ($prod)"
[ -b "$DISK" ] || die "$DISK absent (disque NVMe virtuel non configuré ?)"
lsblk -rno TYPE "$DISK" | grep part >/dev/null && die "$DISK a déjà des partitions : repartir d'un disque virtuel vierge."

banner_mode
confirm_oui "Créer la fausse table Windows sur le disque VIRTUEL $DISK ?"
run sgdisk -o "$DISK"
run sgdisk -n 1:0:+100MiB -t 1:ef00 -c "1:EFI system partition" "$DISK"
run sgdisk -n 2:0:+16MiB  -t 2:0c01 -c "2:Microsoft reserved partition" "$DISK"
run sgdisk -n 3:0:+40GiB  -t 3:0700 -c "3:Basic data partition" "$DISK"
run sgdisk -n 4:0:+700MiB -t 4:2700 -c "4:Recovery" "$DISK"
run partprobe "$DISK"; [ "$DRY_RUN" = "0" ] && udevadm settle
p() { lsblk -rno PATH "$DISK" | sed -n "$(( $1 + 1 ))p"; }
run mkfs.fat -F 32 "$(p 1)"
run mkfs.ntfs -Q -L Windows "$(p 3)"
run mkfs.ntfs -Q -L Recovery "$(p 4)"
run mkdir -p /tmp/fakeesp
run mount "$(p 1)" /tmp/fakeesp
run mkdir -p /tmp/fakeesp/EFI/Microsoft/Boot
run_sh "echo 'faux chargeur Windows (VM de test)' > /tmp/fakeesp/EFI/Microsoft/Boot/bootmgfw.efi"
run umount /tmp/fakeesp
[ "$DRY_RUN" = "0" ] && { sgdisk -p "$DISK"; lsblk -f "$DISK"; }
info "Disque prêt. Suite : install/00-preflight-live.sh avec CONFIG_FILE=config.vm.env"
