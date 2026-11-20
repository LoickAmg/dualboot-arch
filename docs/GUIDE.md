# Guide pas à pas — Windows + Arch (Btrfs, snapshots) + CachyOS + Hyprland

Ce guide se suffit à lui-même : tu peux le suivre seul, du début à la fin. Sur la machine, `./guide.sh` te dit où tu en es et quelle commande lancer ensuite.

**Comment lire chaque étape**

- **Pourquoi** : à quoi sert l'étape.
- **Commandes** : à taper telles quelles, depuis le dossier du dépôt.
- **Ce que tu dois voir** : le résultat normal.
- **Point de contrôle** : ce qui doit être vrai avant de passer à la suite. Ensuite : `./guide.sh valider N`.
- **Si ça ne va pas** : renvoi vers [DEPANNAGE.md](DEPANNAGE.md), avec un code du type `[P3]`.

**Trois règles qui ne changent jamais**

1. Sans `DRY_RUN=0`, un script **montre** ce qu'il ferait et ne touche à rien. Lance-le toujours d'abord sans, lis la sortie, puis relance avec `DRY_RUN=0`.
2. Quand un script demande `OUI`, relis ce qu'il affiche juste au-dessus. En cas de doute, tape autre chose : il s'arrête proprement.
3. Un changement à la fois, puis un test, puis un jalon (snapshot permanent).

**Notation**

- `$` : commande en utilisateur normal ; `#` : commande en root. Dans la clé live, tu es déjà root.
- Avec `sudo`, `DRY_RUN=0` se place **après** sudo : `sudo DRY_RUN=0 ./script.sh`. Placé avant, sudo l'efface et le script reste en simulation.

**Pourquoi pas `archinstall` ?** Il fonctionne, mais par défaut il met les noyaux sur l'ESP (hors des snapshots), peut réutiliser l'ESP de Windows, et son fstab contient des `subvolid=`. Avec ces trois points, un retour arrière peut redémarrer un noyau qui ne correspond plus à ses modules NVIDIA. Les étapes 1 à 5 de ce guide font une installation **minimale** équivalente, avec le bon découpage. Tout le reste (snapshots, CachyOS, Hyprland) vient ensuite, par-dessus.

Pour comprendre les snapshots avant de commencer : [COMPRENDRE-SNAPSHOTS.md](COMPRENDRE-SNAPSHOTS.md).

> **Installation directe sur la vraie machine (sans répétition en VM)**
> Les scripts n'ont pas encore tourné sur ce PC. Pour compenser :
> 1. **Image Clonezilla vérifiée obligatoire** avant l'étape 1. C'est le seul retour arrière possible si l'étape 3 tourne mal.
> 2. **Chaque script d'abord en simulation** (sans `DRY_RUN=0`) : lire ce qu'il affiche. Cette simulation tient lieu de répétition.
> 3. Si un script des étapes 3 à 5 plante : ne pas improviser. Suivre [MANUEL.md](MANUEL.md), qui donne les mêmes opérations commande par commande, avec un contrôle après chacune.
> 4. Noter chaque erreur, même contournée, dans [JOURNAL.md](JOURNAL.md) : elle servira à corriger le script.
> 5. Après l'étape 6, l'assistant peut être réinstallé sur l'Arch pour la suite : voir [REPRISE.md](REPRISE.md).

---

## Matériel nécessaire

- Clé USB **Ventoy** avec l'ISO Arch officielle, Clonezilla et une ISO Windows de secours.
- **Un second support externe** (clé ou disque) pour les sauvegardes : image Clonezilla, table de partitions, copie de l'ESP Windows. Ne pas utiliser la partition Ventoy : elle peut être occupée pendant que la live tourne.
- Ethernet ou Wi-Fi. À défaut, le partage de connexion USB d'un téléphone Android marche directement dans la live.
- Ce guide imprimé ou ouvert sur le téléphone, ainsi que [RECOVERY.md](RECOVERY.md).

---

## Étape 0 — Préparer Windows

**Pourquoi** : Windows ne doit rien bloquer (hibernation, chiffrement), et il faut un espace vide pour Linux plus une image complète pour revenir en arrière.

Tout se fait **dans Windows**, dans un terminal **administrateur** (PowerShell) :

1. **Image complète du disque** avec Clonezilla (démarré depuis la Ventoy), vers le support externe. Puis **vérifier l'image** : Clonezilla le propose à la fin (*check the saved image*). C'est le filet ultime. Le réglage Ghost Spectre + Atlas est long à refaire.
2. **Hibernation et démarrage rapide** :
   ```powershell
   powercfg /a
   powercfg /h off
   ```
   Après `powercfg /h off`, la ligne « Hibernation » de `powercfg /a` doit être indisponible.
3. **BitLocker / chiffrement de l'appareil** :
   ```powershell
   manage-bde -status
   ```
   Il faut lire « Protection désactivée » ou « Entièrement déchiffré » pour C:. Sinon : `manage-bde -off C:`, puis attendre la fin du déchiffrement (relancer `-status`). [P1]
4. **Horloge en UTC**, pour que Windows et Linux affichent la même heure :
   ```powershell
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
   ```
5. **Réduire C:** : Gestion des disques (`diskmgmt.msc`) → clic droit sur C: → *Réduire le volume* → 256 000 Mo ou plus (1 GiB d'ESP + 250 GiB de racine). **Ne rien créer** dans l'espace libéré : il doit rester « Non alloué ». Si Windows refuse de réduire autant : [P2].
6. Noter dans [HARDWARE.md](HARDWARE.md) : taille de l'ESP, espace non alloué, résultat de `reagentc /info`.
7. **Ne pas mettre à jour Windows ni AtlasOS** pendant toute l'installation.

**BIOS** (touche **Suppr** au logo MSI ; **F11** = menu de démarrage) :
- **Secure Boot : désactivé** (le réactiver plus tard n'est pas prévu dans cette version).
- Si une option **Intel VMD / RST** est active, la live ne verra pas le NVMe : lire [P4] **avant** de la changer. Changer ce réglage sans préparation empêche Windows de démarrer.
- Noter s'il existe une option de **MUX / GPU mode** (dans HARDWARE.md). Ne pas la modifier.

**Point de contrôle** : image Clonezilla vérifiée, BitLocker désactivé, hibernation désactivée, ≥ 250 Go non alloués, Secure Boot désactivé.

Optionnel : [VM.md](VM.md) déroule tout ce guide dans une VM avec un faux Windows, pour s'entraîner avant.

---

## Étape 1 — Clé live : réseau, dépôt, état de la machine

**Pourquoi** : démarrer la live, récupérer ce dépôt et vérifier que la machine est dans l'état attendu, sans rien écrire.

1. Brancher la Ventoy, allumer, **F11**, choisir la clé (entrée UEFI) puis l'ISO Arch → *Arch Linux install medium*. Si la clé n'apparaît pas ou que l'écran reste noir : [L1] [L2].
2. Clavier AZERTY :
   ```
   # loadkeys fr-latin9
   ```
3. Vérifier le mode UEFI : `ls /sys/firmware/efi` doit lister des fichiers. Sinon : [L3].
4. Réseau. La carte Wi-Fi de ce PC (Intel AX201) fonctionne directement dans la live : **ni câble ni VM nécessaires**. Détails, cas particuliers (Wi-Fi d'hôtel, eduroam, iPhone) et volume de données : [RESEAU.md](RESEAU.md).
   - Câble Ethernet ou partage USB d'un téléphone Android : rien à faire.
   - Wi-Fi (`loadkeys fr-latin9` **avant**, sinon le mot de passe est tapé en QWERTY) :
     ```
     # iwctl
     [iwd]# device list
     [iwd]# station wlan0 scan
     [iwd]# station wlan0 get-networks
     [iwd]# station wlan0 connect "NomDuReseau"
     [iwd]# exit
     # ping -c3 archlinux.org
     ```
   Si ça ne marche pas : [L4].
5. Heure : `timedatectl` doit afficher `System clock synchronized: yes` au bout d'une minute. Une heure fausse casse les signatures de paquets ([I1]).
6. Récupérer le dépôt :
   - **Dépôt public** :
     ```
     # cd /root
     # git clone https://github.com/LoickAmg/dualboot-arch.git
     ```
   - **Dépôt privé** : sur github.com, créer d'abord un *fine-grained token* en lecture seule sur ce dépôt (Settings → Developer settings → Personal access tokens), avec une expiration de 7 jours. Puis :
     ```
     # git clone https://LoickAmg@github.com/LoickAmg/dualboot-arch.git
     ```
     Au mot de passe, coller le **token** (pas le mot de passe GitHub). Le révoquer après l'installation.
   - **Sans réseau** : voir [L5] (copie depuis une clé USB).
   ```
   # cd /root/dualboot-arch
   # ./guide.sh
   ```
7. Remplir la configuration :
   ```
   # nano config.env
   ```
   Renseigner `HOSTNAME_NEW`, `USERNAME_NEW` (minuscules, sans espace), `KEYMAP` (`fr-latin9` pour l'AZERTY), `XKB_LAYOUT` (`fr`), `BACKUP_DIR` (voir l'étape 2). Vérifier `TIMEZONE` et `ROOT_SIZE_GIB`. Enregistrer : Ctrl+O, Entrée, Ctrl+X.
8. État de la machine (lecture seule) :
   ```
   # ./install/00-preflight-live.sh | less
   ```

**Ce que tu dois voir** :
- `UEFI OK` et `Secure Boot : désactivé`.
- Ton modèle MSI, ainsi que `x86-64-v3 (supported, searched)`.
- `nvme0n1` avec les partitions Windows : une ESP d'environ 100 à 300 Mo, MSR, C:, récupération.
- Un **plus grand bloc libre** d'au moins 250 Go.
- **Une seule** ligne sous « Partitions ESP ».
- `aucun détecté` pour BitLocker et `réseau OK`.

**Point de contrôle** : tous ces points sont vrais. Recopier dans HARDWARE.md le modèle, le CPU, les adresses PCI des GPU et les PARTUUID des partitions Windows. En cas d'écart : [P1] à [P5].

---

## Étape 2 — Sauvegarder la table de partitions et l'ESP Windows

**Pourquoi** : avant toute écriture sur le disque, garder une copie de la table GPT (la carte des partitions) et du chargeur de Windows, sur un support **externe**.

1. Brancher le support de sauvegarde et le monter :
   ```
   # lsblk -f                          # repérer le support (ex. sdb1), PAS nvme0n1
   # mkdir -p /mnt/usb
   # mount /dev/sdb1 /mnt/usb          # adapter le nom
   # mkdir -p /mnt/usb/dualboot-backup
   ```
   Dans `config.env` : `BACKUP_DIR="/mnt/usb/dualboot-backup"`. Si `/mnt/usb` ne se monte pas : [P6].
2. Simulation, puis exécution réelle :
   ```
   # ./install/00-preflight-live.sh backup
   # DRY_RUN=0 ./install/00-preflight-live.sh backup
   ```

**Ce que tu dois voir** :
- `Copie identique à l'original (diff -r).` puis `Terminé et vérifié` ;
- un dossier `preflight-DATE/` qui contient `rapport.txt`, `nvme0n1-gpt.bak`, `nvme0n1-sfdisk.txt`, `esp-windows-EFI/Microsoft/...` et `SHA256SUMS`.

La moindre erreur (copie incomplète, ESP sans `bootmgfw.efi`, support de sauvegarde situé sur le NVMe) **arrête** le script : une sauvegarde n'est jamais annoncée réussie si elle ne l'est pas.
```
# ls -R /mnt/usb/dualboot-backup | head -30
```
Si le script signale « 2 ESP trouvées » ou « Pas de EFI/Microsoft » : [P5].

**Point de contrôle** : les 4 fichiers et le dossier EFI sont présents sur le support externe. **Laisser ce support branché** jusqu'à la fin de l'étape 3.

---

## Étape 3 — Partitionner, formater, monter

**Pourquoi** : créer les 2 partitions Linux dans l'espace libre (ESP Linux de 1 GiB + racine Btrfs), puis les sous-volumes qui rendent les snapshots possibles. Windows n'est pas touché, et le script le vérifie.

Cinq sous-étapes. Chacune affiche d'abord ce qu'elle va faire.

**3.1 Plan (lecture seule)**
```
# ./install/10-partition.sh plan
```
Tu dois voir :
- la liste des partitions existantes (« NE SERONT PAS TOUCHÉES ») ;
- deux lignes de plan (`ESP Linux` 1024 MiB, `Racine` 250 GiB) ;
- deux commandes `sgdisk -n 0:DÉBUT:FIN ...`.

Vérifier que les secteurs de début sont **après** la fin de la dernière partition Windows, ou dans le trou laissé par la réduction de C:.
Le plan est aussi copié sur le support de sauvegarde (`plan-partition/`), avec le modèle et le numéro de série du disque. Les sous-étapes suivantes refusent de tourner sur un autre disque.
Si « Pas assez de place » : [P2]. Si « Une partition porte déjà le nom » : [P7].

**3.2 Création des partitions**
```
# DRY_RUN=0 ./install/10-partition.sh create
```
Taper `OUI` après avoir relu. Tu dois voir : `Contrôle OK : partitions existantes identiques octet pour octet (sfdisk --dump), 2 ajoutées.`
- « La table a changé depuis le plan » : relancer `plan`.
- « UNE PARTITION EXISTANTE A CHANGÉ » : **arrêter tout**, ne pas redémarrer, lire [P8].
- Avertissement de `partprobe` sur le noyau qui n'a pas relu la table : [P9].

**3.3 Formatage**
```
# DRY_RUN=0 ./install/10-partition.sh format
```
Vérifier que les 2 cibles affichées sont bien `ARCH-ESP` (1G) et `ARCH-ROOT` (250G), puis taper `OUI`. Si mkfs signale un système de fichiers déjà présent : [P10].

**3.4 Sous-volumes**
```
# DRY_RUN=0 ./install/10-partition.sh subvols
```
Tu dois voir la liste `@`, `@home`, `@snapshots`, `@var_log` et `@pkg`.

**3.5 Montage**
```
# DRY_RUN=0 ./install/10-partition.sh mount
```

**Point de contrôle** : `lsblk -f` montre la nouvelle racine montée sur `/mnt`, `/mnt/home`, `/mnt/.snapshots`, `/mnt/var/log` et `/mnt/var/cache/pacman/pkg`, et l'ESP Linux (ARCHESP) sur `/mnt/efi`. Les partitions Windows ont toujours leur taille d'origine. `./guide.sh valider 3`.

Si un des scripts de cette étape plante : [MANUEL.md](MANUEL.md), section 3, reprise à la sous-étape où il s'est arrêté.

---

## Étape 4 — Installer la base Arch

**Pourquoi** : installer le strict minimum, avec deux noyaux (`linux` et `linux-lts`, le second servant de secours) et les outils de snapshots.

```
# DRY_RUN=0 ./install/20-base-install.sh
```
Durée : 5 à 20 minutes selon la connexion.

**Ce que tu dois voir** :
- pacstrap qui se termine sans `error:` ;
- puis le contenu de `/mnt/etc/fstab` : 5 lignes `btrfs` avec `subvol=/@`, `/@home`, `/@snapshots`, `/@var_log` et `/@pkg`, plus une ligne `vfat` pour `/efi` ;
- enfin `fstab : 5 sous-volumes présents, aucun subvolid=`.

Erreurs de clés ou de paquets corrompus : [I1]. Téléchargement lent ou en échec : [I2]. « fstab contient déjà des entrées » : [I3].

**Point de contrôle** : le message de contrôle fstab est OK. `./guide.sh valider 4`.

Si le script plante : [MANUEL.md](MANUEL.md), section 4.

---

## Étape 5 — Configurer le système et GRUB

**Pourquoi** : régler la langue, l'heure, le nom de machine, les comptes et la mémoire zram, préparer l'initramfs pour démarrer les snapshots, puis installer GRUB sur l'ESP **Linux**.

```
# arch-chroot /mnt env DRY_RUN=0 /root/dualboot-arch/install/30-chroot-config.sh
```
Le script demande :
1. le **mot de passe root** (deux fois). Il sert au mode de secours systemd : le noter dans un endroit sûr ;
2. le **mot de passe de ton utilisateur** (deux fois) ;
3. `OUI` pour installer GRUB.

**Ce que tu dois voir** :
- `mkinitcpio` qui génère 4 images (linux, linux-fallback, linux-lts, linux-lts-fallback) sans `ERROR` ;
- `grub-install` : `Installation finished. No error reported.` ;
- `grub-mkconfig` : les lignes `Found linux image` pour les deux noyaux ;
- `Windows détecté par os-prober`, ou bien l'avertissement « Windows non détecté dans le chroot ». Cet avertissement est **normal** : on corrige à l'étape 6.

Problèmes : [I4] (locale), [I5] (EFI variables), [I6] (grub-install), [I7] (mkinitcpio).

Puis :
```
# exit            # seulement si tu es resté dans le chroot
# umount -R /mnt
# reboot
```
Retirer la clé au redémarrage.

**Point de contrôle** : le script s'est terminé avec le texte « Point de contrôle phase 3 ». `./guide.sh valider 5`, **avant** `reboot` (la validation est reportée dans les copies posées sur /mnt).

Si le script plante : [MANUEL.md](MANUEL.md), section 5. On peut y reprendre bloc par bloc : ce qui a déjà été fait ne gêne pas.

---

## Étape 6 — Premier démarrage : Arch ET Windows

**Pourquoi** : prouver que les deux systèmes démarrent, avant de construire quoi que ce soit par-dessus.

1. Le menu **GRUB** apparaît. S'il n'apparaît pas et que Windows démarre directement : [B1]. S'il affiche `grub rescue>` : [B2].
2. Choisir *Arch Linux*, puis se connecter avec ton utilisateur.
   - Écran noir après GRUB : [B3].
   - Mode d'urgence (*emergency mode*) : [B4].
3. Réseau :
   ```
   $ nmcli device wifi connect "NomDuReseau" --ask
   $ ping -c3 archlinux.org
   ```
   (`nmtui` propose la même chose en menus.) Sur le système installé, c'est NetworkManager qui gère le réseau, plus `iwctl`. La connexion est mémorisée pour les démarrages suivants. En cas de problème : [B5] et [RESEAU.md](RESEAU.md).
4. Ajouter Windows au menu GRUB s'il n'y était pas :
   ```
   $ sudo grub-mkconfig -o /boot/grub/grub.cfg
   ```
   Une ligne `Found Windows Boot Manager on /dev/nvme0n1pX@/EFI/Microsoft/Boot/bootmgfw.efi` doit apparaître. Sinon : [B6].
5. Redémarrer → GRUB → **Windows** : Windows démarre. Vérifier l'heure : [B7] si elle est fausse.
6. Redémarrer → **F11** → *Windows Boot Manager* : Windows démarre **sans GRUB**. C'est ta porte de sortie permanente.
7. Redémarrer sur Arch → GRUB → *Advanced options* → noyau **linux-lts** : il démarre aussi.
8. Le dépôt est dans ton dossier :
   ```
   $ cd ~/dualboot-arch
   $ ./guide.sh
   ```
   S'il manque : [B8].

**Point de contrôle** : Arch démarre (avec `linux` et `linux-lts`), Windows démarre via GRUB **et** via F11, le réseau fonctionne. `./guide.sh valider 6`.

---

## Étape 7 — Snapshots : snapper, tests, JALON 00

**Pourquoi** : c'est le cœur du projet. Après cette étape, chaque `pacman` crée automatiquement un snapshot « avant » et « après », visible dans le menu GRUB. Le jalon 00 est le point de retour vers une Arch de base propre. À lire avant : [COMPRENDRE-SNAPSHOTS.md](COMPRENDRE-SNAPSHOTS.md).

**7.1 Installer la configuration**
```
$ cd ~/dualboot-arch
$ sudo ./post/40-snapper.sh                 # simulation : lire
$ sudo DRY_RUN=0 ./post/40-snapper.sh
```
Taper `OUI` pour supprimer le sous-volume `/.snapshots` imbriqué, que snapper crée de lui-même et qu'on remplace par `@snapshots`.

Contrôles :
```
$ findmnt /.snapshots              # SOURCE …[/@snapshots]
$ sudo snapper -c root list        # au moins la ligne 0 « current »
$ systemctl status grub-btrfsd     # active (running)
$ systemctl list-timers | grep snapper
```
Problèmes : [S1] à [S3].

**7.2 Test : snapshot automatique par pacman**
```
$ sudo pacman -S tree
$ sudo snapper -c root list
```
Deux nouvelles lignes doivent apparaître, de type `pre` et `post`, avec la description `pacman -S tree`. Sinon : [S4].

**7.3 Test : démarrer un snapshot**
1. Redémarrer. Dans GRUB, une entrée **Arch Linux snapshots** apparaît. Sinon : [S5].
2. Y choisir le snapshot `pre` de l'étape 7.2, puis le noyau `linux`.
3. Se connecter, puis taper `tree` : *command not found* (normal, le snapshot date d'avant son installation).
4. `findmnt /` montre un montage `overlay` : c'est le mode lecture seule + RAM. Les changements disparaîtront au redémarrage. Si le démarrage échoue en « read-only file system » : [S6].
5. Redémarrer normalement : `tree` est toujours là.

**7.4 Test : restauration permanente (le vrai filet)**

À faire **au moins une fois** pour savoir que ça marche. Sur la vraie machine, c'est sans risque pour tes données : l'ancien système est conservé (`@broken-…`), et il est remis en place automatiquement si la restauration échoue.
1. Créer un snapshot de test, puis « casser » quelque chose sans danger :
   ```
   $ sudo snapper -c root create -d "test restauration"
   $ sudo snapper -c root list          # noter son numéro, ex. 5
   $ sudo pacman -R tree
   ```
2. Redémarrer sur la **clé live**, puis :
   ```
   # loadkeys fr-latin9
   # (réseau, voir étape 1) ; git clone … ; cd dualboot-arch
   # ./rescue/restore-snapshot.sh            # liste : retrouver « test restauration »
   # DRY_RUN=0 ./rescue/restore-snapshot.sh 5
   # reboot
   ```
   Sans réseau, la procédure manuelle de [RECOVERY.md](RECOVERY.md) fonctionne sans le dépôt.
3. Une fois redémarré sur Arch :
   ```
   $ tree --version                       # revenu
   $ findmnt /home /.snapshots /var/log   # tous montés
   $ sudo grub-mkconfig -o /boot/grub/grub.cfg
   ```
4. Plus tard, après quelques jours sans problème : supprimer `@broken-…` (commande affichée par le script).

**7.5 Créer le jalon 00**
```
$ sudo DRY_RUN=0 ./post/jalon.sh 00 "arch-base valide (Arch + Windows demarrent)"
```
Le numéro du jalon s'affiche. Le reporter dans le tableau « Jalons » de [JOURNAL.md](JOURNAL.md).

**Point de contrôle** : 7.2, 7.3 et 7.4 sont réussis et le jalon 00 existe. `./guide.sh` coche l'étape tout seul.

---

## Étape 8 — Portable : pilotes, audio, énergie (JALON 01)

**Pourquoi** : l'iGPU Intel affiche l'écran ; la RTX 4060 ne travaille qu'à la demande (`prime-run`) et s'éteint au repos pour préserver la batterie.

```
$ sudo DRY_RUN=0 ./post/50-hardware-laptop.sh install
$ sudo DRY_RUN=0 ./post/50-hardware-laptop.sh udev
$ reboot
$ ./post/50-hardware-laptop.sh check
```

**Ce que tu dois voir** après le redémarrage :
- `nvidia-smi` : la carte *GeForce RTX 4060 Laptop GPU*.
- `prime-run glxinfo | grep "OpenGL renderer"` : NVIDIA.
- `glxinfo | grep "OpenGL renderer"` : Intel. C'est normal : par défaut, tout tourne sur l'Intel.
- Dans `check` :
  - `modeset : Y` ;
  - `/dev/dri/intel-igpu` et `/dev/dri/nvidia-dgpu` présents ;
  - quelques secondes après la fermeture de tout programme graphique, `runtime_status : suspended`.
- Le son fonctionne (`wpctl status` liste les sorties). Le Bluetooth aussi (`bluetoothctl` → `power on` → `scan on`).
- La veille fonctionne : fermer l'écran puis le rouvrir.
- Refaire `nvidia-smi` après avoir démarré sur **linux-lts**.

Problèmes : [N1] à [N6].

```
$ sudo DRY_RUN=0 ./post/jalon.sh 01 "arch-config (reseau, audio, pilotes OK)"
```

---

## Étape 9 — Surcouche CachyOS (JALON 02 → 03)

**Pourquoi** : ajouter les paquets recompilés pour ton CPU (x86-64-v3) et le noyau CachyOS, avec ses modules NVIDIA précompilés. On garde `linux` et `linux-lts` comme secours. Ce que ça apporte ou non : brief §6. Les écarts sont dans DECISIONS.md, n° 8.

**Ce qu'il faut savoir avant** : le script officiel ajoute le dépôt `[cachyos]`, qui **remplace pacman** par la version CachyOS. Au `-Syu` suivant, des paquets de base (glibc, etc.) sont remplacés par leur version recompilée. C'est voulu, mais c'est la raison d'être du jalon 02.

```
$ sudo DRY_RUN=0 ./post/jalon.sh 02 "pre-cachy"
$ sudo ./post/60-cachyos-repo.sh check
```
→ `x86-64-v3 (supported, searched)` et **pas** de v4 en `supported`. `JALON 02 présent`.

```
$ sudo DRY_RUN=0 ./post/60-cachyos-repo.sh prepare
```
Le script s'ouvre dans `less` : **le lire en entier** (flèches, `q` pour quitter). Repérer ce qu'il fait à `pacman.conf`, les clés qu'il importe, les paquets qu'il installe. S'il fait autre chose que ce qui est décrit à l'écran après `less`, ne pas continuer : comparer avec la page officielle (wiki.cachyos.org → Optimized repositories).

```
$ sudo DRY_RUN=0 ./post/60-cachyos-repo.sh run
$ grep -n '^\[' /etc/pacman.conf        # [cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] AVANT [core]
$ sudo pacman -Syu                      # lire chaque « remplacer X par Y ? » ; répondre O
$ reboot
```
Puis vérifier que tout démarre encore, et installer le noyau :
```
$ sudo DRY_RUN=0 ./post/60-cachyos-repo.sh kernel
$ reboot
```

**Tester les trois noyaux**, un démarrage chacun (GRUB → *Advanced options*) :
```
$ uname -r        # contient « cachyos », puis « lts », puis la version Arch
$ nvidia-smi
$ prime-run glxinfo | grep "OpenGL renderer"
```
Problèmes : [C1] à [C5].

Options, **une seule à la fois**, avec un snapshot manuel avant chacune (`sudo snapper -c root create -d "avant X"`) :
- `cachyos-settings` : lire d'abord `pacman -Si cachyos-settings`, puis après installation `pacman -Ql cachyos-settings`. Il modifie sysctl, udev et zram, et peut entrer en conflit avec `/etc/systemd/zram-generator.conf`.
- `ananicy-cpp` + règles ;
- ordonnanceurs `scx`.

**Version minimale possible** : s'arrêter après le noyau, sans aucune option.

```
$ sudo DRY_RUN=0 ./post/jalon.sh 03 "post-cachy (3 noyaux OK)"
```

---

## Étape 10 — Hyprland (JALON 04 → 05)

**Pourquoi** : un bureau animé et léger, lancé sur tty1, avec une session de secours toujours disponible sur tty2.

**À savoir** : Hyprland 0.57 se configure en **Lua** (`~/.config/hypr/hyprland.lua`). Les tutoriels et dotfiles d'avant 2026 utilisent souvent l'ancien format `hyprland.conf`, qui ne s'applique pas tel quel. La documentation qui fait foi est celle de ta version : `hyprctl version`, puis le sélecteur de version sur wiki.hypr.land.

```
$ sudo DRY_RUN=0 ./post/jalon.sh 04 "pre-hyprland"
$ sudo DRY_RUN=0 ./post/70-hyprland.sh packages
$ DRY_RUN=0 ./post/70-hyprland.sh user-setup        # SANS sudo
```
Puis se déconnecter (`exit`) et se reconnecter sur **tty1** : Hyprland démarre et crée une config d'exemple.

**Premiers pas** : le bandeau en haut de l'écran signale la config d'exemple. Lire le fichier `~/.config/hypr/hyprland.lua` pour y trouver les raccourcis. Si la config contient une erreur avant la déclaration des raccourcis, Hyprland active des raccourcis de secours : **SUPER+Q** (terminal), **SUPER+M** (quitter). Pour quitter proprement : `uwsm stop` dans un terminal.

**Tester la session de secours** : Ctrl+Alt+F2 → connexion texte → `sway` (configuration par défaut). Si sway refuse de démarrer à cause de NVIDIA : [H4].

**Clavier français dans Hyprland** : option `kb_layout` de la section *input*. La syntaxe Lua exacte se trouve sur la page *Configuring → Core → Devices / Config options* du wiki de ta version.

**Mettre la config sous Git dès maintenant** :
```
$ cd ~/.config/hypr && git init && git add -A && git commit -m "Hyprland : config de départ"
```

Problèmes : [H1] à [H7].

```
$ sudo DRY_RUN=0 ./post/jalon.sh 05 "hyprland-ok (secours inclus)"
```

---

## Étape 11 — Personnalisation (JALON 06)

**Pourquoi** : le rendu « smooth, animé, customisé », sans perdre ce qui marche.

Méthode pour **n'importe quel** rice (end-4, Caelestia, HyDE, ML4W, Noctalia, ou config maison) :
1. Vérifier qu'il supporte **ta** version de Hyprland (Lua, 0.57+). Sinon, attendre ou choisir un autre rice.
2. `sudo snapper -c root create -d "avant rice X"` et sauvegarder `~/.config` : `cp -a ~/.config ~/.config.avant-rice`. `@home` n'est pas dans les snapshots système.
3. **Lire** son script d'installation : liste des paquets, fichiers écrasés, présence de `sudo` ou de `curl | sh` (refuser ces derniers).
4. L'installer, puis tester : animations, température (`sensors`), batterie, FPS.
5. En cas de problème : restaurer `~/.config.avant-rice` et le snapshot.

Animations : courbes de Bézier et durées, flou et ombres modérés. Sur portable, surveiller la température et la batterie.

```
$ sudo DRY_RUN=0 ./post/jalon.sh 06 "perso-ok"
```

---

## Étape 12 — Maintenance automatique

```
$ sudo DRY_RUN=0 ./post/80-maintenance.sh
```
Active : informant (bloque pacman tant qu'une actualité Arch n'est pas lue), purge du cache pacman, vérification Btrfs mensuelle et surveillance SMART du NVMe.

**Pour chaque mise à jour, à partir de maintenant** :
```
$ sudo DRY_RUN=0 maj-systeme
```
Le script lit les actualités, crée un snapshot, lance `pacman -Syu`, liste les `.pacnew` et les orphelins, puis vérifie les noyaux et GRUB.

Bonnes habitudes :
- Jamais `pacman -Sy paquet` seul : toujours `-Syu`.
- Mettre à jour au moins tous les 15 jours. Une Arch très en retard se met à jour plus difficilement.
- Après une grosse mise à jour (noyau, NVIDIA, Hyprland), redémarrer et vérifier avant d'en faire une autre.
- AUR (`paru` ou `yay`) : lire chaque PKGBUILD avant de l'installer.
- Sauvegarde externe de `/home` : voir brief §8 (`btrbk`, `restic` ou `borg`). Un snapshot n'est **pas** une sauvegarde : il est sur le même disque.

---

## Mémo express

| Je veux… | Commande |
|---|---|
| Savoir où j'en suis | `./guide.sh` |
| Voir les snapshots | `sudo snapper -c root list` |
| Créer un snapshot avant un essai | `sudo snapper -c root create -d "avant essai X"` |
| Comparer avec un snapshot | `sudo snapper -c root status N..0` |
| Annuler les changements de fichiers d'un snapshot (sans redémarrer) | `sudo snapper -c root undochange N..0` (lire [S8] avant) |
| Revenir en arrière proprement | GRUB → snapshots pour tester, puis la clé live → `rescue/restore-snapshot.sh` |
| GRUB ne s'affiche plus | F11 → Windows ; clé live → `rescue/chroot-repair.sh grub` |
| Mettre à jour | `sudo DRY_RUN=0 maj-systeme` |
| Récupérer la dernière version du guide | `cd ~/dualboot-arch && git pull` |
