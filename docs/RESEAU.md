# Réseau — se connecter sans câble ni VM

L'installation d'Arch télécharge ses paquets pendant l'installation : il faut Internet **dans la clé live** (étapes 1 à 5), puis **sur le système installé** (étapes 6 et suivantes).

## Le matériel de ce PC (relevé sous Windows le 2026-11-21)

| Interface | Modèle | Identifiant PCI | Sous Arch |
|---|---|---|---|
| Wi-Fi | Intel Wi-Fi 6 AX201 160 MHz | `8086:51f0` | pilote `iwlwifi` + firmware Intel, fournis par la clé et par `linux-firmware` : **fonctionne sans rien installer** |
| Ethernet | Realtek PCIe GbE (RTL8168) | `10ec:8168` | pilote `r8169`, intégré au noyau : **fonctionne sans rien installer** |

Conclusion : **le Wi-Fi suffit**. Ni câble USB ni VM ne sont nécessaires.

---

## 1. Dans la clé live (étapes 1 à 5)

Trois possibilités, de la plus pratique à la plus sûre.

### A. Wi-Fi avec `iwctl`

```
# iwctl
[iwd]# device list                          # nom de l'interface, en général wlan0
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks           # réseaux visibles
[iwd]# station wlan0 connect "NomDeTaBox"   # demande le mot de passe
[iwd]# exit
# ping -c3 archlinux.org
```
Trois lignes `64 bytes from …` = connecté.

- Un nom de réseau avec des espaces se met **entre guillemets**.
- Mot de passe : la clé live utilise le clavier choisi par `loadkeys` (étape 1). Vérifier la disposition (`loadkeys fr-latin9`) **avant** de taper le mot de passe : sinon, en QWERTY, `a` et `q` sont inversés, de même que `z` et `w`.
- Réseau caché : `station wlan0 connect-hidden "Nom"`.
- Mauvais mot de passe : `station wlan0 disconnect`, puis recommencer.
- La commande en une seule ligne, sans entrer dans l'invite `[iwd]#` :
  ```
  # iwctl --passphrase "MotDePasse" station wlan0 connect "NomDeTaBox"
  ```

### B. Câble Ethernet (RJ45) vers la box

Rien à faire : la connexion est automatique au démarrage de la live. Vérifier avec `ping -c3 archlinux.org`.

### C. Partage de connexion USB d'un téléphone

- **Android** : brancher le téléphone, puis *Paramètres → Point d'accès et partage → Partage de connexion USB*. La live prend une adresse toute seule (interface `usb0` ou `enp…u…`). C'est le plan B le plus fiable.
- **iPhone** : [À VÉRIFIER] le partage USB demande des composants que la live ne charge peut-être pas. Préférer le **point d'accès Wi-Fi** de l'iPhone, puis la méthode A.
- Le partage Wi-Fi d'un téléphone (point d'accès) marche aussi avec la méthode A.

### Vérifications utiles

```
# ip -br link                 # interfaces : wlan0, enp…, usb0
# ip -br addr                 # une adresse IP sur l'interface utilisée ?
# rfkill list                 # « Soft blocked: yes » → rfkill unblock all
# ping -c3 1.1.1.1            # Internet sans DNS
# ping -c3 archlinux.org      # Internet avec DNS
# timedatectl                 # « System clock synchronized: yes » (sinon erreurs de signatures)
```

---

## 2. Sur l'Arch installée (étape 6 et suivantes)

La clé n'est plus là : le système doit savoir se connecter tout seul. C'est prévu : `networkmanager` est installé à l'étape 4 et activé à l'étape 5 (`systemctl enable NetworkManager`). `iwctl` **n'est plus** l'outil à utiliser.

```
$ nmtui                                               # menus : « Activer une connexion »
$ nmcli device wifi list                              # réseaux visibles
$ nmcli device wifi connect "NomDeTaBox" --ask        # demande le mot de passe
$ nmcli connection show                               # connexions enregistrées
```
La connexion est mémorisée et revient automatiquement à chaque démarrage. Plus tard, Hyprland pourra afficher une icône réseau (applet), mais `nmtui` reste toujours disponible dans un terminal.

---

## 3. Cas qui ne marchent pas, et que faire

| Situation | Pourquoi | Solution |
|---|---|---|
| Wi-Fi avec **page de connexion** (hôtel, école, Wi-Fi public avec « J'accepte ») | la live n'a pas de navigateur pour valider la page | partage de connexion du téléphone (C) ou point d'accès du téléphone |
| Wi-Fi **entreprise / eduroam** (identifiant + mot de passe, WPA-Enterprise) | `iwctl` demande un fichier de configuration dédié | utiliser un autre réseau pour l'installation ; configurer eduroam plus tard avec NetworkManager |
| `device list` vide | carte désactivée ou mode avion | `rfkill unblock all` ; touche mode avion du portable ; vérifier que le Wi-Fi n'est pas désactivé dans le BIOS |
| Connecté mais `ping archlinux.org` échoue | DNS | `echo "nameserver 1.1.1.1" > /etc/resolv.conf` (live) |
| Erreurs de signatures pendant pacstrap | heure fausse | `timedatectl set-ntp true`, attendre une minute (DEPANNAGE [I1]) |
| Après redémarrage, plus de réseau | NetworkManager non activé | `sudo systemctl enable --now NetworkManager` (DEPANNAGE [B5]) |

## 4. Volume de données à prévoir

À titre indicatif, pour qui passe par le forfait du téléphone :

| Étape | Ordre de grandeur |
|---|---|
| Étape 4 (pacstrap : base, deux noyaux, firmware, outils) | quelques centaines de Mo à environ 1 Go |
| Étape 8 (pilotes NVIDIA, Intel, audio) | quelques centaines de Mo |
| Étape 9 (CachyOS : remplacement de nombreux paquets + noyau) | plusieurs centaines de Mo à quelques Go |
| Étape 10 (Hyprland et ses outils) | quelques centaines de Mo |

Ces chiffres sont des ordres de grandeur, pas des mesures. `pacman` affiche la taille exacte (« Total Download Size ») et attend un « O » avant de télécharger ; `pacstrap` (étape 4) affiche la taille mais enchaîne sans demander.
