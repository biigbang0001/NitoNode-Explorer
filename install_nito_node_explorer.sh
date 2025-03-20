#!/bin/bash

# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root."
  exit 1
fi

# Étape 1 : Demander les informations
echo "Entrez le nom de domaine pour l’explorateur (ex. : nito-explorer.nitopool.fr) :"
read DOMAIN
echo "Entrez le port RPC du node Nito (ex. : 8825 pour Nito) :"
read RPC_PORT
echo "Entrez le nom d'utilisateur RPC pour le nœud Nito (ex. : user) :"
read RPC_USER
echo "Entrez le mot de passe RPC pour le nœud Nito (ex. : pass) :"
read RPC_PASSWORD
echo "Entrez le répertoire où installer l'explorateur (ex. : /root ou /var/www, appuyez sur Entrée pour utiliser /root par défaut) :"
read INSTALL_DIR
# Si l'utilisateur n'entre rien, utiliser /root par défaut
if [ -z "$INSTALL_DIR" ]; then
  INSTALL_DIR="/root"
fi
# S'assurer que le répertoire se termine sans "/"
INSTALL_DIR=$(echo "$INSTALL_DIR" | sed 's:/*$::')

# Définir les chemins dynamiques
NITO_DIR="$INSTALL_DIR/.nito"
NITO_NODE_DIR="$INSTALL_DIR/nito-node"
EXPLORER_DIR="$INSTALL_DIR/explorer"
TEMP_DIR="$INSTALL_DIR/NitoNode-Explorer"

# Étape 2 : Créer le dossier temporaire pour les téléchargements
echo "Création du dossier temporaire dans $TEMP_DIR..."
mkdir -p "$TEMP_DIR"

# S'assurer que le répertoire d'installation a les bonnes permissions (seulement si nouvellement créé)
if [ ! -d "$INSTALL_DIR" ]; then
  mkdir -p "$INSTALL_DIR"
  chown root:root "$INSTALL_DIR"
  chmod 755 "$INSTALL_DIR"
fi

# Étape 3 : Mise à jour et installation des dépendances nécessaires
echo "Mise à jour du système et installation des dépendances..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl cmake git build-essential libtool autotools-dev automake pkg-config bsdmainutils python3 software-properties-common ufw net-tools jq unzip libzmq3-dev libminiupnpc-dev libssl-dev libevent-dev wget

# Étape 4 : Installer une version de base de Node.js et npm pour NVM
echo "Installation d'une version de base de Node.js et npm pour NVM..."
sudo apt install -y nodejs npm
# Vérifier que npm est bien installé
if ! command -v npm &> /dev/null; then
  echo "Erreur : npm n'a pas pu être installé. Vérifiez votre connexion Internet et les dépôts apt."
  exit 1
fi

# Étape 5 : Téléchargement et installation du Node NitoCoin
echo "🚀 Installation du Node NitoCoin démarrée..."
cd "$INSTALL_DIR"
wget https://github.com/NitoNetwork/Nito-core/releases/download/v2.0.1/nito-2-0-1-x86_64-linux-gnu.tar.gz
tar -xzvf nito-2-0-1-x86_64-linux-gnu.tar.gz
rm nito-2-0-1-x86_64-linux-gnu.tar.gz
mv nito-*/ nito-node

# Ajouter les binaires au PATH globalement via /etc/environment
if ! grep -q "$NITO_NODE_DIR/bin" /etc/environment; then
    echo "PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$NITO_NODE_DIR/bin\"" | sudo tee /etc/environment > /dev/null
fi

# Ajouter le PATH à ~/.bashrc pour les sessions shell de root
if ! grep -q "$NITO_NODE_DIR/bin" ~/.bashrc; then
    echo "export PATH=\"\$PATH:$NITO_NODE_DIR/bin\"" | sudo tee -a ~/.bashrc > /dev/null
fi

# Appliquer le PATH immédiatement dans ce script
export PATH="$PATH:$NITO_NODE_DIR/bin"

# Étape 6 : Configuration du fichier nito.conf avec les identifiants personnalisés
mkdir -p "$NITO_DIR"
cat <<EOF > "$NITO_DIR/nito.conf"
maxconnections=300
server=1
daemon=1
txindex=1
prune=0
datadir=$NITO_DIR
port=8820
rpcuser=$RPC_USER
rpcpassword=$RPC_PASSWORD
rpcport=$RPC_PORT
rpcbind=0.0.0.0
rpcallowip=0.0.0.0/0
zmqpubhashblock=tcp://0.0.0.0:28825
listen=1
listenonion=0
proxy=
bind=0.0.0.0
EOF

# Supprimer conflit potentiel
rm -f "$NITO_NODE_DIR/nito.conf"

# Étape 7 : Configuration du service systemd NitoCoin
cat <<EOF > /etc/systemd/system/nitocoin.service
[Unit]
Description=NitoCoin Node
After=network.target

[Service]
User=root
Group=root
Type=forking
ExecStart=$NITO_NODE_DIR/bin/nitod -daemon -conf=$NITO_DIR/nito.conf
ExecStop=$NITO_NODE_DIR/bin/nito-cli stop
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=120
StartLimitBurst=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Activation du service systemd
sudo systemctl daemon-reload
sudo systemctl enable nitocoin
sudo systemctl start nitocoin

# Étape 8 : Configuration du firewall UFW pour le nœud
echo "Configuration du firewall pour le nœud Nito..."
sudo ufw allow 8820/tcp   # Port réseau P2P
sudo ufw allow ssh        # SSH pour sécurité

# Étape 9 : Vérifications du nœud avant de continuer
echo "⏳ Attente démarrage node (20 sec)..."
sleep 20

echo "🔍 Vérification du statut du node avec systemctl :"
sudo systemctl status nitocoin | grep Active

echo "🔍 Vérification RPC avec nito-cli :"
nito-cli getblockcount

# Recharger .bashrc pour appliquer le PATH au shell courant
source ~/.bashrc

echo "🎉 Node NitoCoin opérationnel. Poursuite avec l'installation de l'explorateur..."

# Étape 10 : Configurer le pare-feu pour l'explorateur
echo "Configuration du pare-feu pour l'explorateur..."
ufw allow 80    # Temporaire pour Certbot
ufw allow 443   # HTTPS
ufw allow 27017 # MongoDB (Docker)
ufw allow "$RPC_PORT" # Port RPC
ufw --force enable

# Étape 11 : Installer Node.js avec NVM (version 16.20.2 pour compatibilité)
echo "Installation de Node.js 16.20.2 via NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 16.20.2
nvm use 16.20.2
node -v
npm -v

# Définir le chemin de npm dynamiquement
NPM_PATH="/root/.nvm/versions/node/v16.20.2/bin/npm"

# Étape 12 : Installer Docker
echo "Installation de Docker..."
apt install -y docker.io
systemctl start docker
systemctl enable docker

# Vérification Docker
if ! docker --version; then
  echo "Erreur : Docker n’est pas installé correctement."
  exit 1
fi

# Étape 13 : Lancer MongoDB 7.0.2 en conteneur Docker avec redémarrage automatique
echo "Lancement de MongoDB 7.0.2 via Docker..."
docker pull mongo:7.0.2
mkdir -p /data/db /var/log/mongodb
docker run -d --name mongodb \
  --restart unless-stopped \
  -p 27017:27017 \
  -v /data/db:/data/db \
  -v /var/log/mongodb:/var/log/mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=eiquidus \
  -e MONGO_INITDB_ROOT_PASSWORD=Nd^p2d77ceBX!L \
  mongo:7.0.2

# Vérification MongoDB
sleep 5 # Attendre que le conteneur démarre
if docker ps | grep mongodb; then
  echo "MongoDB 7.0.2 est actif dans Docker."
else
  echo "Erreur : MongoDB ne démarre pas. Vérifiez avec 'docker logs mongodb'."
  exit 1
fi

# Configuration de la base de données
echo "Configuration de la base de données MongoDB..."
docker exec -i mongodb mongosh -u eiquidus -p Nd^p2d77ceBX!L <<EOF
use explorerdb
db.createUser({ user: "eiquidus", pwd: "Nd^p2d77ceBX!L", roles: ["readWrite"] })
exit
EOF

# Étape 14 : Installer Nginx
echo "Installation de Nginx..."
apt install nginx -y
systemctl start nginx
systemctl enable nginx

# Étape 15 : Installer eIquidus
echo "Téléchargement d’eIquidus dans $EXPLORER_DIR..."
git clone https://github.com/team-exor/eiquidus "$EXPLORER_DIR"
cd "$EXPLORER_DIR"
"$NPM_PATH" install --only=prod

# Étape 16 : Télécharger et intégrer les images Nito et settings.json
echo "Téléchargement des images Nito et settings.json..."
mkdir -p "$EXPLORER_DIR/public/img"
wget -O "$TEMP_DIR/settings.json" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/settings.json"
wget -O "$TEMP_DIR/logo.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/logo.png"
wget -O "$TEMP_DIR/header-logo.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/header-logo.png"
wget -O "$TEMP_DIR/page-title-img.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/page-title-img.png"
wget -O "$TEMP_DIR/favicon-32.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-32.png"
wget -O "$TEMP_DIR/favicon-128.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-128.png"
wget -O "$TEMP_DIR/favicon-180.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-180.png"
wget -O "$TEMP_DIR/favicon-192.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-192.png"
wget -O "$TEMP_DIR/external.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/external.png"
wget -O "$TEMP_DIR/coingecko.png" "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/coingecko.png"

# Copier les images dans les bons dossiers
# Favicons dans explorer/public/
cp "$TEMP_DIR/favicon-32.png" "$EXPLORER_DIR/public/"
cp "$TEMP_DIR/favicon-128.png" "$EXPLORER_DIR/public/"
cp "$TEMP_DIR/favicon-180.png" "$EXPLORER_DIR/public/"
cp "$TEMP_DIR/favicon-192.png" "$EXPLORER_DIR/public/"
# Autres images dans explorer/public/img/
cp "$TEMP_DIR/logo.png" "$EXPLORER_DIR/public/img/"
cp "$TEMP_DIR/header-logo.png" "$EXPLORER_DIR/public/img/"
cp "$TEMP_DIR/page-title-img.png" "$EXPLORER_DIR/public/img/"
cp "$TEMP_DIR/external.png" "$EXPLORER_DIR/public/img/"
cp "$TEMP_DIR/coingecko.png" "$EXPLORER_DIR/public/img/"

# Copier settings.json dans explorer/ et modifier les identifiants et les chemins SSL
cp "$TEMP_DIR/settings.json" "$EXPLORER_DIR/"
# Modifier settings.json pour insérer les identifiants personnalisés et le port RPC
sed -i "s/\"username\": \"user\"/\"username\": \"$RPC_USER\"/" "$EXPLORER_DIR/settings.json"
sed -i "s/\"password\": \"pass\"/\"password\": \"$RPC_PASSWORD\"/" "$EXPLORER_DIR/settings.json"
sed -i "s/\"port\": 8825/\"port\": $RPC_PORT/" "$EXPLORER_DIR/settings.json"
# Modifier les chemins SSL pour correspondre au domaine saisi
sed -i "s|/etc/letsencrypt/live/nito-explorer.nitopool.fr/cert.pem|/etc/letsencrypt/live/$DOMAIN/cert.pem|" "$EXPLORER_DIR/settings.json"
sed -i "s|/etc/letsencrypt/live/nito-explorer.nitopool.fr/chain.pem|/etc/letsencrypt/live/$DOMAIN/chain.pem|" "$EXPLORER_DIR/settings.json"
sed -i "s|/etc/letsencrypt/live/nito-explorer.nitopool.fr/privkey.pem|/etc/letsencrypt/live/$DOMAIN/privkey.pem|" "$EXPLORER_DIR/settings.json"

# Étape 17 : Installer Certbot et générer le certificat via Nginx
echo "Installation de Certbot..."
apt install snapd -y
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

echo "Configuration temporaire de Nginx pour Certbot..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF
nginx -t && systemctl restart nginx

echo "Génération du certificat SSL..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN"
# Vérifier que le certificat a été généré
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "Erreur : Échec de la génération du certificat SSL. Vérifiez la configuration de votre domaine et les logs de Certbot (/var/log/letsencrypt/letsencrypt.log)."
  exit 1
fi

# Étape 18 : Configurer Nginx avec SSL
echo "Configuration finale de Nginx avec SSL..."
cat > /etc/nginx/sites-available/eiquidus <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://localhost:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF
ln -s /etc/nginx/sites-available/eiquidus /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# Étape 19 : Installer et lancer avec PM2
echo "Installation de PM2 et démarrage..."
"$NPM_PATH" install -g pm2
# Vérifier que PM2 est bien installé
if ! command -v pm2 &> /dev/null; then
  echo "Erreur : PM2 n'a pas pu être installé correctement. Tentative de réinstallation..."
  "$NPM_PATH" install -g pm2 --force
fi
# Ajouter le chemin de PM2 au PATH si nécessaire
if ! command -v pm2 &> /dev/null; then
  export PATH="$PATH:/root/.nvm/versions/node/v16.20.2/bin"
  echo "export PATH=\"\$PATH:/root/.nvm/versions/node/v16.20.2/bin\"" >> ~/.bashrc
  source ~/.bashrc
fi
# Vérifier une dernière fois
if ! command -v pm2 &> /dev/null; then
  echo "Erreur : PM2 n'est toujours pas accessible. Vérifiez l'installation de Node.js et npm."
  exit 1
fi
cd "$EXPLORER_DIR"
"$NPM_PATH" run start-pm2

# Étape 20 : Configurer PM2 pour redémarrer automatiquement au boot
echo "Configuration de PM2 pour redémarrage automatique..."
pm2 startup systemd -u root
pm2 save

# Étape 21 : Synchronisation initiale et configuration du cron
echo "Synchronisation initiale de l'explorateur..."
cd "$EXPLORER_DIR"
"$NPM_PATH" run sync-blocks
# Vérifier que la synchronisation initiale a réussi
if [ $? -ne 0 ]; then
  echo "Erreur : Échec de la synchronisation initiale. Vérifiez les logs de l'explorateur et assurez-vous que le nœud NitoCoin est opérationnel."
  exit 1
fi

# Configurer le cron pour synchroniser toutes les minutes
echo "Configuration du cron pour synchronisation automatique toutes les minutes..."
echo "*/1 * * * * cd $EXPLORER_DIR && $NPM_PATH run sync-blocks > /dev/null 2>&1" | crontab -

# Vérifier que le cron est bien configuré
echo "Vérification de la configuration du cron..."
crontab -l

# Nettoyer le dossier temporaire
echo "Nettoyage du dossier temporaire $TEMP_DIR..."
rm -rf "$TEMP_DIR"

echo "🎉 Installation complète terminée !"
echo "Node NitoCoin et l'explorateur eIquidus sont opérationnels."
echo "Accédez à l'explorateur via : https://$DOMAIN"
echo "Détails du nœud :"
echo " - Port P2P : 8820"
echo " - Port RPC : $RPC_PORT"
echo " - Username : $RPC_USER"
echo " - Password : $RPC_PASSWORD"
echo " - Répertoire d'installation : $INSTALL_DIR"
