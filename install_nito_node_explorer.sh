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

# Étape 2 : Créer le dossier NitoNode+Explorer localement
echo "Création du dossier NitoNode+Explorer..."
mkdir -p /root/NitoNode+Explorer

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

# Étape 15 : Télécharger et intégrer les images Nito
echo "Téléchargement des images Nito..."
mkdir -p /root/explorer/public/img
wget -O /root/NitoNode+Explorer/nito-logo.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/nito-logo.png"
wget -O /root/NitoNode+Explorer/nito-header-logo.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/nito-header-logo.png"
wget -O /root/NitoNode+Explorer/nito-page-title-img.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/nito-page-title-img.png"
wget -O /root/NitoNode+Explorer/favicon-32.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/favicon-32.png"
wget -O /root/NitoNode+Explorer/favicon-128.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/favicon-128.png"
wget -O /root/NitoNode+Explorer/favicon-180.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/favicon-180.png"
wget -O /root/NitoNode+Explorer/favicon-192.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/favicon-192.png"
wget -O /root/NitoNode+Explorer/external.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/external.png"
wget -O /root/NitoNode+Explorer/coingecko.png "https://raw.githubusercontent.com/biigbang0001/NitoNode+Explorer/main/coingecko.png"

# Copier les images dans le dossier public d'eIquidus
cp /root/NitoNode+Explorer/nito-logo.png /root/explorer/public/img/
cp /root/NitoNode+Explorer/nito-header-logo.png /root/explorer/public/img/
cp /root/NitoNode+Explorer/nito-page-title-img.png /root/explorer/public/img/
cp /root/NitoNode+Explorer/favicon-32.png /root/explorer/public/
cp /root/NitoNode+Explorer/favicon-128.png /root/explorer/public/
cp /root/NitoNode+Explorer/favicon-180.png /root/explorer/public/
cp /root/NitoNode+Explorer/favicon-192.png /root/explorer/public/
cp /root/NitoNode+Explorer/external.png /root/explorer/public/img/
cp /root/NitoNode+Explorer/coingecko.png /root/explorer/public/img/

# Étape 16 : Configuration eIquidus avec settings.json
echo "Configuration d’eIquidus avec settings.json..."
cat > /root/NitoNode+Explorer/settings.json <<'EOF'
{
  "locale": "locale/en.json",
  "dbsettings": {
    "user": "eiquidus",
    "password": "Nd^p2d77ceBX!L",
    "database": "explorerdb",
    "address": "localhost",
    "port": 27017
  },
  "wallet": {
    "host": "127.0.0.1",
    "port": 8825,
    "username": "user",
    "password": "pass"
  },
  "webserver": {
    "port": 3001,
    "tls": {
      "enabled": false,
      "port": 443,
      "always_redirect": true,
      "cert_file": "/etc/letsencrypt/live/nito-explorer.nitopool.fr/cert.pem",
      "chain_file": "/etc/letsencrypt/live/nito-explorer.nitopool.fr/chain.pem",
      "key_file": "/etc/letsencrypt/live/nito-explorer.nitopool.fr/privkey.pem"
    },
    "cors": {
      "enabled": true,
      "corsorigin": "*"
    }
  },
  "coin": {
    "name": "NITO",
    "symbol": "Nito"
  },
  "network_history": {
    "enabled": true,
    "max_saved_records": 10080
  },
  "shared_pages": {
    "theme": "Cyborg",
    "page_title": "eIquidus",
    "favicons": {
      "favicon32": "favicon-32.png",
      "favicon128": "favicon-128.png",
      "favicon180": "favicon-180.png",
      "favicon192": "favicon-192.png"
    },
    "logo": "/img/nito-logo.png",
    "date_time": {
      "display_format": "LLL dd, yyyy HH:mm:ss ZZZZ",
      "timezone": "utc",
      "enable_alt_timezone_tooltips": false
    },
    "table_header_bgcolor": "",
    "confirmations": 101,
    "difficulty": "POW",
    "show_hashrate": true,
    "page_header": {
      "menu": "side",
      "sticky_header": true,
      "bgcolor": "",
      "home_link": "logo",
      "home_link_logo": "/img/nito-header-logo.png",
      "home_link_logo_height": 50,
      "panels": {
        "network_panel": {
          "enabled": true,
          "display_order": 3,
          "nethash": "getnetworkhashps",
          "nethash_units": "T"
        },
        "difficulty_panel": {
          "enabled": true,
          "display_order": 3
        },
        "masternodes_panel": {
          "enabled": false,
          "display_order": 2
        },
        "coin_supply_panel": {
          "enabled": true,
          "display_order": 3
        },
        "price_panel": {
          "enabled": false,
          "display_order": 0
        },
        "usd_price_panel": {
          "enabled": false,
          "display_order": 4
        },
        "market_cap_panel": {
          "enabled": false,
          "display_order": 0
        },
        "usd_market_cap_panel": {
          "enabled": false,
          "display_order": 5
        },
        "logo_panel": {
          "enabled": true,
          "display_order": 3
        },
        "spacer_panel_1": {
          "enabled": false,
          "display_order": 0
        },
        "spacer_panel_2": {
          "enabled": false,
          "display_order": 0
        },
        "spacer_panel_3": {
          "enabled": false,
          "display_order": 0
        }
      },
      "search": {
        "enabled": true,
        "position": "inside-header"
      },
      "page_title_image": {
        "image_path": "/img/nito-page-title-img.png",
        "enable_animation": true
      },
      "network_charts": {
        "nethash_chart": {
          "enabled": true,
          "bgcolor": "#ffffff",
          "line_color": "rgba(54, 162, 235, 1)",
          "fill_color": "rgba(54, 162, 235, 0.2)",
          "crosshair_color": "#000000",
          "round_decimals": 3
        },
        "difficulty_chart": {
          "enabled": true,
          "bgcolor": "#ffffff",
          "pow_line_color": "rgba(255, 99, 132, 1)",
          "pow_fill_color": "rgba(255, 99, 132, 0.2)",
          "pos_line_color": "rgba(255, 161, 0, 1)",
          "pos_fill_color": "rgba(255, 161, 0, 0.2)",
          "crosshair_color": "#000000",
          "round_decimals": 3
        },
        "reload_chart_seconds": 60
      }
    },
    "page_footer": {
      "sticky_footer": false,
      "bgcolor": "",
      "footer_height_desktop": "50px",
      "footer_height_tablet": "70px",
      "footer_height_mobile": "70px",
      "social_links": [
        {
          "enabled": true,
          "tooltip_text": "Github",
          "url": "https://github.com/biigbang0001/Nito-core",
          "fontawesome_class": "fa-brands fa-github",
          "image_path": ""
        },
        {
          "enabled": false,
          "tooltip_text": "Twitter",
          "url": "https://twitter.com/ExorOfficial",
          "fontawesome_class": "fa-brands fa-twitter",
          "image_path": ""
        },
        {
          "enabled": true,
          "tooltip_text": "Discord",
          "url": "https://discord.com/invite/y5rkGHU7Qh",
          "fontawesome_class": "fa-brands fa-discord",
          "image_path": ""
        },
        {
          "enabled": false,
          "tooltip_text": "Telegram",
          "url": "https://t.me/Exorofficial",
          "fontawesome_class": "fa-brands fa-telegram",
          "image_path": ""
        },
        {
          "enabled": true,
          "tooltip_text": "Website",
          "url": "https://nitopool.fr",
          "fontawesome_class": "",
          "image_path": "/img/external.png"
        },
        {
          "enabled": false,
          "tooltip_text": "Coingecko",
          "url": "https://www.coingecko.com/en/coins/nito",
          "fontawesome_class": "",
          "image_path": "/img/coingecko.png"
        }
      ],
      "social_link_percent_height_desktop": 140,
      "social_link_percent_height_tablet": 84,
      "social_link_percent_height_mobile": 80,
      "powered_by_text": "<a class='nav-link poweredby' href='https://github.com/team-exor/eiquidus' target='_blank'>eIquidus v{explorer_version}</a>"
    }
  },
  "index_page": {
    "show_panels": true,
    "show_nethash_chart": true,
    "show_difficulty_chart": true,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "transaction_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10,
      "reload_table_seconds": 60
    }
  },
  "block_page": {
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_description": true
    },
    "genesis_block": "00014f36c648cdbc750f7dd28487a23cd9e0b0f95f5fccc5b5d01367e3f57469",
    "multi_algorithm": {
      "show_algo": false,
      "key_name": "pow_algo"
    }
  },
  "transaction_page": {
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_description": true
    },
    "genesis_tx": "90b863a727d4abf9838e8df221052e418d70baf996e2cea3211e8df4da1bb131",
    "show_op_return": false
  },
  "address_page": {
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_description": true
    },
    "show_sent_received": false,
    "enable_hidden_address_view": false,
    "enable_unknown_address_view": false,
    "history_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 50
    }
  },
  "error_page": {
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_description": true
    }
  },
  "masternodes_page": {
    "enabled": false,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "masternode_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10
    }
  },
  "movement_page": {
    "enabled": true,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "movement_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10,
      "reload_table_seconds": 45,
      "min_amount": 5000,
      "low_warning_flag": 50000,
      "high_warning_flag": 100000
    }
  },
  "network_page": {
    "enabled": true,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "network_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10,
      "reload_table_seconds": 120
    },
    "addnodes_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10,
      "reload_table_seconds": 120
    },
    "onetry_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10,
      "reload_table_seconds": 120
    }
  },
  "richlist_page": {
    "enabled": true,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "show_received_coins": false,
    "richlist_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 100
    }
  },
  "markets_page": {
    "enabled": false,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "market_price": "AVERAGE",
    "show_market_dropdown_menu": true,
    "exchanges": {
      "freiexchange": {
        "enabled": true,
        "display_name": "FreiExchange",
        "website": "https://freiexchange.com/",
        "summary": true,
        "charts": false,
        "trading_pairs": {
          "LTC/BTC": {
            "enabled": true,
            "display_name": "LTC/BTC"
          }
        }
      }
    },
    "coingecko_currency": "BTC",
    "coingecko_api_key": "",
    "default_exchange": {
      "exchange_name": "freiexchange",
      "trading_pair": "LTC/BTC"
    }
  },
  "api_page": {
    "enabled": true,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_description": true
    },
    "show_logo": true,
    "sample_data": {
      "blockindex": 170154,
      "blockhash": "00000000000006d3e687ac5c09967ef25f294ef2481a2960c6966fc141862c56",
      "txhash": "44a1c9791c03f4ad5a70359dde4f03b498fd70e9a60479e3def93b29e9653961",
      "address": "nito1qt8rzug4pawrgec8jklup3lpl00c5klqksqlrz4"
    },
    "public_apis": {
      "rpc": {
        "getdifficulty": {"enabled": true},
        "getconnectioncount": {"enabled": true},
        "getblockcount": {"enabled": true},
        "getblockhash": {"enabled": true},
        "getblock": {"enabled": true},
        "getrawtransaction": {"enabled": true},
        "getnetworkhashps": {"enabled": true},
        "getvotelist": {"enabled": true},
        "getmasternodecount": {"enabled": true}
      },
      "ext": {
        "getmoneysupply": {"enabled": true},
        "getdistribution": {"enabled": true},
        "getaddress": {"enabled": true},
        "getaddresstxs": {"enabled": true, "max_items_per_query": 100},
        "gettx": {"enabled": true},
        "getbalance": {"enabled": true},
        "getlasttxs": {"enabled": true, "max_items_per_query": 100},
        "getcurrentprice": {"enabled": true},
        "getnetworkpeers": {"enabled": true},
        "getbasicstats": {"enabled": true},
        "getsummary": {"enabled": true},
        "getmasternodelist": {"enabled": true},
        "getmasternoderewards": {"enabled": true},
        "getmasternoderewardstotal": {"enabled": true}
      }
    }
  },
  "claim_address_page": {
    "enabled": false,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_description": true
    },
    "show_header_menu": true,
    "enable_bad_word_filter": true,
    "enable_captcha": true
  },
  "orphans_page": {
    "enabled": false,
    "show_panels": false,
    "show_nethash_chart": false,
    "show_difficulty_chart": false,
    "page_header": {
      "show_img": true,
      "show_title": true,
      "show_last_updated": true,
      "show_description": true
    },
    "orphans_table": {
      "page_length_options": [10, 25, 50, 75, 100, 250, 500, 1000],
      "items_per_page": 10
    }
  },
  "sync": {
    "block_parallel_tasks": 1,
    "update_timeout": 10,
    "check_timeout": 250,
    "save_stats_after_sync_blocks": 100,
    "show_sync_msg_when_syncing_more_than_blocks": 1000,
    "supply": "TXOUTSET"
  },
  "captcha": {
    "google_recaptcha3": {
      "enabled": false,
      "pass_score": 0.5,
      "site_key": "",
      "secret_key": ""
    },
    "google_recaptcha2": {
      "enabled": false,
      "captcha_type": "checkbox",
      "site_key": "",
      "secret_key": ""
    },
    "hcaptcha": {
      "enabled": false,
      "site_key": "",
      "secret_key": ""
    }
  },
  "labels": {
    "EXorBurnAddressXXXXXXXXXXXXXW7cDZQ": {
      "enabled": false,
      "label": "Development Budget",
      "type": "success",
      "url": ""
    },
    "EXorBurnAddressXXXXXXXXXXXXXW7cDZQ": {
      "enabled": false,
      "label": "Burn Address",
      "type": "danger",
      "url": ""
    }
  },
  "default_coingecko_ids": [
    {"symbol": "btc", "id": "bitcoin"},
    {"symbol": "eth", "id": "ethereum"},
    {"symbol": "usdt", "id": "tether"},
    {"symbol": "ltc", "id": "litecoin"},
    {"symbol": "exor", "id": "exor"}
  ],
  "api_cmds": {
    "use_rpc": true,
    "rpc_concurrent_tasks": 1,
    "getnetworkhashps": "getnetworkhashps",
    "getmininginfo": "getmininginfo",
    "getdifficulty": "getdifficulty",
    "getconnectioncount": "getconnectioncount",
    "getblockcount": "getblockcount",
    "getblockhash": "getblockhash",
    "getblock": "getblock",
    "getrawtransaction": "getrawtransaction",
    "getinfo": "getinfo",
    "getblockchaininfo": "getblockchaininfo",
    "getpeerinfo": "getpeerinfo",
    "gettxoutsetinfo": "gettxoutsetinfo",
    "getvotelist": "masternodelist votes",
    "getmasternodecount": "getmasternodecount",
    "getmasternodelist": "listmasternodes",
    "verifymessage": "verifymessage"
  },
  "blockchain_specific": {
    "bitcoin": {
      "enabled": false,
      "api_cmds": {
        "getdescriptorinfo": "getdescriptorinfo",
        "deriveaddresses": "deriveaddresses"
      }
    },
    "heavycoin": {
      "enabled": false,
      "reward_page": {
        "enabled": true,
        "show_panels": false,
        "show_nethash_chart": false,
        "show_difficulty_chart": false,
        "page_header": {
          "show_img": true,
          "show_title": true,
          "show_last_updated": true,
          "show_description": true
        }
      },
      "api_cmds": {
        "getmaxmoney": "getmaxmoney",
        "getmaxvote": "getmaxvote",
        "getvote": "getvote",
        "getphase": "getphase",
        "getreward": "getreward",
        "getsupply": "getsupply",
        "getnextrewardestimate": "getnextrewardestimate",
        "getnextrewardwhenstr": "getnextrewardwhenstr"
      },
      "public_apis": {
        "getmaxmoney": {"enabled": true},
        "getmaxvote": {"enabled": true},
        "getvote": {"enabled": true},
        "getphase": {"enabled": true},
        "getreward": {"enabled": true},
        "getsupply": {"enabled": true},
        "getnextrewardestimate": {"enabled": true},
        "getnextrewardwhenstr": {"enabled": true}
      }
    },
    "zksnarks": {
      "enabled": false
    }
  },
  "plugins": {
    "plugin_secret_code": "SJs2=&r^ScLGLgTaNm7#74=s?48zf*4+vm5S",
    "allowed_plugins": [
      {
        "plugin_name": "generic-snapshots",
        "enabled": false
      }
    ]
  }
}
EOF

# Copier settings.json dans le dossier d'eIquidus
cp /root/NitoNode+Explorer/settings.json /root/explorer/

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
npm install -g pm2
cd /root/explorer
npm run start-pm2

# Étape 20 : Synchronisation
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
