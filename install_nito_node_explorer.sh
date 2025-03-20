#!/bin/bash

# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root."
  exit 1
fi

# Étape 1 : Demander les informations
echo "Entrez le nom de domaine pour l’explorateur (ex. : nito-explorer.nitopool.fr) :"
read DOMAIN
echo "Entrez le port RPC de votre portefeuille (ex. : 8825 pour Nito) :"
read RPC_PORT

# Étape 2 : Créer le dossier NitoNode-Explorer localement
echo "Création du dossier NitoNode-Explorer..."
mkdir -p /root/NitoNode-Explorer

# Étape 3 : Mise à jour et installation des dépendances nécessaires
echo "Mise à jour du système et installation des dépendances..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl cmake git build-essential libtool autotools-dev automake pkg-config bsdmainutils python3 software-properties-common ufw net-tools jq unzip libzmq3-dev libminiupnpc-dev libssl-dev libevent-dev wget

# Étape 4 : Téléchargement et installation du Node NitoCoin
echo "🚀 Installation du Node NitoCoin démarrée..."
cd /root
wget https://github.com/NitoNetwork/Nito-core/releases/download/v2.0.1/nito-2-0-1-x86_64-linux-gnu.tar.gz
tar -xzvf nito-2-0-1-x86_64-linux-gnu.tar.gz
rm nito-2-0-1-x86_64-linux-gnu.tar.gz
mv nito-*/ nito-node

# Ajouter les binaires au PATH globalement via /etc/environment
if ! grep -q "/root/nito-node/bin" /etc/environment; then
    echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/nito-node/bin"' | sudo tee /etc/environment > /dev/null
fi

# Ajouter le PATH à /root/.bashrc pour les sessions shell de root
if ! grep -q "/root/nito-node/bin" /root/.bashrc; then
    echo 'export PATH="$PATH:/root/nito-node/bin"' | sudo tee -a /root/.bashrc > /dev/null
fi

# Appliquer le PATH immédiatement dans ce script
export PATH="$PATH:/root/nito-node/bin"

# Étape 5 : Configuration du fichier nito.conf
mkdir -p /root/.nito
cat <<EOF > /root/.nito/nito.conf
maxconnections=300
server=1
daemon=1
txindex=1
prune=0
datadir=/root/.nito
port=8820
rpcuser=user
rpcpassword=pass
rpcport=8825
rpcbind=0.0.0.0
rpcallowip=0.0.0.0/0
zmqpubhashblock=tcp://0.0.0.0:28825
listen=1
listenonion=0
proxy=
bind=0.0.0.0
EOF

# Supprimer conflit potentiel
rm -f /root/nito-node/nito.conf

# Étape 6 : Configuration du service systemd NitoCoin
cat <<EOF > /etc/systemd/system/nitocoin.service
[Unit]
Description=NitoCoin Node
After=network.target

[Service]
User=root
Group=root
Type=forking
ExecStart=/root/nito-node/bin/nitod -daemon -conf=/root/.nito/nito.conf
ExecStop=/root/nito-node/bin/nito-cli stop
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

# Étape 7 : Configuration du firewall UFW pour le nœud
echo "Configuration du firewall pour le nœud Nito..."
sudo ufw allow 8820/tcp   # Port réseau P2P
sudo ufw allow ssh        # SSH pour sécurité

# Étape 8 : Vérifications du nœud avant de continuer
echo "⏳ Attente démarrage node (20 sec)..."
sleep 20

echo "🔍 Vérification du statut du node avec systemctl :"
sudo systemctl status nitocoin | grep Active

echo "🔍 Vérification RPC avec nito-cli :"
nito-cli getblockcount

# Recharger .bashrc pour appliquer le PATH au shell courant
source /root/.bashrc

echo "🎉 Node NitoCoin opérationnel. Poursuite avec l'installation de l'explorateur..."

# Étape 9 : Configurer le pare-feu pour l'explorateur
echo "Configuration du pare-feu pour l'explorateur..."
ufw allow 80    # Temporaire pour Certbot
ufw allow 443   # HTTPS
ufw allow 27017 # MongoDB (Docker)
ufw allow "$RPC_PORT" # Port RPC
ufw --force enable

# Étape 10 : Installer Node.js avec NVM (v20.9.0 recommandé)
echo "Installation de Node.js 20.9.0..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 20.9.0
nvm use 20.9.0
node -v
npm -v

# Étape 11 : Installer Docker
echo "Installation de Docker..."
apt install -y docker.io
systemctl start docker
systemctl enable docker

# Vérification Docker
if ! docker --version; then
  echo "Erreur : Docker n’est pas installé correctement."
  exit 1
fi

# Étape 12 : Lancer MongoDB 7.0.2 en conteneur Docker
echo "Lancement de MongoDB 7.0.2 via Docker..."
docker pull mongo:7.0.2
mkdir -p /data/db /var/log/mongodb
docker run -d --name mongodb \
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

# Étape 13 : Installer Nginx
echo "Installation de Nginx..."
apt install nginx -y
systemctl start nginx
systemctl enable nginx

# Étape 14 : Installer eIquidus
echo "Téléchargement d’eIquidus..."
git clone https://github.com/team-exor/eiquidus /root/explorer
cd /root/explorer
npm install --only=prod

# Étape 15 : Télécharger et intégrer les images Nito et settings.json
echo "Téléchargement des images Nito et settings.json..."
mkdir -p /root/explorer/public/img
wget -O /root/NitoNode-Explorer/settings.json "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/settings.json"
wget -O /root/NitoNode-Explorer/logo.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/logo.png"
wget -O /root/NitoNode-Explorer/header-logo.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/header-logo.png"
wget -O /root/NitoNode-Explorer/page-title-img.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/page-title-img.png"
wget -O /root/NitoNode-Explorer/favicon-32.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-32.png"
wget -O /root/NitoNode-Explorer/favicon-128.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-128.png"
wget -O /root/NitoNode-Explorer/favicon-180.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-180.png"
wget -O /root/NitoNode-Explorer/favicon-192.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/favicon-192.png"
wget -O /root/NitoNode-Explorer/external.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/external.png"
wget -O /root/NitoNode-Explorer/coingecko.png "https://raw.githubusercontent.com/biigbang0001/NitoNode-Explorer/main/coingecko.png"

# Copier les images dans les bons dossiers
# Favicons dans explorer/public/
cp /root/NitoNode-Explorer/favicon-32.png /root/explorer/public/
cp /root/NitoNode-Explorer/favicon-128.png /root/explorer/public/
cp /root/NitoNode-Explorer/favicon-180.png /root/explorer/public/
cp /root/NitoNode-Explorer/favicon-192.png /root/explorer/public/
# Autres images dans explorer/public/img/
cp /root/NitoNode-Explorer/logo.png /root/explorer/public/img/
cp /root/NitoNode-Explorer/header-logo.png /root/explorer/public/img/
cp /root/NitoNode-Explorer/page-title-img.png /root/explorer/public/img/
cp /root/NitoNode-Explorer/external.png /root/explorer/public/img/
cp /root/NitoNode-Explorer/coingecko.png /root/explorer/public/img/
# Copier settings.json dans explorer/
cp /root/NitoNode-Explorer/settings.json /root/explorer/

# Étape 16 : Installer Certbot et générer le certificat via Nginx
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

# Étape 17 : Configurer Nginx avec SSL
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

# Étape 18 : Installer et lancer avec PM2
echo "Installation de PM2 et démarrage..."
npm install -g pm2
cd /root/explorer
npm run start-pm2

# Étape 19 : Synchronisation
echo "Configuration de la synchronisation..."
npm run sync-blocks
echo "*/1 * * * * cd /root/explorer && npm run sync-blocks > /dev/null 2>&1" | crontab -

echo "🎉 Installation complète terminée !"
echo "Node NitoCoin et l'explorateur eIquidus sont opérationnels."
echo "Accédez à l'explorateur via : https://$DOMAIN"
echo "Détails du nœud :"
echo " - Port P2P : 8820"
echo " - Port RPC : $RPC_PORT"
echo " - Username : user"
echo " - Password : pass"
