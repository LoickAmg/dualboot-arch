# lib/common.sh — fonctions partagées par tous les scripts. À sourcer, pas à exécuter.
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$REPO_DIR/config.env}"
CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
[ -f "$CONFIG_FILE" ] || { echo "config introuvable : $CONFIG_FILE" >&2; exit 1; }
# shellcheck source=../config.env
. "$CONFIG_FILE"
DRY_RUN="${DRY_RUN:-1}"
JOURNAL_FILE="${JOURNAL_FILE:-$REPO_DIR/docs/JOURNAL.md}"
SCRIPT_NAME="$(basename "$0")"

if [ -t 1 ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'; else R=; G=; Y=; B=; N=; fi

info()  { printf '%s[INFO]%s %s\n' "$G" "$N" "$*"; }
warn()  { printf '%s[ATTENTION]%s %s\n' "$Y" "$N" "$*" >&2; }
die()   { printf '%s[ERREUR]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
title() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }

banner_mode() {
  if [ "$DRY_RUN" = "0" ]; then
    printf '%s>>> MODE RÉEL (DRY_RUN=0) : les commandes seront exécutées.%s\n' "$R$B" "$N"
  else
    printf '%s>>> MODE SIMULATION (DRY_RUN=1) : rien ne sera modifié.%s\n' "$G$B" "$N"
  fi
}

show_cmd() { printf '    $'; printf ' %q' "$@"; printf '\n'; }

# run CMD ARGS... : exécutée seulement si DRY_RUN=0
run() {
  if [ "$DRY_RUN" = "0" ]; then show_cmd "$@"; "$@"
  else printf '%s[DRY-RUN]%s' "$Y" "$N"; show_cmd "$@"; fi
}

# run_sh 'chaîne shell' : pour les redirections et tubes, même règle que run
run_sh() {
  if [ "$DRY_RUN" = "0" ]; then printf '    $ %s\n' "$1"; bash -c "$1"
  else printf '%s[DRY-RUN]%s $ %s\n' "$Y" "$N" "$1"; fi
}

# ro CMD : commande en lecture seule, toujours exécutée
ro() { show_cmd "$@"; "$@"; }

# confirm_oui "message" : exige la saisie exacte de OUI en mode réel
confirm_oui() {
  if [ "$DRY_RUN" != "0" ]; then info "(simulation) confirmation demandée en mode réel : $1"; return 0; fi
  local ans
  printf '\n%s%s%s\nTaper OUI (en majuscules) pour continuer, autre chose pour annuler : ' "$B" "$1" "$N"
  read -r ans </dev/tty
  [ "$ans" = "OUI" ] || die "Annulé par l'utilisateur."
}

require_root() { [ "$(id -u)" -eq 0 ] || die "À lancer en root."; }
require_uefi() { [ -d /sys/firmware/efi ] || die "Pas démarré en mode UEFI."; }
require_cmd()  { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "Commande manquante : $c"; done; }

# require_set VAR... : refuse les variables vides ou "A_COMPLETER"
require_set() {
  local v val
  for v in "$@"; do
    val="${!v:-}"
    { [ -n "$val" ] && [ "$val" != "A_COMPLETER" ]; } || die "Variable $v non renseignée dans $(basename "$CONFIG_FILE")."
  done
}

# write_file DEST [MODE] < contenu : sauvegarde l'existant (.bak-DATE) puis écrit
write_file() {
  local dest="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  if [ "$DRY_RUN" = "0" ]; then
    [ -e "$dest" ] && cp -a "$dest" "$dest.bak-$(date +%Y%m%d-%H%M%S)"
    install -D -m "$mode" "$tmp" "$dest"; info "écrit : $dest"
  else
    printf '%s[DRY-RUN]%s écrirait %s :\n' "$Y" "$N" "$dest"; sed 's/^/    | /' "$tmp"
  fi
  rm -f "$tmp"
}

# backup_file FICHIER : copie datée avant modification (mode réel seulement)
backup_file() { [ "$DRY_RUN" = "0" ] && [ -e "$1" ] && cp -a "$1" "$1.bak-$(date +%Y%m%d-%H%M%S)"; return 0; }

# journal "action" "résultat" ["n° snapshot"] : ajoute une ligne à docs/JOURNAL.md
journal() {
  [ "$DRY_RUN" = "0" ] || return 0
  if [ -w "$JOURNAL_FILE" ]; then
    printf '| %s | %s | %s | %s | %s |\n' "$(date '+%Y-%m-%d %H:%M')" "$SCRIPT_NAME" "$1" "$2" "${3:--}" >>"$JOURNAL_FILE"
  else
    warn "Journal non inscriptible ($JOURNAL_FILE) : noter à la main → $1 / $2 / ${3:--}"
  fi
}

# unique_dev LIEN : vérifie qu'un lien /dev/disk/by-* existe et pointe vers un seul périphérique
unique_dev() {
  local link="$1" real
  [ -e "$link" ] || die "Introuvable : $link"
  real="$(readlink -f "$link")"
  [ -b "$real" ] || die "$link ne pointe pas vers un périphérique bloc."
  # un lien by-label n'en montre qu'un : vérifier qu'aucun autre volume ne porte ce label
  case "$link" in
    /dev/disk/by-label/*)
      local n; n="$(blkid -t "LABEL=${link##*/}" -o device | wc -l)"
      [ "$n" -eq 1 ] || die "Label ${link##*/} porté par $n volumes : ambigu, refus."
      ;;
  esac
  printf '%s\n' "$real"
}

# jalon_existe NN : vrai si un snapshot snapper "JALON NN" existe
# (grep sans -q : avec pipefail, -q ferait échouer le tube par SIGPIPE)
jalon_existe() { snapper -c root list 2>/dev/null | grep "JALON $1" >/dev/null; }

# mount_layout ROOT_DEV ESP_DEV CIBLE : monte @, les sous-volumes et l'ESP Linux
mount_layout() {
  local root="$1" esp="$2" t="$3" pair
  run mount -o "${MOUNT_OPTS},subvol=@" "$root" "$t"
  run mkdir -p "$t/home" "$t/.snapshots" "$t/var/log" "$t/var/cache/pacman/pkg" "$t/efi"
  for pair in "@home:home" "@snapshots:.snapshots" "@var_log:var/log" "@pkg:var/cache/pacman/pkg"; do
    run mount -o "${MOUNT_OPTS},subvol=${pair%%:*}" "$root" "$t/${pair#*:}"
  done
  run mount -o umask=0077 "$esp" "$t/efi"
}
