# Dépannage

Chaque problème a un code (`[P3]`, `[S5]`…) cité dans [GUIDE.md](GUIDE.md). Chercher le code avec `/` dans `less` (`./guide.sh depannage`).

**Avant tout**

1. **Ne pas enchaîner les tentatives.** Lire le message d'erreur en entier : la cause est presque toujours dans les 5 dernières lignes.
2. Le noter dans [JOURNAL.md](JOURNAL.md) (commande + message exact).
3. Sur un système installé, **tout est réversible** grâce aux snapshots tant que le jalon précédent existe. Ce qui ne l'est pas : écrire sur le disque depuis la live (étapes 2 et 3). Là, on s'arrête et on réfléchit.
4. Les messages de journal utiles :
   - `journalctl -b -p err` : erreurs du démarrage en cours ;
   - `journalctl -b -1 -p err` : celles du démarrage précédent ;
   - `dmesg | tail -50` : messages récents du noyau.

Index : [Windows et préparation (P)](#windows-préparation-et-disque-p) · [Clé live (L)](#clé-live-l) · [Installation (I)](#installation-i) · [Démarrage (B)](#démarrage-b) · [Snapshots (S)](#snapshots-s) · [NVIDIA et portable (N)](#nvidia-et-portable-n) · [CachyOS (C)](#cachyos-c) · [Hyprland (H)](#hyprland-h) · [Général (G)](#général-g)

---

## Windows, préparation et disque (P)

### [P1] BitLocker actif / « Chiffrement de l'appareil »
- **Symptôme** : `manage-bde -status` indique « Protection activée », ou le preflight trouve une signature BitLocker.
- **Pourquoi c'est bloquant** : un changement de BIOS ou de démarrage peut déclencher la demande de clé de récupération BitLocker.
- **Faire** : dans Windows (admin), `manage-bde -off C:`, puis attendre que `manage-bde -status` affiche « Entièrement déchiffré ». Avant ça, noter la clé de récupération (compte Microsoft ou `manage-bde -protectors -get C:`).

### [P2] Windows refuse de réduire C: autant / « Pas assez de place »
- **Cause** : des fichiers impossibles à déplacer sont placés en fin de volume. Windows ne réduit pas au-delà.
- **Identifier le fichier qui bloque** : après chaque tentative de réduction, Windows note son nom dans le journal Applications (source « defrag », événement **259**). Pour le lire (PowerShell, sans droits administrateur) :
  ```powershell
  Get-WinEvent -FilterHashtable @{LogName='Application'; Id=259} -MaxEvents 1 | Select-Object -ExpandProperty Message
  ```
  La ligne « The last unmovable file appears to be » donne le coupable. Le traiter, puis relancer *Réduire le volume*. Plusieurs fichiers peuvent bloquer **à la suite** : refaire le cycle jusqu'à ce que ça passe.
- **Selon le fichier** (dans Windows, terminal administrateur) :

  | Fichier cité | Solution |
  |---|---|
  | `\$Extend\$UsnJrnl` (journal des modifications NTFS) | `fsutil usn deletejournal /d C:`, puis réduire. N'efface aucun fichier : Windows recrée le journal, la recherche réindexe. |
  | `\pagefile.sys` (fichier d'échange) | *SystemPropertiesPerformance → Advanced → Virtual memory → Change* → décocher « Automatically manage… » → C: → « No paging file » → Set → redémarrer → réduire → **tout recocher** et redémarrer. |
  | `\hiberfil.sys` | `powercfg /h off` |
  | `\System Volume Information\…` (points de restauration) | désactiver temporairement la protection du système pour C:, réduire, la réactiver. |
  | **`\$Mft`** (table principale NTFS) | **Windows ne sait pas la déplacer** : aucun réglage ne débloquera *Réduire le volume*. Passer à un outil hors Windows (ci-dessous). |

- **`$Mft` : réduire avec GParted Live (recommandé)**. Outil libre, sur la clé Ventoy : ISO depuis gparted.org, somme SHA256 vérifiée. Avant : `chkdsk C:` (lecture seule) sans erreur, fichier d'échange désactivé, chargeur branché, fichiers importants copiés hors du PC.
  1. Démarrer GParted (F11 → Ventoy), puis repérer `/dev/nvme0n1p3`, **ntfs**, environ 930 Gio (ni la partition de 100 Mio ni celle de 730 Mio).
  2. Clic droit → *Redimensionner/Déplacer* → **Espace libre suivant (Mio) = 257024**, *Espace libre précédent* laissé à **0**.
  3. *Appliquer*, puis attendre sans interrompre (de 15 minutes à plus d'une heure).
  4. De retour dans Windows : laisser finir une éventuelle vérification du disque, réactiver le fichier d'échange.
  - En cas d'erreur : photographier le message, **ne pas insister**.
- **AOMEI Partition Assistant Standard (gratuit, site officiel uniquement)** : alternative sous Windows. Constaté sur ce PC le 2026-11-21 : mode PreOS grisé, et le mode **Windows PE** plante au démarrage avec l'écran bleu **`DRIVER_VERIFIER_DMA_VIOLATION`**, deux fois. **Le disque n'a pas été modifié** (vérifié ensuite). C'est un conflit entre ce Windows PE et la protection DMA du PC (Intel VT-d). Contournement possible : désactiver **VT-d** dans le BIOS le temps de l'opération, puis le **réactiver**. Plus simple : GParted.
  - **Jamais de version « Technician » ou crackée** d'un outil de partitionnement : il a tous les droits sur le disque.
  - Après un échec : vérifier qu'aucune opération n'attend dans AOMEI, et qu'aucune entrée AOMEI / WinPE ne reste dans `msconfig` → Démarrage.
- **Ou bien** : accepter une racine plus petite. Dans `config.env`, `ROOT_SIZE_GIB=200` (minimum conseillé), ou `MAX` pour prendre tout le bloc libre.
- **Espace libre en deux morceaux** (le preflight montre plusieurs zones libres) : `plan` utilise uniquement le **plus grand bloc**. Si aucun bloc ne suffit, refaire la réduction.

### [P3] Le preflight affiche « PAS EN UEFI »
Voir [L3].

### [P4] Le NVMe n'apparaît pas dans `lsblk`
- **Cause probable** : contrôleur en mode Intel RST (RAID) / VMD dans le BIOS.
- **D'abord** : `# modprobe vmd`, puis `lsblk`. Le noyau Arch gère VMD : si le disque apparaît, rien à changer.
- **S'il n'apparaît toujours pas**, passer le BIOS en AHCI / désactiver VMD **sans casser Windows** :
  1. Dans Windows (admin) : `bcdedit /set {current} safeboot minimal`.
  2. Redémarrer → BIOS (Suppr) → désactiver VMD / RST (passer en AHCI) → enregistrer.
  3. Windows démarre en mode sans échec : il charge le pilote adapté.
  4. Dans Windows (admin) : `bcdedit /deletevalue {current} safeboot` → redémarrer.
- [À VÉRIFIER] Nom exact de l'option dans le BIOS du Cyborg 15. Ne pas l'activer ou la désactiver « pour voir ».

### [P5] Plusieurs ESP trouvées, ou pas de `EFI/Microsoft` dans l'ESP
- **Arrêter.** Ne pas partitionner.
- `lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,PARTLABEL` : repérer les partitions de type `c12a7328-…` (ESP).
- S'il en existe deux : une installation précédente (un ancien Linux, par exemple) en a peut-être laissé une. Identifier celle qui contient `EFI/Microsoft` (la monter en **lecture seule** : `mount -o ro /dev/nvme0n1pX /mnt/x`).
- Copier l'ESP Windows à la main vers le support de sauvegarde :
  ```
  cp -r /mnt/x/EFI /mnt/usb/dualboot-backup/esp-windows-manuel
  umount /mnt/x
  ```
- Une ancienne ESP Linux inutilisée peut rester en place : ne rien supprimer pendant l'installation.

### [P6] Le support de sauvegarde ne se monte pas
- `lsblk -f` : vérifier le nom (sdb1, sdc1…) et le type (`exfat`, `ntfs`, `vfat`, `ext4`).
- NTFS : `mount -t ntfs3 /dev/sdb1 /mnt/usb`. Si Windows avait mis ce disque en veille (hibernation) : le brancher sous Windows, puis le retirer avec « Éjecter ».
- Ne jamais choisir `nvme0n1…` comme support de sauvegarde.

### [P7] « Une partition porte déjà le nom ARCH-ESP / ARCH-ROOT »
- Une installation précédente a déjà créé ces partitions.
- Si c'est voulu (reprise après un échec à l'étape 3 ou 4) : sauter `create` et reprendre à `format`, ou à `mount` si le formatage était fait.
- Pour repartir de zéro : supprimer **seulement** ces deux partitions, après avoir vérifié leur numéro avec `sgdisk -p` :
  ```
  sgdisk -d N /dev/nvme0n1
  ```
  Puis relancer `plan`. Le faire une partition à la fois, en relisant le numéro à chaque fois.

### [P8] « UNE PARTITION EXISTANTE A CHANGÉ »
- **Ne rien faire de plus. Ne pas redémarrer.**
- La ligne affichée est la partition d'origine qui ne correspond plus. Comparer :
  ```
  sfdisk --dump /dev/nvme0n1
  cat /mnt/usb/dualboot-backup/preflight-*/nvme0n1-sfdisk.txt
  ```
- Si seule la **table** a changé (les données n'ont pas été écrites), restaurer la table sauvegardée :
  ```
  sgdisk --load-backup=/mnt/usb/dualboot-backup/preflight-DATE/nvme0n1-gpt.bak /dev/nvme0n1
  ```
  Cela retire aussi les 2 partitions Linux de la table.
- Redémarrer sur Windows pour vérifier. En dernier recours : restaurer l'image Clonezilla.

### [P9] `partprobe` : le noyau n'a pas pris en compte la nouvelle table
- Fréquent si une partition du disque est utilisée.
- `partprobe /dev/nvme0n1` à nouveau, puis `lsblk` : si ARCH-ESP et ARCH-ROOT apparaissent, continuer.
- Sinon : redémarrer la live (la table est déjà écrite sur le disque), puis :
  1. `loadkeys fr-latin9`, réseau, `git clone` ou copie du dépôt (étape 1). Remettre `config.env` dans le même état, en particulier `BACKUP_DIR`.
  2. Remonter le support de sauvegarde **au même endroit** (ex. `/mnt/usb`).
  3. Reprendre à `DRY_RUN=0 ./install/10-partition.sh format`.
- Le plan et la table « avant » sont aussi sur le support externe (`BACKUP_DIR/plan-partition/`). `format` les relit seul et refuse de formater s'il ne trouve aucune référence. Il refuse aussi si le disque n'est plus le même (modèle et numéro de série).

### [P10] mkfs : « appears to contain an existing filesystem »
- La zone contenait des données (ancienne partition à cet endroit).
- `wipefs -n /dev/nvme0n1pX` : regarder ce qui est détecté. Si c'est bien la **nouvelle** partition ARCH-ROOT (vérifier avec `lsblk -o NAME,SIZE,PARTLABEL`), relancer à la main :
  ```
  mkfs.btrfs -f -L archroot /dev/nvme0n1pX
  ```
  Ne jamais utiliser `-f` sans avoir vérifié PARTLABEL et taille.

---

## Clé live (L)

### [L1] La clé n'apparaît pas dans F11
- Prendre un port USB-A directement sur le PC (sans hub).
- BIOS : vérifier que le démarrage USB est autorisé et désactiver *Fast Boot*, qui peut sauter l'initialisation USB.
- Recréer la clé Ventoy (version récente).

### [L2] Écran noir ou blocage au démarrage de la live
- **Secure Boot activé** : Ventoy affiche une erreur de vérification. Le désactiver dans le BIOS.
- Blocage après « Loading initial ramdisk » : écran noir lié au GPU. Dans le menu de la live, appuyer sur `e` (ou Tab), ajouter `nomodeset` à la fin de la ligne du noyau, puis lancer. Cela ne concerne que la live.
- Dans Ventoy, essayer le mode *GRUB2* (touche indiquée en bas de l'écran Ventoy) si le mode normal échoue.

### [L3] Pas en UEFI (`/sys/firmware/efi` absent)
- La live a démarré en mode « Legacy / CSM ». Dans F11, choisir l'entrée qui commence par **UEFI:**. Dans le BIOS, désactiver *CSM* si l'option existe.
- **Ne jamais installer en mode Legacy** : Windows est en UEFI, GRUB doit l'être aussi.

### [L4] Pas de réseau
- `ip link` : l'interface Wi-Fi existe-t-elle ? (`wlan0`, ou un autre nom.)
- `rfkill list` : si « Soft blocked: yes », lancer `rfkill unblock all`. Si « Hard blocked: yes », c'est l'interrupteur ou la touche avion du portable.
- `iwctl` : mot de passe faux → `station wlan0 disconnect`, puis reconnecter.
- Réseau caché : `station wlan0 connect-hidden "Nom"`.
- **Plan B fiable** : téléphone Android branché en USB → *Partage de connexion USB*. L'interface `usb0` / `enp…u…` prend une adresse toute seule.
- DNS : `ping 1.1.1.1` répond mais `ping archlinux.org` échoue → `echo "nameserver 1.1.1.1" > /etc/resolv.conf`.
- Mot de passe Wi-Fi refusé alors qu'il est juste : le clavier est peut-être encore en QWERTY. Faire `loadkeys fr-latin9`, puis retaper le mot de passe.
- Wi-Fi avec **page de connexion** (hôtel, école, Wi-Fi public) ou **WPA-Enterprise / eduroam** : inutilisable simplement dans la live. Passer par le téléphone (partage USB Android ou point d'accès Wi-Fi).
- iPhone : préférer son **point d'accès Wi-Fi** au partage USB.
- Tous les cas, avec les commandes de vérification : [RESEAU.md](RESEAU.md).

### [L5] Récupérer le dépôt sans Internet / git indisponible
- Si `git` manque dans la live : `pacman -Sy git` (acceptable dans la live seulement).
- Sans réseau : copier le dossier `dualboot-arch` depuis Windows sur une clé (exFAT/FAT32), puis dans la live :
  ```
  mount /dev/sdb1 /mnt/usb
  cp -r /mnt/usb/dualboot-arch /root/
  find /root/dualboot-arch -name '*.sh' -exec chmod +x {} +
  sed -i 's/\r$//' /root/dualboot-arch/*.sh /root/dualboot-arch/*/*.sh /root/dualboot-arch/*.env
  ```
  La dernière ligne retire les fins de ligne Windows si un éditeur les a ajoutées. Sans elle : erreurs `$'\r': command not found`.

### [L6] Plus de place dans la live (« No space left on device »)
- La live tourne en RAM. `mount -o remount,size=2G /run/archiso/cowspace`.

---

## Installation (I)

### [I1] Erreurs de signature : « invalid or corrupted package (PGP signature) », « unknown trust », « key could not be looked up »
1. Vérifier l'heure : `timedatectl` (doit afficher `synchronized: yes`). Sinon : `timedatectl set-ntp true`, attendre une minute.
2. Mettre à jour le trousseau de la live :
   ```
   pacman -Sy archlinux-keyring
   ```
3. Si ça persiste :
   ```
   pacman-key --init
   pacman-key --populate archlinux
   ```
4. Relancer `20-base-install.sh` : pacstrap reprend là où il s'était arrêté, `--needed` est implicite. Si le script refuse à cause de fstab, voir [I3].

### [I2] Téléchargements lents ou « failed retrieving file »
- La live choisit les miroirs au démarrage avec reflector. Le relancer :
  ```
  reflector --country France,Germany --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
  ```
- Une coupure réseau au milieu : relancer simplement le script.

### [I3] « /mnt/etc/fstab contient déjà des entrées »
- Le script a déjà été lancé une fois. Lire le fichier : `cat /mnt/etc/fstab`.
- S'il est correct (5 lignes btrfs `subvol=/@…` sans `subvolid=`, plus `/efi`) : ne pas relancer le script. Faire seulement la copie du dépôt :
  ```
  mkdir -p /mnt/root/dualboot-arch
  cp -a /root/dualboot-arch/. /mnt/root/dualboot-arch/
  ```
- S'il est incorrect ou en double : `mv /mnt/etc/fstab /mnt/etc/fstab.raté`, puis relancer le script.

### [I4] `locale-gen` ne génère rien / avertissement de locale
- `grep -v '^#' /etc/locale.gen` (dans le chroot) doit lister `fr_FR.UTF-8 UTF-8` et `en_US.UTF-8 UTF-8`. Sinon, décommenter ces lignes avec `nano /etc/locale.gen`, puis relancer `locale-gen`.

### [I5] grub-install : « EFI variables are not supported on this system »
- La live n'a pas démarré en UEFI : voir [L3].
- Ou le chroot a été lancé avec `chroot` au lieu de `arch-chroot` : utiliser `arch-chroot`.

### [I6] grub-install : autre erreur, ou le script refuse (« /efi n'est pas l'ESP ARCHESP »)
- `findmnt /efi` dans le chroot doit montrer ARCHESP. Sinon, sortir du chroot, puis :
  ```
  umount -R /mnt
  ./install/10-partition.sh mount     # avec DRY_RUN=0
  ```
- « cannot find EFI directory » : `/efi` n'est pas monté.

### [I7] mkinitcpio : « ERROR: Hook 'grub-btrfs-overlayfs' cannot be found »
- Le paquet `grub-btrfs` manque : `pacman -S grub-btrfs` dans le chroot, puis `mkinitcpio -P`.
- Les avertissements « Possibly missing firmware for module » sont **sans gravité**.

---

## Démarrage (B)

### [B1] Le PC démarre Windows directement, sans GRUB
- Le firmware a mis *Windows Boot Manager* en premier.
- **F11** → choisir `ARCH-GRUB` : si GRUB s'affiche, l'installation est bonne.
- Pour que ce soit permanent : BIOS → *Boot* → priorité / *UEFI Hard Disk Drive BBS Priorities* → `ARCH-GRUB` en premier.
- Si `ARCH-GRUB` n'existe pas du tout : clé live → `rescue/chroot-repair.sh shell` →
  ```
  grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=ARCH-GRUB --removable
  ```
  Cette commande écrit sur l'ESP **Linux** seulement. Choisir ensuite la partition dans F11.
- Les mises à jour de Windows peuvent remettre Windows en premier : même remède.
- **Recréer seulement l'entrée UEFI** (GRUB est intact sur l'ESP Linux, mais l'entrée a disparu de la liste du firmware). Depuis Arch ou depuis la live :
  ```
  lsblk -o NAME,PARTLABEL,LABEL          # repérer la partition ARCH-ESP : ex. nvme0n1p5 → numéro 5
  ls /efi/EFI/ARCH-GRUB/                 # (live : monter d'abord ARCHESP) doit contenir grubx64.efi
  efibootmgr -c -d /dev/nvme0n1 -p 5 -L "ARCH-GRUB" -l '\EFI\ARCH-GRUB\grubx64.efi'
  efibootmgr                             # l'entrée apparaît
  ```
  Remplacer `5` par le **vrai** numéro de la partition ARCH-ESP. Le chemin doit être celui de `--bootloader-id=ARCH-GRUB`. Ne pas copier une commande trouvée ailleurs avec `-p 1` : sur un PC livré avec Windows, la partition 1 est en général l'ESP **Windows**.
  Plus simple et équivalent : `DRY_RUN=0 ./rescue/chroot-repair.sh grub`, qui recrée l'entrée.

### [B2] `grub rescue>` ou « error: no such device » / « unknown filesystem »
- GRUB ne trouve plus `/@/boot/grub`, souvent après une manipulation de `@`.
- Clé live → `DRY_RUN=0 ./rescue/chroot-repair.sh grub`. Sans le dépôt : [RECOVERY.md](RECOVERY.md), niveau 3.

### [B3] Écran noir après GRUB
- Dans GRUB, sur *Arch Linux*, appuyer sur `e`. Sur la ligne `linux …`, ajouter `nomodeset` à la fin, puis Ctrl+X. Le système démarre en mode graphique de base. Le vrai correctif est l'étape 8 (pilotes NVIDIA).
- Essayer aussi *Advanced options* → `linux-lts`.
- Ctrl+Alt+F2 donne-t-il une console ? Si oui, le système tourne : seul l'affichage pose problème.

### [B4] « You are in emergency mode »
- Taper le **mot de passe root**, puis :
  ```
  journalctl -xb | grep -iE 'fail|error' | head -30
  cat /etc/fstab
  ```
- Cause fréquente : une ligne de fstab incorrecte (sous-volume mal nommé, UUID faux). Comparer avec `blkid` et `btrfs subvolume list /`.
- Corriger avec `nano /etc/fstab`, puis `systemctl daemon-reload && mount -a`, puis `reboot`.
- Mot de passe root oublié : clé live → `rescue/chroot-repair.sh shell` → `passwd`.

### [B5] Pas de réseau sur l'Arch installé
- `systemctl status NetworkManager` : s'il est inactif, `sudo systemctl enable --now NetworkManager`.
- Wi-Fi : `nmcli device wifi list`, puis `nmcli device wifi connect "Nom" --ask`. Pour un menu : `nmtui`.
- Carte Wi-Fi absente : `ip link` et `dmesg | grep -i firmware` (paquet `linux-firmware`). Le partage USB du téléphone marche aussi ici.

### [B6] Windows absent du menu GRUB
- Vérifier `grep OS_PROBER /etc/default/grub` → `GRUB_DISABLE_OS_PROBER=false`.
- `sudo os-prober` doit afficher une ligne Windows. Si rien n'apparaît : Windows en hibernation ou démarrage rapide ([P1] et étape 0).
- Puis `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
- En attendant : F11 → *Windows Boot Manager* fonctionne toujours.

### [B7] Heure fausse dans Windows ou dans Arch
- La clé `RealTimeIsUniversal` de l'étape 0 n'a pas été appliquée : la relancer dans Windows (admin), puis redémarrer.
- Dans Arch : `timedatectl` doit afficher `RTC in local TZ: no` et `NTP service: active`. Sinon, `sudo timedatectl set-ntp true`.

### [B8] `~/dualboot-arch` absent
- `sudo cp -a /root/dualboot-arch ~/ && sudo chown -R $USER: ~/dualboot-arch`.
- Ou bien `git clone` à nouveau (étape 1). La progression `.etat` est alors perdue : valider de nouveau les étapes faites avec `./guide.sh valider N`.

---

## Snapshots (S)

### [S1] `snapper create-config` : « creating btrfs subvolume .snapshots failed since it already exists »
- `/.snapshots` existe encore. Vérifier : `findmnt /.snapshots` et `ls -A /.snapshots`.
- S'il est monté : `sudo umount /.snapshots`. S'il est vide : `sudo rmdir /.snapshots`. Puis relancer le script.
- S'il n'est **pas vide**, ne rien supprimer : il contient peut-être déjà des snapshots.

### [S2] Le script dit « La config snapper root existe déjà »
- La configuration est déjà faite. Vérifier qu'elle est complète :
  ```
  sudo snapper -c root get-config | grep -E 'TIMELINE|NUMBER_LIMIT'
  findmnt /.snapshots                  # doit montrer [/@snapshots]
  ```
- Si `/.snapshots` n'est pas `@snapshots` mais un sous-volume imbriqué (`btrfs subvolume list /` affiche `@/.snapshots`) : refaire 7.1 à la main en suivant le script ligne par ligne.

### [S3] `snapper list` : « No permissions » en utilisateur
- Utiliser `sudo`, ou vérifier `ALLOW_USERS` : `sudo snapper -c root set-config ALLOW_USERS=$USER`.

### [S4] Pas de snapshot pre/post après `pacman`
- `pacman -Q snap-pac` : le paquet est-il installé ?
- La config doit s'appeler exactement `root` : `sudo snapper list-configs`.
- `pacman -Ss` et `-Q` ne créent pas de snapshot (normal) : seules les installations, mises à jour et suppressions en créent.

### [S5] Pas d'entrée « Arch Linux snapshots » dans GRUB
- `systemctl status grub-btrfsd` → si inactif : `sudo systemctl enable --now grub-btrfsd`.
- Forcer la génération : `sudo grub-mkconfig -o /boot/grub/grub.cfg`. La sortie doit lister « Found snapshot: … ».
- Pas de « Found snapshot » : `sudo snapper -c root list` (y a-t-il des snapshots ?) et `pacman -Q inotify-tools`.

### [S6] Un snapshot démarre mais échoue (lecture seule, services en échec, « read-only file system »)
- Les snapshots sont en lecture seule. Le hook `grub-btrfs-overlayfs` ajoute une couche en RAM pour pouvoir démarrer.
- Vérifier : `grep ^HOOKS /etc/mkinitcpio.conf` → `grub-btrfs-overlayfs` en dernier, et `udev` (pas `systemd`). Puis `sudo mkinitcpio -P`.
- **Important** : chaque snapshot contient son propre initramfs. Un snapshot pris **avant** la correction gardera le problème. Seuls les nouveaux snapshots en profitent.

### [S7] Disque plein à cause des snapshots
- Contrôler :
  ```
  sudo btrfs filesystem usage /
  sudo snapper -c root list
  ```
- Supprimer des snapshots **non jalons** : `sudo snapper -c root delete N` ou une plage `N1-N2`. Ne **jamais** supprimer un `JALON`.
- Baisser les limites : `sudo snapper -c root set-config NUMBER_LIMIT=10 TIMELINE_LIMIT_HOURLY=3`.
- Les gros dossiers qui changent sans cesse (Steam, VM, Docker, modèles IA) ne doivent pas être dans `@`. Leur faire un sous-volume dédié, hors snapshots (brief §2.3).
- `/home` n'est pas dans les snapshots système : y supprimer des fichiers ne libère pas l'espace tenu par les snapshots de `@`.

### [S8] `snapper undochange` ou `snapper rollback` ?
- `undochange N..0` remet les **fichiers** dans leur état du snapshot N, **sans redémarrer**. C'est pratique pour un fichier de config. À éviter pour une mise à jour système complète (noyau ou bibliothèques en cours d'utilisation).
- `snapper rollback` : **ne pas l'utiliser** avec ce layout. Il change le sous-volume par défaut, alors que GRUB et fstab utilisent `subvol=@`. Utiliser `rescue/restore-snapshot.sh` (RECOVERY.md, niveau 2).

### [S9] Après une restauration, `/home` ou `/.snapshots` n'est pas monté
- `cat /etc/fstab` : le fichier du snapshot restauré doit utiliser `subvol=/@…` sans `subvolid=`.
- Si `/.snapshots` manque : `sudo mkdir /.snapshots && sudo mount -a`.

---

## NVIDIA et portable (N)

### [N1] `nvidia-smi` : « couldn't communicate with the NVIDIA driver »
1. A-t-on redémarré depuis l'installation ? Sinon, redémarrer.
2. `lsmod | grep nvidia` : rien ? Alors `sudo modprobe nvidia` et lire l'erreur.
3. Bon noyau ? `uname -r`. Pour `linux-lts`, le paquet `nvidia-open-lts` doit être installé (`pacman -Q nvidia-open-lts`). Pour `linux-cachyos` : `linux-cachyos-nvidia-open`.
4. Secure Boot réactivé par erreur : module refusé (`dmesg | grep -i nvidia`). Le désactiver.
5. `lsmod | grep nouveau` ne doit rien afficher (nvidia-utils le met en liste noire).

### [N2] La dGPU ne passe jamais en `suspended` (batterie qui fond)
- Qui l'utilise ? `sudo lsof +c0 /dev/nvidia*`. Un navigateur ou un programme lancé avec `prime-run` la garde allumée.
- `cat /proc/driver/nvidia/gpus/<adresse>/power` : si « Runtime D3 status: Not supported », suivre la section « PCI-Express Runtime D3 (RTD3) Power Management » du wiki Arch **PRIME**.
- Ne pas installer `nvidia-prime-rtd3pm` ou des options `NVreg_*` sans avoir d'abord constaté le problème. Sur Ada, c'est actif par défaut.

### [N3] Écran externe (HDMI / USB-C) sans image
- La sortie est probablement câblée sur la NVIDIA. Il faut :
  - que la NVIDIA soit dans `AQ_DRM_DEVICES` : `cat ~/.config/uwsm/env-hyprland` → `…intel-igpu:/dev/dri/nvidia-dgpu` ;
  - que `/dev/dri/nvidia-dgpu` existe (`ls -l /dev/dri/`).
- Sinon : `sudo DRY_RUN=0 ./post/50-hardware-laptop.sh udev`, puis se reconnecter.
- Noter le résultat dans HARDWARE.md : sortie câblée sur l'iGPU ou sur la dGPU.

### [N4] Problème au réveil de veille (écran noir, artefacts)
- Lire « NVIDIA/Tips and tricks → Preserve video memory after suspend » sur le wiki Arch.
- Vérifier `systemctl is-enabled nvidia-suspend nvidia-resume`.
- [À VÉRIFIER] Si ces services sont activés par défaut par `nvidia-utils` dans la version installée.

### [N5] `prime-run` : « command not found »
- `sudo pacman -S nvidia-prime`.

### [N6] Ventilateurs, seuil de charge, rétroéclairage MSI
- Le pilote `msi-ec` doit **explicitement** supporter le Cyborg 15 A12VF (liste des modèles et versions de firmware EC dans son dépôt). Sinon, ne pas l'utiliser : une écriture dans l'EC d'un modèle non supporté peut dérégler les ventilateurs.

---

## CachyOS (C)

### [C1] Le script ne trouve pas ou ne peut pas importer la clé
- Heure fausse : voir [I1].
- Serveur de clés indisponible : relancer plus tard, ou suivre la procédure **manuelle** de la page officielle (wiki.cachyos.org → Optimized repositories, onglet *Manual*).

### [C2] `pacman -Syu` après ajout des dépôts : conflits, « are in conflict », « file exists in filesystem »
- **Ne pas** utiliser `--overwrite` ni `-dd` sans comprendre le conflit.
- Copier le message exact, chercher le paquet sur le forum ou Discord CachyOS.
- Revenir en arrière proprement : GRUB → snapshot `JALON 02`, puis `rescue/restore-snapshot.sh` avec son numéro.

### [C3] Le noyau `linux-cachyos` ne démarre pas, ou NVIDIA KO dessus
- GRUB → *Advanced options* → `linux` ou `linux-lts` : ils restent fonctionnels.
- `pacman -Q linux-cachyos linux-cachyos-nvidia-open` : les deux versions doivent correspondre.
- Désinstaller seulement le noyau : `sudo pacman -R linux-cachyos linux-cachyos-headers linux-cachyos-nvidia-open`, puis `sudo grub-mkconfig -o /boot/grub/grub.cfg`.

### [C4] Retirer complètement CachyOS
- Option propre : restaurer le JALON 02.
- Option sur place : `sudo DRY_RUN=0 ./post/60-cachyos-repo.sh remove` (script officiel `--remove`), puis `sudo pacman -Syu`.

### [C5] `check` affiche `x86-64-v4 (supported)`
- Inattendu sur un i7 de 12e génération : le wiki CachyOS indique que l'AVX-512 y est désactivé. Ne pas choisir v4 : rester sur v3, et le noter dans HARDWARE.md.

---

## Hyprland (H)

### [H1] Rien ne se passe sur tty1 après connexion
- `cat ~/.bash_profile` : le bloc `uwsm` est-il présent ?
- Tester à la main : `uwsm check may-start`, puis `uwsm start hyprland.desktop`, et lire l'erreur.
- Le bloc ne s'active que sur **tty1** (voulu). Sur un autre tty, c'est normal qu'il ne se lance pas.

### [H2] Hyprland démarre puis écran noir ou retour au tty
- Ctrl+Alt+F2 → se connecter :
  ```
  journalctl --user -b | tail -50
  ```
- Config cassée : la mettre de côté, Hyprland en regénérera une :
  ```
  mv ~/.config/hypr ~/.config/hypr.cassee
  ```
- Problème GPU : vérifier `cat ~/.config/uwsm/env-hyprland` et `ls -l /dev/dri/intel-igpu`.

### [H3] Bandeau rouge ou erreur de configuration
- Lire le message : il indique le fichier et la ligne Lua.
- Raccourcis de secours si la config a échoué avant les raccourcis : **SUPER+Q** (terminal), **SUPER+M** (quitter).
- `hyprctl reload` après correction.

### [H4] sway (session de secours) refuse de démarrer
- Message à propos du pilote propriétaire NVIDIA : lancer `sway --unsupported-gpu`.
- [À VÉRIFIER] Si `WLR_DRM_DEVICES=/dev/dri/intel-igpu sway` suffit sans l'option.
- Toujours possible en dernier recours : travailler en console sur tty2.

### [H5] Clavier en QWERTY dans Hyprland
- Option `kb_layout` dans la section *input* de `hyprland.lua`. Syntaxe exacte : wiki Hyprland de ta version → *Configuring → Config options*.

### [H6] Pas de fenêtre de mot de passe (polkit) dans les applications
- `systemctl --user status hyprpolkitagent` → si inactif : `systemctl --user enable --now hyprpolkitagent`.

### [H7] Partage d'écran ou sélecteur de fichiers absent
- `pacman -Q xdg-desktop-portal-hyprland xdg-desktop-portal-gtk`.
- Redémarrer la session (`uwsm stop`, puis se reconnecter).

---

## Général (G)

### [G1] « unable to lock database » (`/var/lib/pacman/db.lck`)
- Un autre pacman tourne-t-il ? `ps aux | grep -E 'pacman|paru|yay'`.
- Si **aucun** ne tourne (par exemple après une coupure) : `sudo rm /var/lib/pacman/db.lck`.

### [G2] Mise à jour interrompue (coupure de courant, plantage)
- Ne pas paniquer : snap-pac a fait un snapshot `pre`.
- Si le système démarre : `sudo pacman -Syu` relance la mise à jour.
- S'il ne démarre plus : GRUB → snapshot `pre` de cette mise à jour → puis restauration (RECOVERY.md, niveau 2).

### [G3] Fichiers `.pacnew`
- `sudo pacdiff` : comparer et fusionner. Ne jamais écraser sans lire, surtout pour `pacman.conf`, `mkinitcpio.conf`, `default/grub` et `fstab`.

### [G4] Le système a beaucoup de retard (plusieurs mois sans mise à jour)
- `sudo pacman -Sy archlinux-keyring && sudo pacman -Syu`. C'est l'exception autorisée à « jamais -Sy seul » : le `-Syu` suit immédiatement.
- Lire toutes les actualités Arch de la période.

### [G5] Mettre à jour ce guide sur la machine
- `cd ~/dualboot-arch && git pull`. Les fichiers locaux modifiés (`config.env`, `JOURNAL.md`) peuvent bloquer :
  ```
  git stash
  git pull
  git stash pop
  ```

### [G6] Quelque chose n'est pas dans ce document
1. Noter la commande et le message exact dans JOURNAL.md.
2. Revenir au dernier état sûr si besoin (snapshot).
3. Chercher le message exact sur le wiki Arch et le forum (bbs.archlinux.org), puis sur le wiki CachyOS ou Hyprland selon la partie concernée.
4. Ajouter la solution ici, avec un nouveau code, pour la prochaine fois.
