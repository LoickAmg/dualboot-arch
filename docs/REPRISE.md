# Reprise — continuer le projet sur l'Arch installée, avec un assistant

À utiliser à partir de l'**étape 6** (Arch démarre), quand tu réinstalles ton assistant de code en ligne de commande sur l'Arch pour être accompagné sur la suite (snapshots, CachyOS, Hyprland). Ce fichier lui donne tout le contexte nécessaire, sans qu'il ait besoin de la conversation d'origine.

---

## 1. Installer l'assistant sur l'Arch

Pré-requis :
```
$ sudo pacman -S --needed curl less gnupg
```

Règle du projet : **aucun script téléchargé ne s'exécute sans avoir été lu**. Donc jamais `curl … | bash`, mais :
```
$ cd ~
$ curl -fsSL <URL du script d'installation officiel> -o install.sh
$ less install.sh          # lire en entier : que télécharge-t-il, où installe-t-il, que modifie-t-il ?
$ bash install.sh
$ rm install.sh
```
L'URL est celle de la page d'installation officielle de l'assistant (section Linux). La lire sur le téléphone.

Points à connaître (vérifiés sur la doc officielle le 2026-11-20) :
- Le binaire s'installe dans `~/.local/bin`. L'installateur **ne modifie pas** le PATH. Sur un TTY, c'est `~/.bash_profile` qui est lu à la connexion :
  ```
  $ echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bash_profile
  $ source ~/.bash_profile
  ```
- Arch n'est pas dans la liste des distributions citées par la doc, sans être exclue. Il existe un paquet AUR communautaire, non officiel : préférer l'installateur officiel.
- La doc publie un manifeste signé GPG des binaires, pour vérifier une version précise : la section « binary integrity » de la page d'installation explique comment.
- Alternative par npm : elle demande Node.js 22 ou plus récent (`sudo pacman -S nodejs npm`). Ne pas utiliser `sudo` pour l'installation npm.

**Connexion depuis un TTY (sans navigateur sur la machine)** : au premier lancement, l'assistant affiche une adresse de connexion. L'ouvrir sur le téléphone ou sur un autre PC, se connecter, puis recopier le **code** affiché à l'invite « Paste code here ». Les identifiants restent dans `~/` avec des droits privés : ne jamais les copier dans ce dépôt.

Diagnostic : la commande `doctor` de l'assistant (installation, configuration, mises à jour).

## 2. Avant chaque session avec l'assistant

```
$ sudo snapper -c root create -d "avant session assistant $(date +%F)"
```
(Possible seulement après l'étape 7. Avant, l'image Clonezilla reste le seul filet.)

**Ne pas activer le mode qui accepte toutes les actions sans confirmation.** Valider chaque commande qui écrit sur le système.

## 3. Phrase de démarrage à donner à l'assistant

> Lis en entier `docs/REPRISE.md`, puis `README.md`, `docs/DECISIONS.md`, `docs/JOURNAL.md` et `docs/HARDWARE.md`. Lance `./guide.sh` pour voir où j'en suis. Ensuite, dis-moi l'étape en cours et ce que tu proposes, **sans rien exécuter** avant mon accord.

L'assistant travaille depuis `~/dualboot-arch`. Mettre le dépôt à jour d'abord : `git pull` (voir DEPANNAGE [G5] en cas de conflit).

---

## 4. Contexte pour l'assistant

### Machine et objectif
- MSI Cyborg 15 A12VF, **portable**, i7 de 12e génération (x86-64-v3, pas v4), 16 Go de RAM, un seul NVMe de 1 To partagé avec Windows.
- Graphique hybride : iGPU Intel Iris Xe + RTX 4060 Laptop. L'iGPU affiche, la dGPU sert en offload (`prime-run`).
- Windows 11 personnalisé (Ghost Spectre + AtlasOS) : **une seule installation, à ne jamais toucher**.
- Objectif : dual boot sûr, snapshots Btrfs automatiques, retour possible à chaque jalon, Arch minimale puis surcouche CachyOS, puis Hyprland.
- Faits vérifiés sur la machine : [HARDWARE.md](HARDWARE.md). Ce qui y est marqué `[À COMPLÉTER]` n'est pas vérifié.

### Architecture en place (ne pas la changer)
- ESP Linux séparée (`ARCHESP`, 1 GiB, montée sur `/efi`), qui ne contient que GRUB. L'ESP Windows n'est jamais montée en écriture.
- Racine Btrfs `archroot`, layout plat : `@` → `/`, `@home`, `@snapshots` → `/.snapshots`, `@var_log`, `@pkg`. `/boot` est **dans** `@`.
- fstab avec `subvol=` uniquement, **jamais** `subvolid=`.
- GRUB + grub-btrfs (`grub-btrfsd`). Hooks mkinitcpio **`udev`, pas `systemd`**, avec `grub-btrfs-overlayfs` en dernier.
- Noyaux `linux` + `linux-lts` conservés en permanence ; `linux-cachyos` ajouté à l'étape 9.
- zram (pas de swap, pas d'hibernation), pas de LUKS.
- Restauration : `rescue/restore-snapshot.sh` depuis la clé live. **Pas** de `snapper rollback`, incompatible avec ce layout.

Les raisons de chaque choix, et les 8 écarts entre le brief d'origine et la doc officielle, sont dans [DECISIONS.md](DECISIONS.md). Points clés :
- NVIDIA : `nvidia-open` + `nvidia-open-lts`. Pas de `nvidia_drm.modeset=1` (actif par défaut). RTD3 actif par défaut sur Ada.
- Hyprland 0.57 se configure en **Lua** (`hyprland.lua`). Variables dans `~/.config/uwsm/env` et `env-hyprland`. `AQ_DRM_DEVICES` utilise les liens udev `/dev/dri/intel-igpu` et `/dev/dri/nvidia-dgpu`, jamais `/dev/dri/by-path`.
- CachyOS : le dépôt `[cachyos]` remplace pacman. Niveau v3.

### Règles impératives (à respecter sans exception)
1. **Aucune commande destructive sans validation explicite de l'utilisateur** : `sgdisk`, `parted`, `mkfs.*`, `wipefs`, `dd`, `btrfs subvolume delete`, `rm -rf`, `efibootmgr -B/-o`, `grub-install`, `pacman -Rns` en masse, modification de `/etc/pacman.conf`.
2. **Ne jamais toucher aux partitions Windows** : ESP Windows, MSR, C:, récupération. Pas de `ntfsfix`, pas de montage NTFS en écriture.
3. **Mode simulation par défaut** : les scripts tournent avec `DRY_RUN=1`. L'exécution réelle (`sudo DRY_RUN=0 …`) se fait seulement à la demande de l'utilisateur.
4. **Rien de non lu ne s'exécute** : pas de `curl | bash`, PKGBUILD AUR lus, script CachyOS lu en entier (`60-cachyos-repo.sh prepare`).
5. **Vérifier contre la doc officielle** (Arch Wiki, wiki.cachyos.org, wiki.hypr.land **à la version installée**) avant d'appliquer une procédure. En cas de contradiction, la doc a raison : le signaler et le noter dans DECISIONS.md.
6. **Un changement à la fois, puis un test, puis un snapshot de jalon** (`post/jalon.sh`).
7. **Tout est journalisé** dans [JOURNAL.md](JOURNAL.md) : date, commande, résultat, numéro de snapshot.
8. Répondre en **français**. Pas de mention d'outil d'IA dans les fichiers versionnés, les commits ou les messages de commit.
9. Ne jamais affirmer qu'une chose fonctionne sans l'avoir vérifiée par une commande réelle.

### Organisation du dépôt
- `guide.sh` : progression (étapes 0 à 12) et prochaine commande.
- `install/` (étapes 1 à 5, clé live), `post/` (étapes 7 à 12), `rescue/`, `maintenance/`, `lib/common.sh` (DRY_RUN, confirmations, journal).
- Docs : [GUIDE.md](GUIDE.md) (procédure), [DEPANNAGE.md](DEPANNAGE.md) (problèmes par code), [MANUEL.md](MANUEL.md) (étapes 3 à 5 sans script), [RECOVERY.md](RECOVERY.md) (secours), [COMPRENDRE-SNAPSHOTS.md](COMPRENDRE-SNAPSHOTS.md).
- Commits en français, au format « Domaine : pourquoi ». Ne pousser qu'à la demande de l'utilisateur.

### État connu
- Les scripts ont passé shellcheck et des tests sur disques simulés. **Ils n'ont pas été répétés en VM** : l'installation se fait directement sur la vraie machine.
- Toute erreur rencontrée pendant les étapes 1 à 5 doit figurer dans JOURNAL.md. **La lire en premier** : elle peut révéler un défaut de script à corriger avant de continuer.
- Points ouverts : section « Points encore à vérifier » de DECISIONS.md.
