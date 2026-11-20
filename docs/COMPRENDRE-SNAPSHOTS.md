# Comprendre les snapshots (en 5 minutes)

## L'idée

Un **snapshot** est une photo instantanée du système à un moment donné. Btrfs ne copie rien au moment de la photo : il garde simplement les anciennes versions des fichiers au lieu de les écraser. Un snapshot ne coûte donc presque rien au départ. Il grossit ensuite au fur et à mesure que le système change.

> Un snapshot **n'est pas une sauvegarde** : il est sur le même disque. Si le NVMe meurt, les snapshots meurent avec lui. Pour ça, il y a la sauvegarde externe (brief §8).

## Comment le disque est découpé

La partition Linux (Btrfs) contient des **sous-volumes**. Ce sont des dossiers qu'on peut photographier séparément :

```
partition archroot (Btrfs)
├── @           → monté sur /           le système : programmes, /etc, /boot (noyaux), base pacman
├── @home       → monté sur /home       tes fichiers personnels
├── @snapshots  → monté sur /.snapshots les photos de @
├── @var_log    → monté sur /var/log    les journaux
└── @pkg        → monté sur /var/cache/pacman/pkg   les paquets téléchargés
```

**Seul `@` est photographié.** Conséquences :

- Revenir en arrière **ne touche pas à tes fichiers** dans `/home` : tes documents ne remontent pas dans le temps.
- Les **journaux** sont conservés : on peut lire ce qui a cassé, même après un retour arrière.
- Les **photos** elles-mêmes sont à part : remplacer `@` ne les efface pas.
- `/boot` est **dans** `@` : un retour arrière ramène un noyau et ses modules NVIDIA qui vont ensemble. C'est la raison pour laquelle on n'a pas utilisé archinstall.

## Qui fait quoi

| Outil | Rôle |
|---|---|
| **snapper** | crée, liste, compare et supprime les snapshots de `@` (configuration « root ») |
| **snap-pac** | à chaque `pacman` qui installe, met à jour ou supprime : un snapshot *pre* avant, un *post* après |
| **timeline** (timer snapper) | un snapshot par heure, puis un tri : en garde 5 horaires, 7 journaliers, 2 hebdomadaires et 1 mensuel |
| **cleanup** (timer snapper) | supprime les vieux snapshots automatiques au-delà des limites |
| **grub-btrfs** (`grub-btrfsd`) | ajoute chaque nouveau snapshot au menu GRUB, dans « Arch Linux snapshots » |
| **jalons** (`post/jalon.sh`) | snapshots manuels **sans nettoyage** : jamais supprimés automatiquement |

## Les trois façons de revenir en arrière

| Situation | Que faire | Effet |
|---|---|---|
| Je veux **juste voir** si un état d'avant fonctionne | GRUB → *Arch Linux snapshots* → choisir | Démarre l'ancien état en lecture seule, les changements restent en RAM. Rien n'est modifié. |
| Je veux **revenir pour de bon** | Clé live → `rescue/restore-snapshot.sh N` | L'ancien `@` est mis de côté (`@broken-DATE`), une copie du snapshot devient le nouveau `@`. |
| Je veux **annuler un fichier** (config ratée) | `sudo snapper -c root undochange N..0 /chemin/fichier` | Remet ce fichier dans son état du snapshot N, sans redémarrer. |

> Ne pas utiliser `snapper rollback` : avec ce découpage, c'est `restore-snapshot.sh` qui fait le travail. Explication : [DEPANNAGE.md](DEPANNAGE.md) [S8].

## Lire `snapper list`

```
$ sudo snapper -c root list
 #  | Type   | Pre # | Date                | Cleanup  | Description
----+--------+-------+---------------------+----------+------------------------------
 0  | single |       |                     |          | current
 1  | single |       | 2026-12-01 10:02:11 |          | JALON 00 - arch-base valide
 2  | pre    |       | 2026-12-01 10:15:40 | number   | pacman -S tree
 3  | post   |     2 | 2026-12-01 10:15:44 | number   | tree
 4  | single |       | 2026-12-01 11:00:01 | timeline | timeline
```

- `0 current` : le système en cours. Ce n'est pas un snapshot.
- `Cleanup` vide : le snapshot ne sera **jamais** supprimé automatiquement (c'est le cas des jalons).
- `pre` / `post` : la paire créée autour d'une commande pacman. Le `post` indique son `pre`.

Voir ce qui a changé entre deux snapshots :

```
$ sudo snapper -c root status 2..3          # liste des fichiers modifiés
$ sudo snapper -c root diff 2..3 /etc/fstab # différences dans un fichier précis
```

## Les jalons de ce projet

| Jalon | Moment | Sert à revenir… |
|---|---|---|
| 00 | Arch minimal + snapshots testés | à une Arch « neuve » |
| 01 | pilotes, audio, réseau OK | avant toute surcouche |
| 02 | juste avant CachyOS | si CachyOS pose problème |
| 03 | CachyOS OK, 3 noyaux testés | |
| 04 | juste avant Hyprland | si Hyprland casse tout |
| 05 | Hyprland + secours OK | |
| 06 | personnalisation finie | état final de référence |

Créer un jalon : `sudo DRY_RUN=0 ./post/jalon.sh NN "description"`, puis noter son numéro dans JOURNAL.md.

## Bonnes habitudes

- Avant un essai risqué (nouveau logiciel, modification de config système) : `sudo snapper -c root create -d "avant essai X"`.
- Après un retour arrière qui fonctionne : attendre quelques jours, puis supprimer `@broken-…`.
- Surveiller l'espace : `sudo btrfs filesystem usage /`. S'il se remplit : [DEPANNAGE.md](DEPANNAGE.md) [S7].
