#!/usr/bin/env bash
# guide.sh — tableau de bord de l'installation. Ne modifie jamais le système.
#
#   ./guide.sh              où j'en suis, prochaine étape, commandes exactes
#   ./guide.sh valider N    marquer l'étape N comme validée (après son point de contrôle)
#   ./guide.sh annuler N    retirer la validation de l'étape N
#   ./guide.sh doc [N]      lire le guide (à l'étape N)
#   ./guide.sh depannage    lire le guide de dépannage
#   ./guide.sh liste        toutes les étapes avec leurs commandes
#
# La progression est enregistrée dans .etat (copiée avec le dépôt dans le système installé).
# shellcheck source=lib/common.sh
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
set +e

ETAT="$REPO_DIR/.etat"
GUIDE="$REPO_DIR/docs/GUIDE.md"
DEP="$REPO_DIR/docs/DEPANNAGE.md"

# id | titre | où | commandes (séparées par « ; ; »)
ETAPES=(
"0|Préparer Windows (image, réduire C:, UTC, BitLocker)|windows|voir docs/GUIDE.md, étape 0 (à faire dans Windows)"
"1|Clé live : réseau, dépôt, état de la machine|live|./install/00-preflight-live.sh"
"2|Sauvegarder la table de partitions et l'ESP Windows|live|DRY_RUN=0 ./install/00-preflight-live.sh backup"
"3|Partitionner, formater, monter|live|./install/10-partition.sh plan ; ; DRY_RUN=0 ./install/10-partition.sh create ; ; DRY_RUN=0 ./install/10-partition.sh format ; ; DRY_RUN=0 ./install/10-partition.sh subvols ; ; DRY_RUN=0 ./install/10-partition.sh mount"
"4|Installer la base Arch|live|DRY_RUN=0 ./install/20-base-install.sh"
"5|Configurer le système et GRUB (chroot)|live|arch-chroot /mnt env DRY_RUN=0 /root/dualboot-arch/install/30-chroot-config.sh ; ; exit ; ; umount -R /mnt ; ; reboot"
"6|Premier démarrage : Arch ET Windows démarrent|installe|sudo grub-mkconfig -o /boot/grub/grub.cfg   (si Windows absent du menu)"
"7|Snapshots : snapper + tests + JALON 00|installe|sudo DRY_RUN=0 ./post/40-snapper.sh ; ; (tests : docs/GUIDE.md étape 7) ; ; sudo DRY_RUN=0 ./post/jalon.sh 00 \"arch-base valide\""
"8|Portable : pilotes NVIDIA/Intel, audio, énergie + JALON 01|installe|sudo DRY_RUN=0 ./post/50-hardware-laptop.sh install ; ; sudo DRY_RUN=0 ./post/50-hardware-laptop.sh udev ; ; reboot ; ; ./post/50-hardware-laptop.sh check ; ; sudo DRY_RUN=0 ./post/jalon.sh 01 \"arch-config\""
"9|CachyOS : JALON 02, dépôts, noyau, JALON 03|installe|sudo DRY_RUN=0 ./post/jalon.sh 02 \"pre-cachy\" ; ; sudo ./post/60-cachyos-repo.sh check ; ; sudo DRY_RUN=0 ./post/60-cachyos-repo.sh prepare ; ; sudo DRY_RUN=0 ./post/60-cachyos-repo.sh run ; ; sudo pacman -Syu ; ; reboot ; ; sudo DRY_RUN=0 ./post/60-cachyos-repo.sh kernel ; ; sudo DRY_RUN=0 ./post/jalon.sh 03 \"post-cachy\""
"10|Hyprland : JALON 04, installation, session de secours, JALON 05|installe|sudo DRY_RUN=0 ./post/jalon.sh 04 \"pre-hyprland\" ; ; sudo DRY_RUN=0 ./post/70-hyprland.sh packages ; ; DRY_RUN=0 ./post/70-hyprland.sh user-setup ; ; sudo DRY_RUN=0 ./post/jalon.sh 05 \"hyprland-ok\""
"11|Personnalisation + JALON 06|installe|(rice choisi, snapshot avant) ; ; sudo DRY_RUN=0 ./post/jalon.sh 06 \"perso-ok\""
"12|Maintenance automatique|installe|sudo DRY_RUN=0 ./post/80-maintenance.sh ; ; ensuite, pour chaque mise à jour : sudo DRY_RUN=0 maj-systeme"
)

contexte() {
  if [ -d /run/archiso ]; then echo live
  elif systemd-detect-virt --chroot >/dev/null 2>&1; then echo chroot
  elif [ -f /etc/arch-release ]; then echo installe
  else echo autre; fi
}

# validation automatique quand une preuve existe sur le système
auto_ok() {
  case "$1" in
    7)  jalon_existe 00 ;;
    8)  jalon_existe 01 ;;
    9)  jalon_existe 03 ;;
    10) jalon_existe 05 ;;
    11) jalon_existe 06 ;;
    12) systemctl is-enabled paccache.timer >/dev/null 2>&1 ;;
    *)  return 1 ;;
  esac
}

est_ok() { grep -qx "$1" "$ETAT" 2>/dev/null || auto_ok "$1"; }

champ() { local IFS='|'; local -a f; read -r -a f <<<"$1"; echo "${f[$2]}"; }

prochaine() {
  local e id
  for e in "${ETAPES[@]}"; do id="$(champ "$e" 0)"; est_ok "$id" || { echo "$id"; return; }; done
  echo fin
}

cmds() { champ "${ETAPES[$1]}" 3 | sed 's/ ; ; /\n/g' | sed 's/^/      /'; }

tableau() {
  local ctx nx e id t ou mark
  ctx="$(contexte)"; nx="$(prochaine)"
  title "Installation dual boot — où j'en suis"
  echo "Contexte détecté : $ctx   (live = clé USB, chroot = /mnt, installe = Arch démarré)"
  echo
  for e in "${ETAPES[@]}"; do
    id="$(champ "$e" 0)"; t="$(champ "$e" 1)"; ou="$(champ "$e" 2)"
    if est_ok "$id"; then mark="${G}[OK]${N}"; elif [ "$id" = "$nx" ]; then mark="${Y}[>>]${N}"; else mark="[  ]"; fi
    printf ' %s %2s  %-11s %s\n' "$mark" "$id" "($ou)" "$t"
  done
  echo
  if [ "$nx" = fin ]; then info "Tout est validé. Maintenance : sudo DRY_RUN=0 maj-systeme"; return; fi
  title "Prochaine étape : $nx — $(champ "${ETAPES[$nx]}" 1)"
  local ou_nx; ou_nx="$(champ "${ETAPES[$nx]}" 2)"
  if [ "$ou_nx" != "$ctx" ] && ! { [ "$ou_nx" = live ] && [ "$ctx" = chroot ]; }; then
    warn "Cette étape se fait en contexte « $ou_nx », tu es en « $ctx »."
  fi
  echo "  Commandes (depuis le dossier du dépôt) :"
  cmds "$nx"
  echo
  echo "  Explications, résultat attendu, erreurs : ./guide.sh doc $nx"
  echo "  Une fois le point de contrôle réussi    : ./guide.sh valider $nx"
  echo "  Problème                                : ./guide.sh depannage"
  echo
  echo "Rappel : sans DRY_RUN=0, un script ne fait que montrer ce qu'il ferait."
}

lire() {
  local fichier="$1" motif="${2:-}"
  if command -v less >/dev/null; then
    if [ -n "$motif" ]; then less -R +"/$motif" "$fichier"; else less -R "$fichier"; fi
  else cat "$fichier"; fi
}

case "${1:-}" in
  "") tableau ;;
  valider)
    [[ "${2:-}" =~ ^[0-9]+$ ]] && [ "$2" -le 12 ] || die "Usage : $0 valider N (0 à 12)"
    grep -qx "$2" "$ETAT" 2>/dev/null || echo "$2" >>"$ETAT"
    # depuis la live : reporter aussi dans les copies du dépôt déjà posées dans /mnt
    for copie in /mnt/root/dualboot-arch /mnt/home/*/dualboot-arch; do
      if [ -d "$copie" ] && [ "$copie" != "$REPO_DIR" ]; then
        cp "$ETAT" "$copie/.etat" 2>/dev/null && chown --reference="$copie" "$copie/.etat" 2>/dev/null
      fi
    done
    info "Étape $2 validée."; journal_line="$(date '+%Y-%m-%d %H:%M')"
    [ -w "$JOURNAL_FILE" ] && printf '| %s | guide.sh | étape %s validée | OK | - |\n' "$journal_line" "$2" >>"$JOURNAL_FILE"
    tableau ;;
  annuler)
    [ -f "$ETAT" ] && sed -i "/^${2:-x}\$/d" "$ETAT"; info "Validation de l'étape ${2:-?} retirée."; tableau ;;
  doc)        if [ -n "${2:-}" ]; then lire "$GUIDE" "^## Étape ${2} "; else lire "$GUIDE"; fi ;;
  depannage)  lire "$DEP" ;;
  liste)
    for i in "${!ETAPES[@]}"; do printf '\n%s%2s — %s%s (%s)\n' "$B" "$i" "$(champ "${ETAPES[$i]}" 1)" "$N" "$(champ "${ETAPES[$i]}" 2)"; cmds "$i"; done ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
