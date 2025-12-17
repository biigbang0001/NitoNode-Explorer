# NITO Explorer - Installation Multi-Explorer Compatible

## Présentation

**NITO Explorer** est un script d'auto-installation conçu pour déployer un explorateur de blockchain eIquidus pour NitoCoin. Ce script est **compatible avec d'autres explorateurs** sur le même serveur (FixedCoin, etc.) grâce à des noms uniques pour MongoDB, PM2, et les ports.

### Fonctionnalités
- Installation automatique de l'explorateur eIquidus pour NITO
- **Compatible multi-explorer** : peut coexister avec d'autres explorateurs sur le même serveur
- Détecte et réutilise le container MongoDB existant (mongodb-explorer)
- Base de données séparée : `explorerdb-nito`
- Utilisateur MongoDB séparé : `eiquidus-nito`
- Processus PM2 séparé : `explorer-nito`
- Port par défaut : 3001 (configurable)
- Configuration SSL via Certbot
- Synchronisation automatique via cron

### Configuration Multi-Explorer

| Élément | NITO | FixedCoin (exemple) |
|---------|------|---------------------|
| PM2 App Name | `explorer-nito` | `explorer` |
| MongoDB Database | `explorerdb-nito` | `explorerdb` |
| MongoDB User | `eiquidus-nito` | `eiquidus` |
| Explorer Port | `3001` | `3003` |
| Install Directory | `/var/explorer-nito` | `/var/fixedcoin/explorer` |

## Prérequis

- Serveur Linux (Ubuntu 22.04 / Debian 12 recommandé)
- Accès root
- Connexion Internet stable
- Nom de domaine configuré (ex: `nito-explorer.nitopool.fr`)
- Ports 80/443 accessibles

## Installation

```bash
wget https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/install_nito_explorer.sh
chmod +x install_nito_explorer.sh
./install_nito_explorer.sh
```

### Questions posées

1. **Nom de domaine** : ex. `nito-explorer.nitopool.fr`
2. **RPC Host** : IP du nœud NITO (défaut: `127.0.0.1`)
3. **RPC Port** : Port RPC (défaut: `8825`)
4. **RPC Username** : Utilisateur RPC (défaut: `user`)
5. **RPC Password** : Mot de passe RPC (défaut: `pass`)

## Utilisation

### Accéder à l'explorateur
```
https://nito-explorer.nitopool.fr
```

### Commandes PM2 (NITO spécifique)

```bash
# Voir tous les explorateurs
pm2 list

# Voir uniquement NITO
pm2 show explorer-nito

# Logs NITO
pm2 logs explorer-nito

# Redémarrer NITO
pm2 restart explorer-nito

# Arrêter NITO (sans affecter les autres)
pm2 stop explorer-nito
```

### Commandes MongoDB

```bash
# Vérifier le container
docker ps | grep mongodb

# Se connecter à la base NITO
docker exec -it mongodb-explorer mongosh -u eiquidus-nito -p 'Nd^p2d77ceBX!L' --authenticationDatabase explorerdb-nito

# Lister les bases
docker exec mongodb-explorer mongosh -u eiquidus -p 'Nd^p2d77ceBX!L' --authenticationDatabase admin --eval "show dbs"
```

### Synchronisation manuelle

```bash
cd /var/explorer-nito/explorer
npm run sync-blocks
```

### Vérifier le cron

```bash
crontab -l | grep nito
```

## Structure des fichiers

```
/var/explorer-nito/
├── explorer/
│   ├── settings.json        # Configuration NITO
│   ├── sync-nito.sh         # Script de synchronisation
│   ├── sync-cron.log        # Logs du cron
│   └── public/img/          # Logos et images
```

## Dépannage

### L'explorateur ne démarre pas

```bash
# Vérifier les logs
pm2 logs explorer-nito --lines 50

# Vérifier la configuration MongoDB
grep -A5 dbsettings /var/explorer-nito/explorer/settings.json
```

### Erreur de connexion MongoDB

```bash
# Tester la connexion
docker exec mongodb-explorer mongosh -u eiquidus-nito -p 'Nd^p2d77ceBX!L' --authenticationDatabase explorerdb-nito --eval "db.stats()"

# Recréer l'utilisateur si nécessaire
docker exec mongodb-explorer mongosh --quiet --eval "
conn = new Mongo('mongodb://eiquidus:Nd^p2d77ceBX!L@localhost:27017/admin');
db = conn.getDB('explorerdb-nito');
db.createUser({
    user: 'eiquidus-nito',
    pwd: 'Nd^p2d77ceBX!L',
    roles: [{ role: 'readWrite', db: 'explorerdb-nito' }]
});
"
```

### Nginx renvoie 502

```bash
# Vérifier que l'explorer écoute sur le bon port
curl -I http://localhost:3001

# Vérifier la config nginx
cat /etc/nginx/sites-available/nito-explorer

# Redémarrer nginx
nginx -t && systemctl reload nginx
```

### L'explorateur n'est pas à jour

```bash
# Vérifier le cron
crontab -l | grep nito

# Forcer la synchronisation
cd /var/explorer-nito/explorer
npm run sync-blocks

# Voir les logs de sync
tail -f /var/explorer-nito/explorer/sync-cron.log
```

## Désinstallation

Pour supprimer NITO sans affecter les autres explorateurs :

```bash
# Arrêter et supprimer de PM2
pm2 stop explorer-nito
pm2 delete explorer-nito
pm2 save

# Supprimer le cron
crontab -l | grep -v "sync-nito.sh" | crontab -

# Supprimer les fichiers
rm -rf /var/explorer-nito

# Supprimer la base MongoDB (optionnel)
docker exec mongodb-explorer mongosh -u eiquidus -p 'Nd^p2d77ceBX!L' --authenticationDatabase admin --eval "
db.getSiblingDB('explorerdb-nito').dropDatabase()
"

# Supprimer la config nginx
rm /etc/nginx/sites-enabled/nito-explorer
rm /etc/nginx/sites-available/nito-explorer
nginx -t && systemctl reload nginx
```

## Informations NITO

| Paramètre | Valeur |
|-----------|--------|
| Coin | NITO |
| Symbole | NITO |
| Port RPC | 8825 |
| Port P2P | 8820 |
| Genesis Block | `00000000103d1acbedc9bb8ff2af8cb98a751965e784b4e1f978f3d5544c6c3c` |
| Genesis TX | `90b863a727d4abf9838e8df221052e418d70baf996e2cea3211e8df4da1bb131` |

## Support

Pour toute question ou problème, ouvrir une issue sur GitHub :
https://github.com/biigbang0001/NitoNode-Explorer/issues
