## Présentation

**NitoNode-Explorer** est un script d'auto-installation conçu pour déployer un nœud complet NitoCoin ([https://github.com/NitoNetwork/Nito-core](https://github.com/NitoNetwork/Nito-core)) et un explorateur de blockchain eIquidus ([https://github.com/team-exor/eiquidus](https://github.com/team-exor/eiquidus)) sur un serveur Linux (Ubuntu 22.04 recommandé). Ce script automatise l'installation, la configuration, et la synchronisation des deux composants, te permettant d'avoir un nœud opérationnel et un explorateur web accessible en quelques étapes simples.

### Fonctionnalités
- Installation automatique du nœud NitoCoin (version 2.0.1).
- Installation et configuration de l'explorateur eIquidus avec une interface personnalisée pour NitoCoin.
- Synchronisation automatique de la blockchain pour le nœud et l'explorateur (toutes les minutes via un cron).
- Configuration d'un certificat SSL via Certbot ([https://certbot.eff.org/](https://certbot.eff.org/)) pour sécuriser l'accès à l'explorateur, avec des chemins SSL adaptés dynamiquement au domaine saisi.
- Personnalisation avec des images spécifiques (logo, favicons, etc.) pour l'explorateur.
- Configuration sécurisée des identifiants RPC (nom d'utilisateur et mot de passe) définis par l'utilisateur au début de l'installation.
- Redémarrage automatique du nœud et de l'explorateur (y compris MongoDB) en cas de redémarrage du serveur.
- Option pour choisir le répertoire d'installation.

## Prérequis
Avant de commencer, assure-toi d'avoir :
- Un serveur Linux (Ubuntu 22.04 recommandé).
- Accès root sur le serveur.
- Une connexion Internet stable.
- Un nom de domaine configuré pour pointer vers l'adresse IP de ton serveur (nécessaire pour l'explorateur).
    - Les ports nécessaires (8820 pour le nœud, 80/443 pour l'explorateur doivent être accessibles. Le script ouvrira automatiquement ces ports via UFW.

    ## Installation

    L'installation est entièrement automatisée. Suis ces étapes pour installer le nœud NitoCoin et l'explorateur eIquidus :
    - Le script te posera cinq questions :
     - **Nom de domaine** : Entre le domaine de ton explorateur (ex. : `nito-explorer.exemple.fr`).
     - **Port RPC** : Entre le port RPC de ton nœud Nito (par défaut : `8825`).
     - **Nom d'utilisateur RPC** : Entre un nom d'utilisateur pour l'accès RPC (ex. : `user`).
     - **Mot de passe RPC** : Entre un mot de passe sécurisé pour l'accès RPC (ex. : `pass`).
     - **Répertoire d'installation** : Entre le répertoire où installer l'explorateur (ex. : `/var/www`, appuie sur Entrée pour utiliser `/root` par défaut).

   **Télécharger la commande d'installation** 
        
   Exécute la commande suivante pour télécharger et executer le script depuis GitHub ([https://github.com/biigbang0001/NitoNode-Explorer](https://github.com/biigbang0001/NitoNode-Explorer)) :  
   ```bash
   wget https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/install_nito_node_explorer.sh
   chmod +x install_nito_node_explorer.sh
   ./install_nito_node_explorer.sh
   ```

   **Attendre la fin de l'installation** :
   - L'installation prend environ 10 à 20 minutes, selon la vitesse de ton serveur et de ta connexion Internet.
   - À la fin, un message s'affichera avec l'URL de ton explorateur (ex. : `https://nito-explorer.exemple.fr`), les identifiants que tu as choisis, et le répertoire d'installation.
   - L'explorateur peut initialement être en retard dans la synchronisation. Attends quelques minutes pour que le cron mette à jour les données.

## Utilisation

Une fois l'installation terminée, le nœud NitoCoin et l'explorateur eIquidus seront opérationnels. Voici comment les gérer et les utiliser.

### Accéder à l'explorateur
- Ouvre ton navigateur et accède à l'URL suivante :  
  ```
  https://<ton-domaine>
  ```
  Exemple : `https://nito-explorer.exemple.fr`

### Commandes pour gérer le nœud NitoCoin
Le nœud NitoCoin est géré via systemd ([https://systemd.io/](https://systemd.io/)). Voici les commandes utiles (remplace `<répertoire choisi>` par le répertoire que tu as spécifié, ex. `/root` ou `/var/www`) :

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
  nito-cli -conf=<répertoire choisi>/.nito/nito.conf getblockcount
  ```
- Obtenir des informations sur le nœud :  
  ```bash
  nito-cli -conf=<répertoire choisi>/.nito/nito.conf getinfo
  ```
- Consulter les logs du nœud :  
  ```bash
  journalctl -u nitocoin
  ```

### Commandes pour gérer l'explorateur eIquidus
L'explorateur eIquidus est géré via PM2 ([https://pm2.keymetrics.io/](https://pm2.keymetrics.io/)), et la base de données utilise MongoDB ([https://www.mongodb.com/](https://www.mongodb.com/)) dans un conteneur Docker. Voici les commandes utiles (remplace `<répertoire choisi>` par le répertoire que tu as spécifié, ex. `/root` ou `/var/www`) :

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
  cd <répertoire choisi>/explorer
  npm run sync-blocks
  ```
- Vérifier l'état de la synchronisation automatique (cron) :  
  ```bash
  crontab -l
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

Si tu rencontres des problèmes, voici quelques étapes pour diagnostiquer et résoudre les erreurs (remplace `<répertoire choisi>` par le répertoire que tu as spécifié, ex. `/root` ou `/var/www`) :

- **Si l'explorateur ne se charge pas** :
  - Vérifie que Nginx ([https://nginx.org/](https://nginx.org/)) est en cours d'exécution :  
    ```bash
    systemctl status nginx
    ```
  - Vérifie les logs de l'explorateur :  
    ```bash
    pm2 logs explorer
    ```
  - Vérifie que MongoDB ([https://www.mongodb.com/](https://www.mongodb.com/)) est en cours d'exécution :  
    ```bash
    docker ps
    ```
  - Redémarre l'explorateur si nécessaire :  
    ```bash
    pm2 restart explorer
    ```

- **Si l'explorateur n'est pas à jour** :
  - Vérifie que le cron est bien configuré :  
    ```bash
    crontab -l
    ```
  - Vérifie les logs du cron pour voir s'il y a des erreurs :  
    ```bash
    grep CRON /var/log/syslog
    ```
  - Force une synchronisation manuelle :  
    ```bash
    cd <répertoire choisi>/explorer
    npm run sync-blocks
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

## Support
Si tu as des questions ou des problèmes, tu peux ouvrir une issue sur ce dépôt GitHub ([https://github.com/biigbang0001/NitoNode-Explorer/issues](https://github.com/biigbang0001/NitoNode-Explorer/issues)).
```
