# Réduire C: avec GParted Live

À utiliser quand Windows refuse de réduire C: parce que la `$Mft` est en fin de volume (DEPANNAGE [P2]). Sur ce PC, c'est le cas depuis le 2026-11-21.

---

## Comprendre avant de commencer

### Pourquoi Windows bloque

Un volume NTFS (C:) contient des fichiers ordinaires, que Windows sait déplacer, et quelques fichiers système qu'il refuse de bouger pendant qu'il tourne. Le plus important est la **`$Mft`** (Master File Table) : c'est **le sommaire du disque**, avec une fiche par fichier. Sur ce PC, une partie de la `$Mft` est à environ 920 Go, presque au bout de C:. L'outil *Réduire le volume* ne peut pas couper au-delà de ce point, d'où les 10 898 Mo proposés au lieu de 257 024.

### Ce que fait GParted

**GParted Live** est un petit Linux qui démarre depuis une clé USB et ne sert qu'à gérer les partitions. Comme il tourne **hors de Windows**, aucun fichier n'est verrouillé : il peut tout déplacer, la `$Mft` comprise.

Pour une partition NTFS, GParted fait travailler l'outil **`ntfsresize`** (projet ntfs-3g). Quand tu cliques sur *Appliquer*, il enchaîne trois phases :

| Phase | Ce qui se passe | Écrit sur le disque ? |
|---|---|---|
| 1. Contrôle | vérifie que NTFS est cohérent et que Windows a été arrêté proprement ; puis **simule** la réduction | **non** : s'il trouve un problème, il s'arrête ici et rien n'est modifié |
| 2. Réduction du système de fichiers | déplace les données qui se trouvent après la nouvelle fin vers l'espace libre du début, puis raccourcit NTFS | **oui** : c'est la phase longue et sensible |
| 3. Réduction de la partition | modifie la table de partitions : la fin de C: recule | oui, très rapide |

Au premier démarrage suivant, Windows peut lancer une **vérification du disque** : c'est prévu. `ntfsresize` le lui demande pour qu'il remette à jour ses propres informations.

### Les risques, honnêtement

- **Le vrai risque est une coupure pendant la phase 2.** Si le PC s'éteint pendant que les données se déplacent, NTFS peut être abîmé. D'où : chargeur branché, rien d'autre en cours, ne jamais forcer l'arrêt.
- Un NTFS déjà abîmé, ou un Windows qui n'a pas été arrêté proprement (démarrage rapide, hibernation) : GParted **refuse** en phase 1, sans rien écrire. Sur ce PC, l'hibernation et le démarrage rapide sont déjà désactivés.
- Sans image Clonezilla, il n'y a pas de retour arrière : les fichiers importants doivent être **copiés hors du PC** avant.

---

## Ce qu'il faut

- **Une clé USB** : la clé Ventoy du projet, ou n'importe quelle clé d'au moins 1 Go.
- L'ISO **GParted Live** pour **amd64**, téléchargée **uniquement** depuis le site officiel, gparted.org.
- Le chargeur du portable.

---

## Pas à pas

### A. Dans Windows, avant

1. **Copier hors du PC** ce qui compte : l'archive des sauvegardes de jeux et les fichiers personnels.
2. **Vérifier l'ISO**. Sa somme SHA256 est publiée sur la page de téléchargement. Dans PowerShell :
   ```powershell
   Get-FileHash .\gparted-live-*-amd64.iso -Algorithm SHA256
   ```
   Les deux valeurs doivent être **identiques**. Sinon, retélécharger.
3. **Mettre l'ISO sur la clé** :
   - clé Ventoy : copier simplement le fichier `.iso` dessus ;
   - clé ordinaire : l'écrire avec Rufus (mode image ISO / DD). Cela **efface** la clé.
4. **Vérifier NTFS** (terminal administrateur, lecture seule, ne répare rien) :
   ```powershell
   chkdsk C:
   ```
   Il doit indiquer qu'il n'a trouvé aucun problème. Sinon, s'arrêter et demander de l'aide.
5. **Désactiver le fichier d'échange** : *SystemPropertiesPerformance → Advanced → Virtual memory → Change* → décocher « Automatically manage… » → C: → « No paging file » → Set → OK.
6. **Arrêter complètement le PC.** Un « Arrêter » normal suffit, puisque le démarrage rapide est désactivé.

### B. Démarrer GParted

1. Clé branchée, chargeur branché. Allumer, puis appuyer sur **F11** au logo MSI et choisir la clé (entrée UEFI). Avec Ventoy, choisir ensuite l'ISO GParted.
2. Menu GParted Live : **GParted Live (Default settings)**.
3. *Configuring console-data* (clavier) : **Don't touch keymap**. Le clavier ne sert presque pas, tout se fait à la souris.
4. Langue : taper le numéro affiché en face de **French** dans la liste, ou Entrée pour garder l'anglais.
5. Mode : **0** (interface graphique). GParted s'ouvre tout seul.

### C. Repérer les partitions

En haut à droite, le disque `/dev/nvme0n1` (931,51 Gio) doit être sélectionné. Tu dois voir :

| Partition | Système de fichiers | Taille | Rôle |
|---|---|---|---|
| `/dev/nvme0n1p1` | fat32 | 100 Mio | ESP Windows : **ne pas toucher** |
| `/dev/nvme0n1p2` | (inconnu) | 16 Mio | MSR : **ne pas toucher** |
| `/dev/nvme0n1p3` | **ntfs** | environ 930 Gio | **C: : celle-ci** |
| `/dev/nvme0n1p4` | ntfs | 730 Mio | récupération : **ne pas toucher** |

Si une partition affiche un **point d'exclamation** ou un **cadenas**, s'arrêter. Voir « Messages possibles » ci-dessous.

### D. Programmer la réduction

1. Clic droit sur **`/dev/nvme0n1p3`** → **Redimensionner/Déplacer**.
2. Dans la fenêtre :
   - **Espace libre précédent (Mio)** : laisser **0** ;
   - **Nouvelle taille (Mio)** : ne pas la taper, elle se calcule seule ;
   - **Espace libre suivant (Mio)** : taper **`257024`**, puis appuyer sur Tab ;
   - la nouvelle taille doit alors être d'environ **695 996 Mio**.
3. Cliquer sur **Redimensionner/Déplacer**.
4. Sur la carte du disque, un bloc gris **« non alloué » d'environ 251 Gio** apparaît entre C: et la partition de 730 Mio. **Rien n'est encore écrit** : l'opération est seulement en attente (compteur en bas de la fenêtre).
5. Si autre chose est en attente, *Édition → Annuler la dernière opération* jusqu'à n'avoir **qu'une seule** opération.

### E. Appliquer

1. Bouton vert **✓ Appliquer** → confirmer.
2. Une fenêtre de progression s'affiche, avec les détails de chaque phase.
3. **Attendre sans rien toucher.** Durée indicative : de 15 minutes à plus d'une heure, selon la quantité de données à déplacer. La barre peut rester longtemps immobile : c'est normal.
4. À la fin : *Toutes les opérations ont été effectuées avec succès* → **Fermer**.
5. Vérifier sur la carte : `nvme0n1p3` fait environ 680 Gio, suivi d'environ 251 Gio **non alloués**.
6. Si GParted signale une erreur, cliquer sur **Enregistrer les détails** (le fichier `gparted_details.htm` peut être copié sur la clé), photographier l'écran et **ne pas relancer**.

### F. Revenir sur Windows

1. Icône **Exit** sur le bureau GParted → **Shutdown**. Retirer la clé quand l'écran le demande.
2. Démarrer Windows. Une **vérification du disque** peut se lancer : la laisser aller au bout.
3. Gestion des disques : C: fait environ **679,7 Go**, suivie d'environ **251 Go « Non alloué »**. Ne rien créer dans cet espace.
4. **Réactiver le fichier d'échange** (recocher « Automatically manage… »), puis redémarrer.
5. Noter le résultat dans [JOURNAL.md](JOURNAL.md) et dans [HARDWARE.md](HARDWARE.md). La suite reprend au GUIDE, étape 1.

---

## Messages possibles et réponses

| Message ou symptôme | Signification | Que faire |
|---|---|---|
| Point d'exclamation sur `nvme0n1p3`, « NTFS is inconsistent » ou « marked dirty » | NTFS n'est pas propre (arrêt brutal, vérification en attente) | revenir sur Windows, `chkdsk C: /f` (terminal administrateur, accepter la vérification au redémarrage), redémarrer **deux fois**, puis recommencer |
| « Windows is hibernated » / « unclean shutdown » | Windows n'a pas été arrêté complètement | dans Windows : `powercfg /h off`, puis *Arrêter* (pas *Redémarrer*) |
| Cadenas sur une partition | partition montée ou utilisée | ne rien forcer : redémarrer GParted |
| L'opération échoue en phase 1 (contrôle) | `ntfsresize` a trouvé un problème **avant** d'écrire | rien n'est modifié : enregistrer les détails, ne pas relancer, demander de l'aide |
| L'opération échoue en phase 2 ou 3 | problème **pendant** l'écriture | **ne pas redémarrer sur Windows tout de suite** : enregistrer les détails, photographier, demander de l'aide |
| Windows lance une vérification du disque au démarrage | prévu après un redimensionnement NTFS | la laisser finir |

## Et après ?

L'espace non alloué est utilisé par l'étape 3 du guide (`10-partition.sh plan`), qui crée les partitions Linux **depuis la clé Arch**. On ne crée rien dans cet espace depuis Windows ni depuis GParted.
