#!/usr/bin/env bash
# install/10-partition.sh — phase 2, depuis la clé live. DRY_RUN=1 par défaut.
#
# Étapes, à lancer une par une, chacune avec sa propre confirmation :
#   plan      LECTURE SEULE : calcule les secteurs dans le plus grand bloc libre, écrit le plan
#   create    ajoute les 2 partitions (sgdisk), puis vérifie que les partitions existantes sont intactes
#   format    mkfs.fat sur la nouvelle ESP, mkfs.btrfs sur la nouvelle racine
#   subvols   crée @ @home @snapshots @var_log @pkg
#   mount     monte l'arborescence sur $TARGET
#
# Exemple : ./10-partition.sh plan ; puis DRY_RUN=0 ./10-partition.sh create
# shellcheck source=../lib/common.sh
. "$(dirname "$0")/../lib/common.sh"

STATE_DIR="/tmp/dualboot-arch"
PLAN="$STATE_DIR/plan.env"
PRE_DUMP="$STATE_DIR/sfdisk-avant.txt"
SUBVOLS="@ @home @snapshots @var_log @pkg"

# lignes "partition" de sfdisk --dump (sans l'en-tête, qui contient last-lba etc.)
part_lines() { sfdisk --dump "$DISK" | grep '^/dev/'; }

align_up() { local v="$1" a="$2"; echo $(( (v + a - 1) / a * a )); }

do_plan() {
  require_root; require_uefi; require_cmd sgdisk sfdisk blockdev lsblk
  [ -b "$DISK" ] || die "Disque introuvable : $DISK"
  mkdir -p "$STATE_DIR"
  local ss align first last esp_sectors root_sectors esp_start esp_end root_start root_end free
  ss="$(blockdev --getss "$DISK")"
  align=$(( 1048576 / ss ))                       # alignement 1 MiB
  first="$(sgdisk -F "$DISK" | tail -1)"; last="$(sgdisk -E "$DISK" | tail -1)"
  [[ "$first" =~ ^[0-9]+$ && "$last" =~ ^[0-9]+$ ]] || die "Impossible de lire le bloc libre (sgdisk -F/-E)."
  free=$(( (last - first + 1) * ss / 1073741824 ))
  info "Plus grand bloc libre : secteurs $first → $last (~${free} GiB, secteur = $ss o)"

  esp_sectors=$(( ESP_SIZE_MIB * 1048576 / ss ))
  esp_start="$(align_up "$first" "$align")"
  esp_end=$(( esp_start + esp_sectors - 1 ))
  root_start="$(align_up $(( esp_end + 1 )) "$align")"
  if [ "$ROOT_SIZE_GIB" = "MAX" ]; then
    root_end="$last"
  else
    root_sectors=$(( ROOT_SIZE_GIB * 1073741824 / ss ))
    root_end=$(( root_start + root_sectors - 1 ))
  fi
  [ "$root_end" -le "$last" ] || die "Pas assez de place : il faut $(( ESP_SIZE_MIB / 1024 + ROOT_SIZE_GIB )) GiB, bloc libre ~${free} GiB."
  [ $(( (root_end - root_start + 1) * ss / 1073741824 )) -ge 200 ] || warn "Racine < 200 GiB (normal en VM, pas sur la vraie machine)."

  for l in "$ESP_PARTLABEL" "$ROOT_PARTLABEL"; do
    lsblk -rno PARTLABEL "$DISK" | grep -Fx "$l" >/dev/null && die "Une partition porte déjà le nom $l : installation déjà faite ?"
  done

  part_lines >"$PRE_DUMP"
  cat >"$PLAN" <<EOF
PLAN_DISK=$DISK
PLAN_SS=$ss
ESP_START=$esp_start
ESP_END=$esp_end
ROOT_START=$root_start
ROOT_END=$root_end
PRE_SHA=$(sha256sum "$PRE_DUMP" | cut -d' ' -f1)
EOF
  title "Partitions existantes (NE SERONT PAS TOUCHÉES)"
  cat "$PRE_DUMP"
  title "Plan"
  printf '  ESP Linux  : secteurs %s → %s (%s MiB), type EF00, nom %s\n' "$esp_start" "$esp_end" "$ESP_SIZE_MIB" "$ESP_PARTLABEL"
  printf '  Racine     : secteurs %s → %s (%s GiB), type 8300, nom %s\n' "$root_start" "$root_end" \
    $(( (root_end - root_start + 1) * ss / 1073741824 )) "$ROOT_PARTLABEL"
  title "Commandes qui seront lancées par « create »"
  print_create_cmds
  info "Plan enregistré dans $PLAN. Relire, puis : DRY_RUN=0 $0 create"
}

print_create_cmds() {
  show_cmd sgdisk -n "0:${ESP_START:-?}:${ESP_END:-?}" -t 0:ef00 -c "0:$ESP_PARTLABEL" "$DISK"
  show_cmd sgdisk -n "0:${ROOT_START:-?}:${ROOT_END:-?}" -t 0:8300 -c "0:$ROOT_PARTLABEL" "$DISK"
}

load_plan() {
  [ -f "$PLAN" ] || die "Pas de plan : lancer d'abord « $0 plan »."
  # shellcheck disable=SC1090
  . "$PLAN"
  [ "$PLAN_DISK" = "$DISK" ] || die "Le plan concerne $PLAN_DISK, pas $DISK."
}

do_create() {
  require_root; require_uefi; require_set BACKUP_DIR; load_plan
  [ "$(part_lines | sha256sum | cut -d' ' -f1)" = "$PRE_SHA" ] || die "La table a changé depuis le plan. Relancer « plan »."
  ls "$BACKUP_DIR"/preflight-*/"$(basename "$DISK")"-gpt.bak >/dev/null 2>&1 \
    || die "Aucune sauvegarde GPT dans $BACKUP_DIR. Lancer d'abord : DRY_RUN=0 ./00-preflight-live.sh backup"
  banner_mode
  title "État actuel"; lsblk -f "$DISK"; sgdisk -p "$DISK"
  title "Commandes"; print_create_cmds
  confirm_oui "Ajouter ces 2 partitions sur $DISK ? Les partitions Windows ne sont pas modifiées."
  run sgdisk -n "0:${ESP_START}:${ESP_END}" -t 0:ef00 -c "0:$ESP_PARTLABEL" "$DISK"
  run sgdisk -n "0:${ROOT_START}:${ROOT_END}" -t 0:8300 -c "0:$ROOT_PARTLABEL" "$DISK"
  run partprobe "$DISK"
  [ "$DRY_RUN" = "0" ] || return 0
  udevadm settle
  verify_untouched
  sgdisk -p "$DISK"
  journal "sgdisk : ajout $ESP_PARTLABEL + $ROOT_PARTLABEL (secteurs $ESP_START-$ROOT_END)" "OK, partitions existantes intactes"
}

verify_untouched() {
  local post; post="$(part_lines)"
  local missing; missing="$(grep -Fxv -f <(printf '%s\n' "$post") "$PRE_DUMP" || true)"
  [ -z "$missing" ] || { printf '%s\n' "$missing"; die "UNE PARTITION EXISTANTE A CHANGÉ. Ne rien faire de plus. Voir docs/RECOVERY.md (restauration GPT)."; }
  local added; added=$(( $(printf '%s\n' "$post" | wc -l) - $(wc -l <"$PRE_DUMP") ))
  [ "$added" -eq 2 ] || die "Attendu : 2 partitions ajoutées, constaté : $added."
  info "Contrôle OK : partitions existantes identiques octet pour octet (sfdisk --dump), 2 ajoutées."
}

# new_part PARTLABEL : périphérique de la partition créée par ce script (jamais une préexistante)
new_part() {
  local label="$1" devs uuid
  mapfile -t devs < <(lsblk -rno PATH,PARTLABEL "$DISK" | awk -v l="$label" '$2==l {print $1}')
  [ "${#devs[@]}" -eq 1 ] || die "Partition $label : ${#devs[@]} trouvée(s), 1 attendue."
  uuid="$(lsblk -rno PARTUUID "${devs[0]}")"
  [ -f "$PRE_DUMP" ] && grep -qi "uuid=$uuid" "$PRE_DUMP" && die "${devs[0]} existait avant le plan : refus de formater."
  printf '%s\n' "${devs[0]}"
}

do_format() {
  require_root
  local esp root
  esp="$(new_part "$ESP_PARTLABEL")"; root="$(new_part "$ROOT_PARTLABEL")"
  banner_mode
  title "Cibles du formatage"
  lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,PARTUUID "$esp" "$root"
  title "Signatures existantes (wipefs -n, lecture seule)"
  wipefs -n "$esp" "$root" || true
  confirm_oui "Formater $esp en FAT32 ($ESP_FSLABEL) et $root en Btrfs ($ROOT_FSLABEL) ?"
  run mkfs.fat -F 32 -n "$ESP_FSLABEL" "$esp"
  run mkfs.btrfs -L "$ROOT_FSLABEL" "$root"
  journal "mkfs.fat $esp + mkfs.btrfs $root" "OK"
}

do_subvols() {
  require_root
  local root; root="$(unique_dev "$ROOT_DEV")"
  banner_mode
  confirm_oui "Créer les sous-volumes ($SUBVOLS) sur $root ?"
  run mkdir -p /mnt/top
  run mount -o subvolid=5 "$root" /mnt/top
  local s; for s in $SUBVOLS; do run btrfs subvolume create "/mnt/top/$s"; done
  [ "$DRY_RUN" = "0" ] && btrfs subvolume list /mnt/top
  run umount /mnt/top
  journal "sous-volumes $SUBVOLS" "OK"
}

do_mount() {
  require_root
  local root esp; root="$(unique_dev "$ROOT_DEV")"; esp="$(unique_dev "$ESP_DEV")"
  banner_mode
  mountpoint -q "$TARGET" && die "$TARGET est déjà monté."
  mount_layout "$root" "$esp" "$TARGET"
  [ "$DRY_RUN" = "0" ] && { title "Contrôle"; lsblk -f "$DISK"; findmnt -R "$TARGET"; }
  return 0
}

case "${1:-}" in
  plan) do_plan ;; create) do_create ;; format) do_format ;;
  subvols) do_subvols ;; mount) do_mount ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
