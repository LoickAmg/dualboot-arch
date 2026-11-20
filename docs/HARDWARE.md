# Faits matériels

Une valeur n'est « vérifiée » qu'avec la commande qui la prouve. Les relevés « Windows » ont été faits le 2026-11-21 depuis Windows, en lecture seule. Ceux sous Linux se complètent avec `install/00-preflight-live.sh` (étape 1).

| Élément | Attendu (brief) | Constaté | Commande | Vérifié le |
|---|---|---|---|---|
| Modèle | MSI Cyborg 15 A12VF | **Cyborg 15 A12VF** | Windows : `Win32_ComputerSystem.Model` · Linux : `dmidecode -s system-product-name` | 2026-11-21 (Windows) |
| Version BIOS | | [À COMPLÉTER] | `dmidecode -s bios-version` | |
| CPU | i7 12e gen (i7-12650H probable) | [À COMPLÉTER] | `lscpu` | |
| Niveau x86-64 | v3, pas v4 | [À COMPLÉTER] | `/lib/ld-linux-x86-64.so.2 --help \| grep supported` | |
| RAM | 16 Go | [À COMPLÉTER] | `free -h` | |
| Disque | 1 To NVMe unique | **WD Green SN350 1 To** (931,5 Go), NVMe, GPT, disque 0 unique | Windows : `Get-Disk` · Linux : `lsblk` | 2026-11-21 (Windows) |
| Taille de secteur | | [À COMPLÉTER] | `blockdev --getss /dev/nvme0n1` | |
| Wi-Fi | | **Intel Wi-Fi 6 AX201 160 MHz**, PCI `8086:51f0` → pilote `iwlwifi`, fonctionne dans la live | Windows : `Get-NetAdapter` · Linux : `lspci -nnk \| grep -A3 Network` | 2026-11-21 (Windows) |
| Ethernet | | **Realtek PCIe GbE (RTL8168)**, PCI `10ec:8168` → pilote `r8169` | idem | 2026-11-21 (Windows) |
| iGPU (adresse PCI) | Intel Iris Xe | [À COMPLÉTER] | `lspci -D -d ::03xx` | |
| dGPU (adresse PCI) | RTX 4060 Laptop | [À COMPLÉTER] | `lspci -D -d ::03xx` | |
| MUX GPU | à vérifier | [À COMPLÉTER] | BIOS | |
| Sortie HDMI/USB-C sur | iGPU ou dGPU ? | [À COMPLÉTER] | test avec écran externe | |
| Mode de démarrage | UEFI / GPT | **UEFI**, disque **GPT** | Windows : `$env:firmware_type`, `Get-Disk` · Linux : `ls /sys/firmware/efi` | 2026-11-21 (Windows) |
| Secure Boot | désactivé pendant l'installation | [À COMPLÉTER] | BIOS / preflight | |
| BitLocker | absent | probablement absent : Gestion des disques n'affiche pas « BitLocker Encrypted » sur C:. **À confirmer** avec `manage-bde -status` (admin) | `manage-bde -status` · Linux : `blkid \| grep -i bitlocker` | indice 2026-11-21 |

## Partitions Windows (NE PAS TOUCHER)

Relevé `Get-Partition -DiskNumber 0` du 2026-11-21. Les PARTUUID se relèvent sous Linux (étape 1).

| Partition | Rôle | Taille | Position | PARTUUID |
|---|---|---|---|---|
| 1 | ESP Windows (FAT32) | 100 Mo | début du disque | [À COMPLÉTER] |
| 2 | MSR | 16 Mo | après l'ESP | [À COMPLÉTER] |
| 3 | C: (NTFS) | 930,68 Go (586 Go utilisés, environ 345 Go libres) | à partir de 0,11 Go | [À COMPLÉTER] |
| 4 | Récupération | 730 Mo | **après C:**, en fin de disque | [À COMPLÉTER] |

La partition de récupération est **après** C: : l'espace libéré en réduisant C: se retrouve entre C: et la récupération. C'est normal, et `10-partition.sh plan` le gère (il prend le plus grand bloc libre).

## Côté Windows

| Contrôle | Commande | Résultat |
|---|---|---|
| Hibernation / démarrage rapide désactivés | `powercfg /a`, présence de `C:\hiberfil.sys`, `HiberbootEnabled` | **OK** : pas de `hiberfil.sys`, `HiberbootEnabled = 0` (2026-11-21) |
| BitLocker | `manage-bde -status` (admin) | [À COMPLÉTER] (voir l'indice plus haut) |
| Environnement de récupération | `reagentc /info` (admin) | [À COMPLÉTER] |
| Horloge en UTC | `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f` | **absente** au 2026-11-21 (clé non trouvée) : [À COMPLÉTER] après application |
| Espace non alloué après réduction de C: | Gestion des disques | **pas encore** : réduction bloquée par `$MFT` (voir DEPANNAGE [P2]) |
| Image Clonezilla | | **non faite**, par choix. Seules les sauvegardes des 3 jeux sont faites (`sauvegardes-jeux-2026-11-21.zip`, hors dépôt) |
