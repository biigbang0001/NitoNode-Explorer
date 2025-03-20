## Présentation

**NitoNode-Explorer** est un script d'auto-installation conçu pour déployer un nœud complet NitoCoin (https://github.com/NitoNetwork/Nito-core) et un explorateur de blockchain eIquidus (https://github.com/team-exor/eiquidus) sur un serveur Linux (Ubuntu recommandé). Ce script automatise l'installation, la configuration, et la synchronisation des deux composants, te permettant d'avoir un nœud opérationnel et un explorateur web accessible en quelques étapes simples.

### Fonctionnalités
- Installation automatique du nœud NitoCoin (version 2.0.1).
- Installation et configuration de l'explorateur eIquidus avec une interface personnalisée pour NitoCoin.
- Synchronisation automatique de la blockchain pour le nœud et l'explorateur.
- Configuration d'un certificat SSL via Certbot (https://certbot.eff.org/) pour sécuriser l'accès à l'explorateur.
- Personnalisation avec des images spécifiques (logo, favicons, etc.) pour l'explorateur.
- Configuration sécurisée des identifiants RPC (nom d'utilisateur et mot de passe) définis par l'utilisateur au début de l'installation.

## Prérequis
Avant de commencer, assure-toi d'avoir :
- Un serveur Linux (Ubuntu 20.04 ou 22.04 recommandé).
- Accès root sur le serveur.
- Une connexion Internet stable.
- Un nom de domaine configuré pour pointer vers l'adresse IP de ton serveur (nécessaire pour l'explorateur).

## Installation

L'installation est entièrement automatisée. Suis ces étapes pour installer le nœud NitoCoin et l'explorateur eIquidus :

1. **Télécharger la commande d'installation** :  
   Exécute la commande suivante pour télécharger le script depuis GitHub (https://github.com/biigbang0001/NitoNode-Explorer) :  
   ```bash
   wget https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/install_nito_node_explorer.sh
   ```

2. **Rendre le script exécutable** :  
   Ajoute les permissions d'exécution au script :  
   ```bash
   chmod +x install_nito_node_explorer.sh
   ```

3. **Lancer l'installation** :  
   Exécute le script pour démarrer l'installation :  
   ```bash
   ./install_nito_node_explorer.sh
   ```
   - Le script te posera quatre questions :
     - **Nom de domaine** : Entre le domaine de ton explorateur (ex. : `nito-explorer.nitopool.fr`).
     - **Port RPC** : Entre le port RPC de ton nœud Nito (par défaut : `8825`).
     - **Nom d'utilisateur RPC** : Entre un nom d'utilisateur pour l'accès RPC (ex. : `user`).
     - **Mot de passe RPC** : Entre un mot de passe sécurisé pour l'accès RPC (ex. : `pass`).

   Le script effectuera les actions suivantes automatiquement :
   - Installation des dépendances nécessaires (Node.js, Docker, Nginx, etc.).
   - Téléchargement et configuration du nœud NitoCoin (version 2.0.1) avec les identifiants choisis.
   - Démarrage du nœud et début de la synchronisation de la blockchain.
   - Installation de l'explorateur eIquidus avec MongoDB (https://www.mongodb.com/) pour la base de données.
   - Configuration de Nginx (https://nginx.org/) comme reverse proxy avec un certificat SSL via Certbot (https://certbot.eff.org/).
   - Téléchargement des images personnalisées (logo, favicons, etc.) depuis le dépôt GitHub.
   - Placement des favicons (`favicon-32.png`, `favicon-128.png`, `favicon-180.png`, `favicon-192.png`) dans `explorer/public/`.
   - Placement des autres images (`logo.png`, `header-logo.png`, `page-title-img.png`, `external.png`, `coingecko.png`) dans `explorer/public/img/`.
   - Téléchargement et configuration de `settings.json` avec les identifiants choisis.
   - Lancement de l'explorateur avec PM2 (https://pm2.keymetrics.io/) et synchronisation automatique de la blockchain.

4. **Attendre la fin de l'installation** :
   - L'installation prend environ 10 à 20 minutes, selon la vitesse de ton serveur et de ta connexion Internet.
   - À la fin, un message s'affichera avec l'URL de ton explorateur (ex. : `https://nito-explorer.nitopool.fr`) et les identifiants que tu as choisis.

## Utilisation

Une fois l'installation terminée, le nœud NitoCoin et l'explorateur eIquidus seront opérationnels. Voici comment les gérer et les utiliser.

### Accéder à l'explorateur
- Ouvre ton navigateur et accède à l'URL suivante :  
  ```
  https://<ton-domaine>
  ```
  Exemple : `https://nito-explorer.nitopool.fr`

- **Note sur le favicon** : Si l'icône de la fenêtre (favicon) ne s'affiche pas correctement, vide le cache de ton navigateur ou ouvre l'explorateur en mode de navigation privée.

### Commandes pour gérer le nœud NitoCoin
Le nœud NitoCoin est géré via systemd (https://systemd.io/). Voici les commandes utiles :

- Vérifier le statut du nœud :  
  ```bash
  systemctl status nitocoin
  ```
- Arrêter le nœud :  
  ```bash
  systemctl stop nitocoin
  ```
- Redémarrer le nœud :  
  ```bash
  systemctl restart nitocoin
  ```
- Vérifier la progression de la synchronisation :  
  ```bash
  nito-cli getblockcount
  ```
- Obtenir des informations sur le nœud :  
  ```bash
  nito-cli getinfo
  ```
- Consulter les logs du nœud :  
  ```bash
  journalctl -u nitocoin
  ```

### Commandes pour gérer l'explorateur eIquidus
L'explorateur eIquidus est géré via PM2 (https://pm2.keymetrics.io/), et la base de données utilise MongoDB (https://www.mongodb.com/) dans un conteneur Docker. Voici les commandes utiles :

- Vérifier le statut de l'explorateur :  
  ```bash
  pm2 list
  ```
- Arrêter l'explorateur :  
  ```bash
  pm2 stop explorer
  ```
- Redémarrer l'explorateur :  
  ```bash
  pm2 restart explorer
  ```
- Consulter les logs de l'explorateur :  
  ```bash
  pm2 logs explorer
  ```
- Vérifier l'état de MongoDB :  
  ```bash
  docker ps  # Vérifie que le conteneur MongoDB est en cours d'exécution
  docker logs mongodb  # Affiche les logs de MongoDB
  ```
- Forcer une resynchronisation manuelle de l'explorateur :  
  ```bash
  cd /root/explorer
  npm run sync-blocks
  ```
- Vérifier l'état de Nginx :  
  ```bash
  systemctl status nginx
  ```
- Redémarrer Nginx :  
  ```bash
  systemctl restart nginx
  ```

## Dépannage

Si tu rencontres des problèmes, voici quelques étapes pour diagnostiquer et résoudre les erreurs :

- **Si l'explorateur ne se charge pas** :
  - Vérifie que Nginx (https://nginx.org/) est en cours d'exécution :  
    ```bash
    systemctl status nginx
    ```
  - Vérifie les logs de l'explorateur :  
    ```bash
    pm2 logs explorer
    ```
  - Vérifie que MongoDB (https://www.mongodb.com/) est en cours d'exécution :  
    ```bash
    docker ps
    ```
  - Redémarre l'explorateur si nécessaire :  
    ```bash
    pm2 restart explorer
    ```

- **Si le nœud ne se synchronise pas** :
  - Vérifie les logs du nœud :  
    ```bash
    journalctl -u nitocoin
    ```
  - Assure-toi que le port 8820 est ouvert :  
    ```bash
    ufw status
    ```
  - Redémarre le nœud si nécessaire :  
    ```bash
    systemctl restart nitocoin
    ```

- **Si le certificat SSL ne fonctionne pas** :
  - Vérifie les logs de Certbot :  
    ```bash
    cat /var/log/letsencrypt/letsencrypt.log
    ```
  - Renouvelle manuellement le certificat :  
    ```bash
    certbot renew
    ```
  - Redémarre Nginx :  
    ```bash
    systemctl restart nginx
    ```

- **Si le favicon ne s'affiche pas correctement** :
  - Vide le cache de ton navigateur ou ouvre l'explorateur en mode de navigation privée.
  - Vérifie que les fichiers `favicon-32.png`, `favicon-128.png`, `favicon-180.png`, et `favicon-192.png` sont bien présents dans `/root/explorer/public/` :  
    ```bash
    ls /root/explorer/public/
    ```
