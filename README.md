# NitoNode-Explorer

NitoNode+Explorer
Ce dépôt contient un script d'auto-installation pour configurer un nœud NitoCoin et un explorateur de blockchain eIquidus sur un serveur Linux (Ubuntu recommandé). Tout est automatisé : le nœud et l'explorateur seront installés, configurés, et synchronisés automatiquement.

Prérequis
Un serveur Linux (Ubuntu 20.04 ou 22.04 recommandé).
Accès root.
Une connexion Internet stable.
Un nom de domaine configuré pour pointer vers l'adresse IP de ton serveur (nécessaire pour l'explorateur).
Installation

Télécharger le script d'installation 
Exécute la commande suivante pour télécharger le script depuis GitHub :
wget https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/install_nito_node_explorer.sh

Rendre le script exécutable :
chmod +x install_nito_node_explorer.sh

Lancer l'installation :
./install_nito_node_explorer.sh

On te demandera deux informations :
Nom de domaine : Entre le domaine de ton explorateur (ex. : nito-explorer.nitopool.fr).
Port RPC : Entre le port RPC de ton nœud Nito (par défaut : 8825).
Le script installera automatiquement :

Le nœud NitoCoin (démarré et synchronisé).
L'explorateur eIquidus (avec MongoDB, Nginx, et PM2).
Les images personnalisées pour l'explorateur (logo, favicons, etc.).
Un certificat SSL via Certbot pour sécuriser l'accès à l'explorateur.
Attendre la fin de l'installation :

Le script prendra environ 10 à 20 minutes, selon la vitesse de ton serveur et de ta connexion.
À la fin, tu verras un message indiquant que l'installation est terminée, avec l'URL de ton explorateur (ex. : https://nito-explorer.nitopool.fr).
Commandes utiles
Gérer le nœud NitoCoin

Vérifier le statut du nœud:
systemctl status nitocoin

Arrêter le nœud :
systemctl stop nitocoin

Redémarrer le nœud :
systemctl restart nitocoin

Vérifier la progression de la synchronisation :
nito-cli getblockcount

Obtenir des informations sur le nœud :
nito-cli getinfo

Gérer l'explorateur eIquidus
Vérifier le statut de l'explorateur (géré par PM2) :
pm2 list

Arrêter l'explorateur :
pm2 stop explorer

Redémarrer l'explorateur :
pm2 restart explorer

Vérifier les logs de l'explorateur :
pm2 logs explorer

Vérifier MongoDB (utilisé par l'explorateur) :
docker ps  # Vérifie que le conteneur MongoDB est en cours d'exécution
docker logs mongodb  # Affiche les logs de MongoDB

Forcer une resynchronisation manuelle de l'explorateur :
cd /root/explorer
npm run sync-blocks

Sécurité post-installation
Pour des raisons de sécurité, il est fortement recommandé de changer les identifiants par défaut (user et pass) utilisés pour le nœud Nito et l'explorateur eIquidus. Voici comment procéder :

1. Changer les identifiants du nœud Nito
Édite le fichier de configuration du nœud :
nano /root/.nito/nito.conf

Modifie les lignes suivantes avec un nouveau rpcuser et rpcpassword sécurisés :
rpcuser=ton-nouveau-user
rpcpassword=ton-nouveau-mot-de-passe

Sauvegarde (Ctrl + X, Y, Entrée).
Redémarre le nœud pour appliquer les changements :
systemctl restart nitocoin

. Changer les identifiants dans l'explorateur eIquidus
Édite le fichier de configuration de l'explorateur :
nano /root/explorer/settings.json

Modifie les identifiants dans la section wallet pour qu'ils correspondent à ceux du nœud :
"wallet": {
  "host": "127.0.0.1",
  "port": 8825,
  "username": "ton-nouveau-user",
  "password": "ton-nouveau-mot-de-passe"
}

Sauvegarde (Ctrl + X, Y, Entrée).
Redémarre l'explorateur pour appliquer les changements :
pm2 restart explorer

Accéder à l'explorateur
Une fois l'installation terminée, tu peux accéder à ton explorateur via l'URL suivante :
https://<ton-domaine>

Exemple : https://nito-explorer.nitopool.fr

Dépannage
Si l'explorateur ne se charge pas :
Vérifie que Nginx est en cours d'exécution : systemctl status nginx.
Vérifie les logs de l'explorateur : pm2 logs explorer.
Vérifie que MongoDB est en cours d'exécution : docker ps.
Si le nœud ne se synchronise pas :
Vérifie les logs du nœud : journalctl -u nitocoin.
Assure-toi que le port 8820 est ouvert : ufw status.
