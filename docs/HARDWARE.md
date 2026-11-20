# Faits matériels

À remplir avec la sortie de `install/00-preflight-live.sh` (phase 1). Une valeur n'est « vérifiée » qu'avec la commande qui la prouve.

| Élément | Attendu (brief) | Constaté | Commande | Vérifié le |
|---|---|---|---|---|
| Modèle | MSI Cyborg 15 A12VF | [À COMPLÉTER] | `dmidecode -s system-product-name` | |
| Version BIOS | | [À COMPLÉTER] | `dmidecode -s bios-version` | |
| CPU | i7 12e gen (i7-12650H probable) | [À COMPLÉTER] | `lscpu` | |
| Niveau x86-64 | v3, pas v4 | [À COMPLÉTER] | `/lib/ld-linux-x86-64.so.2 --help \| grep supported` | |
| RAM | 16 Go | [À COMPLÉTER] | `free -h` | |
| Disque | 1 To NVMe unique | [À COMPLÉTER] | `lsblk` | |
| Taille de secteur | | [À COMPLÉTER] | `blockdev --getss /dev/nvme0n1` | |
| iGPU (adresse PCI) | Intel Iris Xe | [À COMPLÉTER] | `lspci -D -d ::03xx` | |
| dGPU (adresse PCI) | RTX 4060 Laptop | [À COMPLÉTER] | `lspci -D -d ::03xx` | |
| MUX GPU | à vérifier | [À COMPLÉTER] | BIOS | |
| Sortie HDMI/USB-C sur | iGPU ou dGPU ? | [À COMPLÉTER] | test avec écran externe | |
| Mode de démarrage | UEFI / GPT | [À COMPLÉTER] | `ls /sys/firmware/efi` | |
| Secure Boot | désactivé pendant l'installation | [À COMPLÉTER] | BIOS / preflight | |
| BitLocker | absent | [À COMPLÉTER] | `blkid \| grep -i bitlocker` | |

## Partitions Windows (NE PAS TOUCHER)

| Partition | Rôle | Taille | PARTUUID |
|---|---|---|---|
| [À COMPLÉTER] | ESP Windows | | |
| [À COMPLÉTER] | MSR | | |
| [À COMPLÉTER] | C: (NTFS) | | |
| [À COMPLÉTER] | Récupération | | |

## Côté Windows (relevé par l'utilisateur)

| Contrôle | Commande (terminal admin) | Résultat |
|---|---|---|
| Hibernation / démarrage rapide désactivés | `powercfg /a` (sinon `powercfg /h off`) | [À COMPLÉTER] |
| BitLocker | `manage-bde -status` | [À COMPLÉTER] |
| Environnement de récupération | `reagentc /info` | [À COMPLÉTER] |
| Horloge en UTC | `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f` | [À COMPLÉTER] |
| Espace non alloué après réduction de C: | Gestion des disques | [À COMPLÉTER] |
| Image Clonezilla faite **et restauration testée** | | [À COMPLÉTER] |
