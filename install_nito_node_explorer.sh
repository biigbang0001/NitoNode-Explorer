#!/bin/bash

################################################################################
# Universal Blockchain Explorer - Automated Installation Script
# Version 3.0 - Multi-Chain SHA256 Compatible
# Supports any Bitcoin-based blockchain with RPC interface
################################################################################

set -e
trap 'handle_error $? $LINENO' ERR

################################################################################
# GLOBAL VARIABLES
################################################################################
SCRIPT_VERSION="3.0"
LOG_FILE="/var/log/blockchain-explorer-install.log"
BACKUP_DIR="/tmp/explorer-install-backup"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

info() { 
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() { 
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

highlight() {
    echo -e "${MAGENTA}[BLOCKCHAIN]${NC} $1" | tee -a "$LOG_FILE"
}

fatal() {
    error "$1"
    cleanup_on_error
    exit 1
}

handle_error() {
    local exit_code=$1
    local line_number=$2
    error "Error at line $line_number (code: $exit_code)"
    
    echo ""
    warning "An error occurred. Options:"
    echo "1) Retry this step"
    echo "2) Skip and continue"
    echo "3) Clean up and exit"
    read -p "Your choice (1/2/3): " choice
    
    case $choice in
        1) return 0 ;;
        2) warning "Step skipped, continuing..."; return 0 ;;
        *) cleanup_on_error; exit 1 ;;
    esac
}

cleanup_on_error() {
    warning "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    log "Installation interrupted"
}

backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/$(basename $file).bak.$(date +%s)"
    fi
}

confirm() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [ "$default" = "Y" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-Y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-N}
    fi
    
    [[ "$response" =~ ^[YyOo]$ ]]
}

check_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    else
        return 0
    fi
}

################################################################################
# RPC HELPER FUNCTIONS
################################################################################

rpc_call() {
    local method="$1"
    local params="$2"
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        local response=$(curl -s --connect-timeout 10 \
            --user "$RPC_USER:$RPC_PASSWORD" \
            --data-binary "{\"jsonrpc\":\"1.0\",\"id\":\"explorer\",\"method\":\"$method\",\"params\":[$params]}" \
            -H 'content-type: text/plain;' \
            "http://$RPC_HOST:$RPC_PORT/" 2>/dev/null)
        
        if [ -n "$response" ] && echo "$response" | grep -q '"result"'; then
            echo "$response"
            return 0
        fi
        
        retry_count=$((retry_count+1))
        [ $retry_count -lt $max_retries ] && sleep 2
    done
    
    echo ""
    return 1
}

extract_json_value() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\":[^,}]*" | sed 's/.*://;s/"//g;s/ //g'
}

################################################################################
# STEP 1: Prerequisites Check
################################################################################
check_prerequisites() {
    info "Checking prerequisites..."
    
    [ "$EUID" -ne 0 ] && fatal "This script must be run as root"
    [ ! -f /etc/os-release ] && fatal "Unsupported operating system"
    
    . /etc/os-release
    if [[ ! "$ID" =~ ^(ubuntu|debian)$ ]]; then
        warning "Untested system: $ID"
        confirm "Continue anyway?" || exit 1
    fi
    
    local available=$(df / | awk 'NR==2 {print $4}')
    if [ $available -lt 10485760 ]; then
        warning "Low disk space: $(($available/1048576))GB available"
        confirm "Continue with limited space?" || exit 1
    fi
    
    success "Prerequisites checked"
}

################################################################################
# STEP 2: Install Cron
################################################################################
install_cron() {
    info "Checking cron..."
    
    if command -v cron &> /dev/null && systemctl is-active --quiet cron; then
        success "Cron already installed and active"
        return 0
    fi
    
    info "Installing cron..."
    apt update || fatal "Failed to update apt"
    apt install -y cron || fatal "Failed to install cron"
    systemctl enable cron && systemctl start cron
    
    systemctl is-active --quiet cron && success "Cron operational" || fatal "Unable to start cron"
}

################################################################################
# STEP 3: Collect Configuration
################################################################################
collect_configuration() {
    info "=== UNIVERSAL BLOCKCHAIN EXPLORER CONFIGURATION ==="
    echo ""
    
    # Domain
    while true; do
        read -p "Domain name (e.g., explorer.mychain.org): " DOMAIN
        [ -z "$DOMAIN" ] && { error "Domain cannot be empty"; continue; }
        
        if host "$DOMAIN" &>/dev/null; then
            success "DNS resolution OK for $DOMAIN"
            break
        else
            warning "Domain $DOMAIN does not resolve to an IP"
            confirm "Continue anyway?" && break
        fi
    done
    
    # Installation directory
    read -p "Installation directory [/var/blockchain-explorer]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/var/blockchain-explorer}
    INSTALL_DIR=$(echo "$INSTALL_DIR" | sed 's:/*$::')
    
    if [ -d "$INSTALL_DIR/explorer" ]; then
        warning "Directory $INSTALL_DIR/explorer already exists"
        confirm "Remove and start fresh?" && rm -rf "$INSTALL_DIR/explorer" && success "Old directory removed" || fatal "Installation cancelled"
    fi
    
    echo ""
    info "=== BLOCKCHAIN NODE CONNECTION ==="
    
    # RPC Host
    read -p "Node RPC host (IP or DNS) [127.0.0.1]: " RPC_HOST
    RPC_HOST=${RPC_HOST:-127.0.0.1}
    
    # RPC Port
    read -p "Node RPC port [8332]: " RPC_PORT
    RPC_PORT=${RPC_PORT:-8332}
    
    # RPC Credentials
    read -p "RPC username: " RPC_USER
    [ -z "$RPC_USER" ] && fatal "RPC username is required"
    
    read -sp "RPC password: " RPC_PASSWORD
    echo ""
    [ -z "$RPC_PASSWORD" ] && fatal "RPC password is required"
    
    # Test RPC connection early
    info "Testing RPC connection..."
    test_rpc_connection_early || fatal "Cannot continue without working RPC connection"
    
    echo ""
    info "=== PORT CONFIGURATION ==="
    
    # Explorer Port
    EXPLORER_PORT=3003
    while ! check_port $EXPLORER_PORT; do
        warning "Port $EXPLORER_PORT already in use"
        read -p "Alternative port for Explorer [$((EXPLORER_PORT+1))]: " new_port
        EXPLORER_PORT=${new_port:-$((EXPLORER_PORT+1))}
    done
    success "Explorer port: $EXPLORER_PORT"
    
    # MongoDB Port
    MONGODB_PORT=27017
    while ! check_port $MONGODB_PORT; do
        warning "Port $MONGODB_PORT already in use"
        read -p "Alternative port for MongoDB [$((MONGODB_PORT+1))]: " new_port
        MONGODB_PORT=${new_port:-$((MONGODB_PORT+1))}
    done
    success "MongoDB port: $MONGODB_PORT"
    
    EXPLORER_DIR="$INSTALL_DIR/explorer"
    TEMP_DIR="$INSTALL_DIR/temp-install"
    
    echo ""
    info "========== CONFIGURATION SUMMARY =========="
    echo "Domain           : $DOMAIN"
    echo "Installation     : $EXPLORER_DIR"
    echo "Explorer Port    : $EXPLORER_PORT"
    echo "MongoDB Port     : $MONGODB_PORT"
    echo "RPC Node         : $RPC_HOST:$RPC_PORT"
    echo "RPC User         : $RPC_USER"
    echo "Blockchain       : $BLOCKCHAIN_NAME (detected)"
    info "==========================================="
    echo ""
    
    confirm "Confirm this configuration?" Y || fatal "Installation cancelled"
}

################################################################################
# STEP 4: Test RPC and Detect Blockchain
################################################################################
test_rpc_connection_early() {
    info "Connecting to blockchain node..."
    
    local test_response=$(rpc_call "getblockchaininfo" "")
    
    if [ -z "$test_response" ] || ! echo "$test_response" | grep -q '"result"'; then
        error "Failed to connect to RPC node"
        error "Please verify:"
        echo "  - Node is running"
        echo "  - RPC credentials are correct"
        echo "  - RPC port is accessible"
        echo "  - rpcallowip is configured in node config"
        return 1
    fi
    
    success "RPC connection established"
    
    # Detect blockchain info
    BLOCKCHAIN_NAME=$(extract_json_value "$test_response" "chain")
    BLOCKCHAIN_BLOCKS=$(extract_json_value "$test_response" "blocks")
    
    highlight "Connected to: $BLOCKCHAIN_NAME"
    highlight "Current blocks: $BLOCKCHAIN_BLOCKS"
    
    return 0
}

################################################################################
# STEP 5: Fetch Blockchain Information
################################################################################
fetch_blockchain_info() {
    info "Fetching blockchain information via RPC..."
    echo ""
    
    # Get blockchain info
    highlight "Step 1/6: Fetching blockchain info..."
    local blockchain_info=$(rpc_call "getblockchaininfo" "")
    CHAIN=$(extract_json_value "$blockchain_info" "chain")
    BLOCKS=$(extract_json_value "$blockchain_info" "blocks")
    success "Chain: $CHAIN | Blocks: $BLOCKS"
    sleep 1
    
    # Get network info
    highlight "Step 2/6: Fetching network info..."
    local network_info=$(rpc_call "getnetworkinfo" "")
    PROTOCOL_VERSION=$(extract_json_value "$network_info" "protocolversion")
    success "Protocol version: $PROTOCOL_VERSION"
    sleep 1
    
    # Get genesis block hash
    highlight "Step 3/6: Fetching genesis block hash..."
    local genesis_hash_response=$(rpc_call "getblockhash" "0")
    GENESIS_HASH=$(extract_json_value "$genesis_hash_response" "result" | tr -d '"')
    success "Genesis hash: ${GENESIS_HASH:0:16}..."
    sleep 1
    
    # Get genesis block details
    highlight "Step 4/6: Fetching genesis block details..."
    local genesis_block=$(rpc_call "getblock" "\"$GENESIS_HASH\"")
    GENESIS_TX=$(echo "$genesis_block" | grep -o '"tx":\["[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
    success "Genesis TX: ${GENESIS_TX:0:16}..."
    sleep 1
    
    # Get block 1 for reward calculation
    highlight "Step 5/6: Calculating block reward..."
    local block1_hash=$(rpc_call "getblockhash" "1")
    BLOCK1_HASH=$(extract_json_value "$block1_hash" "result" | tr -d '"')
    local block1=$(rpc_call "getblock" "\"$BLOCK1_HASH\", 2")
    
    # Extract coinbase reward from block 1
    BLOCK_REWARD=$(echo "$block1" | grep -o '"vout":\[{"value":[0-9.]*' | head -1 | grep -o '[0-9.]*$')
    [ -z "$BLOCK_REWARD" ] && BLOCK_REWARD="50"
    success "Block reward: $BLOCK_REWARD"
    sleep 1
    
    # Detect if coin name exists in genesis tx
    highlight "Step 6/6: Detecting coin symbol..."
    local gettx=$(rpc_call "getrawtransaction" "\"$GENESIS_TX\", 1")
    
    # Try to extract coin symbol from genesis coinbase
    COIN_SYMBOL=$(echo "$CHAIN" | tr '[:lower:]' '[:upper:]')
    [ "$COIN_SYMBOL" = "MAIN" ] && COIN_SYMBOL="BTC"
    [ "$COIN_SYMBOL" = "TEST" ] && COIN_SYMBOL="TBTC"
    
    success "Coin symbol: $COIN_SYMBOL"
    sleep 1
    
    echo ""
    info "========== DETECTED BLOCKCHAIN INFO =========="
    echo "Chain            : $CHAIN"
    echo "Coin Symbol      : $COIN_SYMBOL"
    echo "Current Blocks   : $BLOCKS"
    echo "Protocol Version : $PROTOCOL_VERSION"
    echo "Genesis Hash     : $GENESIS_HASH"
    echo "Genesis TX       : $GENESIS_TX"
    echo "Block Reward     : $BLOCK_REWARD"
    info "=============================================="
    echo ""
}

################################################################################
# STEP 6: Create Directories
################################################################################
create_directories() {
    info "Creating directories..."
    mkdir -p "$INSTALL_DIR" "$EXPLORER_DIR" "$TEMP_DIR" "$BACKUP_DIR" || fatal "Failed to create directories"
    success "Directories created"
}

################################################################################
# STEP 7: Install System Dependencies
################################################################################
install_system_dependencies() {
    info "Installing system dependencies..."
    apt update || warning "Failed to update apt"
    
    local packages="curl git build-essential ufw net-tools wget snapd jq"
    for package in $packages; do
        dpkg -l | grep -q "^ii  $package " && info "$package already installed" || {
            info "Installing $package..."
            apt install -y $package || warning "Failed to install $package"
        }
    done
    
    success "System dependencies installed"
}

################################################################################
# STEP 8: Install Node.js
################################################################################
install_nodejs() {
    info "Installing Node.js via NVM..."
    
    export NVM_DIR="/root/.nvm"
    
    if [ -d "$NVM_DIR" ]; then
        warning "NVM already installed"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    else
        info "Downloading and installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || fatal "Failed to install NVM"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi
    
    nvm list | grep -q "v16.20.2" && info "Node.js 16.20.2 already installed" || {
        info "Installing Node.js 16.20.2..."
        nvm install 16.20.2 || fatal "Failed to install Node.js"
    }
    
    nvm use 16.20.2
    nvm alias default 16.20.2
    
    node -v | grep -q "v16.20.2" && success "Node.js 16.20.2 installed: $(node -v)" || fatal "Node.js version mismatch"
    
    export NPM_PATH="/root/.nvm/versions/node/v16.20.2/bin/npm"
    export NODE_PATH="/root/.nvm/versions/node/v16.20.2/bin/node"
    export PATH="$PATH:/root/.nvm/versions/node/v16.20.2/bin"
}

################################################################################
# STEP 9: Install Docker
################################################################################
install_docker() {
    info "Checking Docker..."
    
    if command -v docker &> /dev/null && docker ps &> /dev/null; then
        success "Docker already installed and working"
        return 0
    fi
    
    info "Installing Docker..."
    
    dpkg -l | grep -q "ii  containerd.io" && {
        warning "containerd.io conflict detected"
        confirm "Remove containerd.io?" Y && apt remove -y containerd.io && apt autoremove -y
    }
    
    apt install -y docker.io || fatal "Failed to install Docker"
    systemctl start docker && systemctl enable docker
    sleep 2
    
    docker ps &> /dev/null && success "Docker operational" || fatal "Docker not working"
}

################################################################################
# STEP 10: Install MongoDB
################################################################################
install_mongodb() {
    info "Configuring MongoDB..."
    
    local container_name="mongodb-explorer"
    local data_dir="/data/db-explorer"
    local log_dir="/var/log/mongodb-explorer"
    
    # Clean existing containers
    docker ps -a | grep -q "mongo" && {
        warning "Cleaning existing MongoDB containers..."
        docker stop $(docker ps -a | grep mongo | awk '{print $1}') 2>/dev/null || true
        docker rm $(docker ps -a | grep mongo | awk '{print $1}') 2>/dev/null || true
        sleep 2
    }
    
    rm -rf "$data_dir"/*
    mkdir -p "$data_dir" "$log_dir"
    
    info "Downloading MongoDB 7.0.2..."
    docker pull mongo:7.0.2 || fatal "Failed to download MongoDB"
    
    info "Creating MongoDB container..."
    docker run -d --name "$container_name" \
        --restart unless-stopped \
        -p "$MONGODB_PORT":27017 \
        -v "$data_dir":/data/db \
        -v "$log_dir":/var/log/mongodb \
        -e MONGO_INITDB_ROOT_USERNAME=eiquidus \
        -e MONGO_INITDB_ROOT_PASSWORD=Nd^p2d77ceBX!L \
        mongo:7.0.2 || fatal "Failed to create MongoDB container"
    
    info "Waiting for MongoDB..."
    local attempts=30
    while [ $attempts -gt 0 ]; do
        docker exec "$container_name" mongosh --quiet --eval "db.version()" &>/dev/null && break
        attempts=$((attempts-1))
        sleep 1
    done
    
    [ $attempts -eq 0 ] && fatal "MongoDB not responding"
    success "MongoDB operational"
    
    sleep 3
    
    info "Creating database user..."
    docker exec "$container_name" mongosh --quiet --eval "
        conn = new Mongo('mongodb://eiquidus:Nd^p2d77ceBX!L@localhost:27017/admin');
        db = conn.getDB('explorerdb');
        try {
            db.createUser({
                user: 'eiquidus',
                pwd: 'Nd^p2d77ceBX!L',
                roles: [{ role: 'readWrite', db: 'explorerdb' }]
            });
        } catch(e) { if (e.code !== 51003) throw e; }
    " &>/dev/null
    
    success "MongoDB configured"
}

################################################################################
# STEP 11: Install Nginx
################################################################################
install_nginx() {
    info "Installing Nginx..."
    command -v nginx &> /dev/null || apt install -y nginx || fatal "Failed to install Nginx"
    systemctl start nginx && systemctl enable nginx
    systemctl is-active --quiet nginx && success "Nginx operational" || fatal "Nginx not starting"
}

################################################################################
# STEP 12: Install eIquidus
################################################################################
install_eiquidus() {
    info "Installing eIquidus..."
    cd "$INSTALL_DIR"
    
    if [ -d "$EXPLORER_DIR/.git" ]; then
        warning "eIquidus already cloned"
        cd "$EXPLORER_DIR"
        git pull || warning "Failed to update"
    else
        info "Cloning eIquidus..."
        git clone https://github.com/team-exor/eiquidus "$EXPLORER_DIR" || fatal "Failed to clone"
        cd "$EXPLORER_DIR"
    fi
    
    info "Installing npm dependencies..."
    "$NPM_PATH" install --only=prod || fatal "Failed to install npm dependencies"
    success "eIquidus installed"
}

################################################################################
# STEP 13: Generate settings.json from Blockchain Data
################################################################################
generate_settings() {
    info "Generating settings.json from blockchain data..."
    
    cat > "$EXPLORER_DIR/settings.json" <<EOF
{
  "title": "$COIN_SYMBOL Explorer",
  "address": "https://$DOMAIN",
  "coin": "$COIN_SYMBOL",
  "symbol": "$COIN_SYMBOL",
  "logo": "/img/logo.png",
  "favicon": "favicon-32.png",
  "theme": "Exor",
  "port": $EXPLORER_PORT,
  "dbsettings": {
    "user": "eiquidus",
    "password": "Nd^p2d77ceBX!L",
    "database": "explorerdb",
    "address": "localhost",
    "port": $MONGODB_PORT
  },
  "update_timeout": 10,
  "check_timeout": 250,
  "wallet": {
    "host": "$RPC_HOST",
    "port": $RPC_PORT,
    "username": "$RPC_USER",
    "password": "$RPC_PASSWORD"
  },
  "genesis_tx": "$GENESIS_TX",
  "genesis_block": "$GENESIS_HASH",
  "use_rpc": true,
  "heavy": false,
  "lock_during_index": false,
  "txcount": 100,
  "txcount_per_page": 50,
  "show_sent_received": true,
  "supply": "COINBASE",
  "nethash": "netmhashps",
  "nethash_units": "MH",
  "labels": {
    "api": "API",
    "coin": "Coin",
    "markets": "Markets",
    "richlist": "Rich List",
    "network": "Network",
    "movement": "Movement",
    "block": "Block",
    "blocklist": "Block List",
    "peers": "Peers",
    "transactions": "Transactions",
    "address": "Address",
    "search": "Search"
  },
  "locale": "en",
  "display": {
    "api": true,
    "markets": true,
    "richlist": true,
    "twitter": false,
    "facebook": false,
    "googleplus": false,
    "bitcointalk": false,
    "website": false,
    "slack": false,
    "github": false,
    "discord": false,
    "instagram": false,
    "reddit": false,
    "telegram": false,
    "youtube": false,
    "search": true,
    "movement": true,
    "network": true,
    "masternodes": false,
    "peers": true,
    "reward": $BLOCK_REWARD,
    "difficulty": "POW"
  },
  "index": {
    "show_hashrate": true,
    "difficulty": "POW",
    "show_last_updated": true
  },
  "api_page": {
    "enabled": true,
    "blockindex": 1,
    "blockhash": "$GENESIS_HASH",
    "txhash": "$GENESIS_TX",
    "address": ""
  },
  "markets_page": {
    "enabled": false
  },
  "richlist_page": {
    "enabled": true,
    "amount": 100
  },
  "movement_page": {
    "enabled": true,
    "low_flag": 100,
    "high_flag": 1000
  },
  "network_page": {
    "enabled": true
  },
  "masternodes_page": {
    "enabled": false
  },
  "shared_pages": {
    "page_header": {
      "network_charts": {
        "enabled": false
      }
    }
  },
  "webserver": {
    "port": $EXPLORER_PORT,
    "tls": {
      "enabled": false,
      "port": 443,
      "always_redirect": false,
      "cert_file": "",
      "chain_file": "",
      "key_file": ""
    }
  },
  "confirmations": 6,
  "sync": {
    "update_stats_on_sync": true
  },
  "blockchain_specific": {
    "bitcoin": {
      "genesis_tx": "$GENESIS_TX",
      "genesis_block": "$GENESIS_HASH",
      "block_time_sec": 600
    }
  },
  "donation_address": ""
}
EOF
    
    success "settings.json generated with blockchain data"
}

################################################################################
# STEP 14: Setup Logo (Placeholder)
################################################################################
setup_logo() {
    info "Setting up default logo..."
    mkdir -p "$EXPLORER_DIR/public/img"
    
    # Create a simple placeholder logo
    cat > "$EXPLORER_DIR/public/img/logo.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
EOF
    
    base64 -d "$EXPLORER_DIR/public/img/logo.png" > /tmp/logo.png 2>/dev/null || true
    
    info "To customize the logo, replace: $EXPLORER_DIR/public/img/logo.png"
}

################################################################################
# STEP 15: Configure Firewall
################################################################################
configure_firewall() {
    info "Configuring firewall..."
    ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
    ufw allow 443/tcp comment "HTTPS" 2>/dev/null || true
    ufw allow 22/tcp comment "SSH" 2>/dev/null || true
    ufw status | grep -q "Status: active" || ufw --force enable
    success "Firewall configured"
}

################################################################################
# STEP 16: Install SSL Certificate
################################################################################
install_ssl() {
    info "Installing Certbot..."
    
    command -v snap &> /dev/null || {
        apt install -y snapd
        systemctl start snapd
        sleep 2
    }
    
    snap install core 2>/dev/null || snap refresh core
    snap list | grep -q certbot || {
        snap install --classic certbot
        ln -sf /snap/bin/certbot /usr/bin/certbot
    }
    
    info "Configuring Nginx for Certbot..."
    cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF
    
    nginx -t && systemctl reload nginx
    
    info "Generating SSL certificate..."
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        warning "Certificate already exists"
        confirm "Renew?" N && certbot --nginx -d "$DOMAIN" --force-renewal --non-interactive --agree-tos --email "admin@$DOMAIN"
    else
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || warning "SSL generation failed (non-critical)"
    fi
    
    success "SSL configured"
}

################################################################################
# STEP 17: Final Nginx Configuration
################################################################################
configure_nginx_final() {
    info "Final Nginx configuration..."
    
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/explorer
    
    cat > /etc/nginx/sites-available/explorer <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://localhost:$EXPLORER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF
    
    ln -sf /etc/nginx/sites-available/explorer /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    success "Nginx configured"
}

################################################################################
# STEP 18: Install PM2 and Start Explorer
################################################################################
install_pm2() {
    info "Installing PM2..."
    command -v pm2 &> /dev/null || "$NPM_PATH" install -g pm2
    
    export PATH="$PATH:/root/.nvm/versions/node/v16.20.2/bin"
    echo 'export PATH="$PATH:/root/.nvm/versions/node/v16.20.2/bin"' >> ~/.bashrc
    
    cd "$EXPLORER_DIR"
    pm2 delete all 2>/dev/null || true
    
    info "Starting explorer..."
    "$NPM_PATH" run start-pm2 || {
        error "Failed to start explorer"
        cat "$EXPLORER_DIR/tmp/explorer.log" 2>/dev/null
        fatal "Explorer start failed"
    }
    
    success "Explorer started"
    
    pm2 startup systemd -u root --hp /root
    pm2 save
    
    systemctl daemon-reload
    systemctl enable pm2-root
    systemctl start pm2-root
    
    sleep 2
    systemctl is-active --quiet pm2-root && success "PM2 service active" || warning "PM2 service issue"
}

################################################################################
# STEP 19: Setup Synchronization
################################################################################
setup_sync() {
    info "Configuring synchronization..."
    cd "$EXPLORER_DIR"
    
    cat > "$EXPLORER_DIR/sync-explorer.sh" <<EOF
#!/bin/bash
export NVM_DIR="/root/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
cd $EXPLORER_DIR
npm run sync-blocks >> $EXPLORER_DIR/sync-cron.log 2>&1
EOF
    
    chmod +x "$EXPLORER_DIR/sync-explorer.sh"
    nohup "$EXPLORER_DIR/sync-explorer.sh" > "$EXPLORER_DIR/sync-initial.log" 2>&1 &
    
    (crontab -l 2>/dev/null | grep -v "sync-explorer.sh"; echo "*/1 * * * * /bin/bash $EXPLORER_DIR/sync-explorer.sh") | crontab -
    
    success "Synchronization configured"
}

################################################################################
# STEP 20: Final Validation
################################################################################
final_validation() {
    info "Running final validation..."
    
    systemctl is-active --quiet pm2-root && success "✅ PM2 service: active" || error "❌ PM2 service: inactive"
    docker ps | grep -q mongodb-explorer && success "✅ MongoDB: running" || error "❌ MongoDB: stopped"
    systemctl is-active --quiet nginx && success "✅ Nginx: active" || error "❌ Nginx: inactive"
    pm2 list | grep -q "online" && success "✅ Explorer: running" || error "❌ Explorer: stopped"
    crontab -l | grep -q "sync-explorer" && success "✅ Cron: configured" || error "❌ Cron: missing"
}

################################################################################
# STEP 21: Show Summary
################################################################################
show_summary() {
    echo ""
    echo "=========================================="
    success "🎉 INSTALLATION COMPLETE!"
    echo "=========================================="
    echo ""
    highlight "BLOCKCHAIN INFORMATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Coin             : $COIN_SYMBOL"
    echo "Chain            : $CHAIN"
    echo "Genesis Block    : ${GENESIS_HASH:0:32}..."
    echo "Genesis TX       : ${GENESIS_TX:0:32}..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "EXPLORER ACCESS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "URL              : https://$DOMAIN"
    echo "Local            : http://localhost:$EXPLORER_PORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "USEFUL COMMANDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  pm2 list                    # Check status"
    echo "  pm2 logs                    # View logs"
    echo "  pm2 restart all             # Restart explorer"
    echo "  tail -f $EXPLORER_DIR/sync-initial.log"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warning "⏳ Initial sync in progress (may take 10-30 min)"
    echo ""
}

################################################################################
# MAIN
################################################################################
main() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  Universal Blockchain Explorer v$SCRIPT_VERSION   ║"
    echo "║  Multi-Chain SHA256 Compatible            ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    install_cron
    collect_configuration
    fetch_blockchain_info
    create_directories
    install_system_dependencies
    install_nodejs
    install_docker
    install_mongodb
    install_nginx
    install_eiquidus
    generate_settings
    setup_logo
    configure_firewall
    install_ssl
    configure_nginx_final
    install_pm2
    setup_sync
    final_validation
    show_summary
}

main "$@"
