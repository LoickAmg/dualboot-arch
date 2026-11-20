# Journal

Une ligne par action réelle (`DRY_RUN=0`). Les scripts ajoutent leurs lignes automatiquement quand ce fichier est accessible en écriture. Les actions manuelles (Windows, BIOS, tests) s'ajoutent à la main.

## Jalons

| Jalon | N° snapper | Date | Validé par |
|---|---|---|---|
| 00-arch-base | | | |
| 01-arch-config | | | |
| 02-pre-cachy | | | |
| 03-post-cachy | | | |
| 04-pre-hyprland | | | |
| 05-hyprland-ok | | | |
| 06-perso-ok | | | |

## Actions

| Date | Script / origine | Action | Résultat | Snapshot |
|---|---|---|---|---|
| 2026-11-20 | dépôt | création du dépôt `dualboot-arch` (scripts, docs), vérification du brief contre la doc officielle | 8 écarts consignés dans DECISIONS.md | - |
| 2026-11-21 | Windows | relevé matériel en lecture seule (disque WD SN350 1 To GPT, 4 partitions, Wi-Fi Intel AX201, hibernation désactivée) | reporté dans HARDWARE.md | - |
| 2026-11-21 | Windows | sauvegarde des 3 jeux (P5R, Prince of Persia, Zelda OoT) | `sauvegardes-jeux-2026-11-21.zip`, 72 fichiers vérifiés | - |
| 2026-11-21 | Windows | réduction de C: : bloquée par `$UsnJrnl` → `fsutil usn deletejournal` ; puis par `pagefile.sys` → fichier d'échange désactivé | débloqués | - |
| 2026-11-21 | Windows | réduction de C: : bloquée par `$Mft` (Windows ne peut pas la déplacer) | **non réduite** | - |
| 2026-11-21 | AOMEI PA Standard | réduction via Windows PE | écran bleu `DRIVER_VERIFIER_DMA_VIOLATION` ×2, disque **intact** (vérifié) ; reporté à GParted | - |
