# Décisions et écarts avec le brief

Type de projet : **D (outil local / scripts)**. Pas de backend, pas de clés, pas d'interface web.

## Choix d'architecture (repris du brief)

| Choix | Raison |
|---|---|
| ESP Linux séparée (1 GiB, `/efi`), ESP Windows jamais montée en écriture | Si GRUB casse, Windows démarre toujours par F11. Aucune écriture possible sur la chaîne de démarrage Windows. |
| `/boot` dans `@` (Btrfs), pas sur l'ESP | Noyau, initramfs et modules NVIDIA font partie du snapshot : un retour arrière reste cohérent. |
| GRUB + grub-btrfs | GRUB lit Btrfs nativement et affiche les snapshots. Limine mettrait les noyaux sur l'ESP. |
| Layout plat `@ @home @snapshots @var_log @pkg` | Les snapshots survivent au remplacement de `@` ; `/var/lib/pacman` reste dans `@`, donc cohérent. |
| `subvol=` sans `subvolid=` dans fstab | Après restauration, `@` a un nouvel ID : `subvolid=` empêcherait le démarrage. `20-base-install.sh` le retire. |
| zram, pas de swap ni d'hibernation | 16 Go de RAM, NVMe unique, moins de pièces mobiles. |
| Noyaux `linux` + `linux-lts` gardés en permanence | Filets de sécurité ; `linux-cachyos` ajouté seulement en phase 6. |
| Pas de LUKS | Limiter les points de panne pour cette version. |
| Mode hybride : iGPU affiche, dGPU en offload (`prime-run`) | Autonomie du portable. Aucune variable NVIDIA globale. |

## Choix ajoutés pendant l'écriture des scripts

| Choix | Raison |
|---|---|
| `lib/common.sh` : `run`, `confirm_oui`, `write_file`, `journal` | Une seule implémentation du DRY_RUN et des confirmations. `write_file` sauvegarde toujours l'existant (`.bak-DATE`). |
| `10-partition.sh` découpé en `plan / create / format / subvols / mount` | Une confirmation par opération destructive. Le plan calcule les secteurs depuis le plus grand bloc libre (`sgdisk -F/-E`), aligné sur 1 MiB. |
| Contrôle « partitions intactes » par `sfdisk --dump` avant/après | Chaque ligne de partition existante doit être identique à l'octet près, et exactement 2 partitions ajoutées. Sinon arrêt. |
| `format` refuse toute partition dont le PARTUUID existait avant le plan | Impossible de formater une partition Windows par erreur de label. |
| Labels vérifiés uniques (`blkid -t LABEL=`) | Un lien `/dev/disk/by-label` n'en montre qu'un seul si deux volumes portent le même label. |
| `create` exige une sauvegarde GPT dans `BACKUP_DIR` | Règle 3 du brief, rendue bloquante. |
| `rmdir` au lieu de `rm -rf /.snapshots` (phase 4) | `rmdir` refuse un dossier non vide. |
| `post/jalon.sh` | Jalons nommés `JALON NN - …`, sans algorithme de nettoyage, numéro snapper inscrit au journal. |
| Script de maintenance nommé `maj-systeme.sh` (et non `ark-update.sh`) | Éviter la confusion avec le projet Ark. Le brief laissait le nom libre. |
| Hyprland sur tty1 seulement, tty2 = shell texte + `sway` | Session de secours toujours accessible même si `hyprland.lua` casse. |
| VM de répétition : VMware (déjà installé), QEMU/OVMF en alternative | Voir `docs/VM.md`. `vm/make-fake-windows.sh` refuse de tourner hors VM et sur un matériel MSI. |

## Écarts avec le brief (vérifiés le 2026-11-20)

Règle 7 du brief : la doc officielle l'emporte.

1. **NVIDIA pour `linux-lts` : `nvidia-open-lts`, pas `nvidia-open-dkms`.**
   Wiki Arch, page NVIDIA, tableau d'installation : Ada → `nvidia-open` pour linux, `nvidia-open-lts` pour linux-lts, `nvidia-open-dkms` pour n'importe quel noyau. Les deux paquets précompilés existent dans `extra` (620.73.04 au 2026-11-20). Pas de DKMS nécessaire.
2. **`nvidia_drm.modeset=1` inutile.** Wiki NVIDIA : DRM activé par défaut depuis `nvidia-utils` 560.35.03-5. Contrôle : `cat /sys/module/nvidia_drm/parameters/modeset` → `Y`.
3. **RTD3 (énergie dGPU) : rien à configurer a priori sur Ada.** Wiki PRIME : « No configuration is generally needed for Ampere as this is enabled by default ». `50-hardware-laptop.sh check` affiche `runtime_status` ; on n'ajoute règles udev et `NVreg_DynamicPowerManagement` que si la dGPU ne passe pas en `suspended`.
4. **`AQ_DRM_DEVICES` : pas de chemins `/dev/dri/by-path/...`.** Wiki Hyprland (Multi-GPU, 0.57.0) : la variable est séparée par `:` et les chemins by-path contiennent des `:`. Solution du wiki : règle udev qui crée un lien stable. D'où `/dev/dri/intel-igpu` et `/dev/dri/nvidia-dgpu` (`50-hardware-laptop.sh udev`). La dGPU est incluse en second : un écran branché sur sa sortie ne marche que si sa carte est dans la liste.
5. **Hyprland 0.57 se configure en Lua** (`~/.config/hypr/hyprland.lua`), plus en hyprlang. Conséquence pour la phase 8 : vérifier que le « rice » choisi (end-4, Caelestia, HyDE, ML4W, Noctalia…) supporte la version installée avant de l'appliquer. Aucun fichier de config Hyprland n'est écrit par les scripts : Hyprland génère un exemple au premier lancement.
6. **Variables d'environnement avec uwsm** : `~/.config/uwsm/env-hyprland` pour `HYPR*`/`AQ_*`, `~/.config/uwsm/env` pour le reste (wiki Hyprland, page UWSM). Pas dans `hyprland.lua`. Lancement : `uwsm check may-start` puis `exec uwsm start hyprland.desktop`. Quitter avec `uwsm stop`.
7. **HOOKS `udev` (busybox) conservés volontairement.** Wiki mkinitcpio : les hooks d'exécution sont des scripts sourcés par busybox ash ; l'initramfs systemd ne les exécute pas. `grub-btrfs-overlayfs` (nom confirmé par le README grub-btrfs) est un hook d'exécution : il faut donc `udev`, pas `systemd`. Pas de `fsck` (Btrfs).
8. **CachyOS : le dépôt `[cachyos]` installe un pacman modifié.** Wiki CachyOS (optimized_repos, mis à jour le 2026-11-14) : ne pas ajouter `[cachyos]` évite le pacman modifié ; Intel 12e gen doit être traité en x86-64-v3 uniquement. Paquet `linux-cachyos-nvidia-open` confirmé sur packages.cachyos.org (dépôt `cachyos-v3`). `linux-cachyos-headers` : vérifié au moment de l'installation par `pacman -Si` (le script s'arrête s'il manque).

## Points encore à vérifier (pendant la répétition en VM ou sur la machine)

- [À VÉRIFIER] Code de sortie de `informant check` quand des actualités sont non lues (utilisé par `maj-systeme.sh`).
- [À VÉRIFIER] `sway` avec le module nvidia chargé : peut exiger `--unsupported-gpu` même si l'iGPU fait le rendu.
- [À VÉRIFIER] Le firmware MSI garde-t-il l'entrée UEFI `ARCH-GRUB` ? Sinon `grub-install --removable` (sur l'ESP Linux uniquement).
- [À VÉRIFIER] Présence d'un MUX dans le BIOS MSI.
- [À VÉRIFIER] Sortie HDMI/USB-C câblée sur la dGPU ou l'iGPU.
- [À VÉRIFIER] `msi-ec` : compatibilité avec le Cyborg 15 A12VF avant toute écriture dans l'EC.
