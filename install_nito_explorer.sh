#!/bin/bash

################################################################################
# NITO Blockchain Explorer - Installation Script
# Version 4.0 - Multi-Explorer Compatible
# Designed to coexist with other explorers (FixedCoin, etc.)
################################################################################

set -e
trap 'handle_error $? $LINENO' ERR

################################################################################
# NITO-SPECIFIC CONFIGURATION
################################################################################
COIN_NAME="NITO"
COIN_SYMBOL="NITO"
INSTALL_NAME="nito"
DEFAULT_RPC_PORT=8825
DEFAULT_EXPLORER_PORT=3001
GENESIS_BLOCK="00000000103d1acbedc9bb8ff2af8cb98a751965e784b4e1f978f3d5544c6c3c"
GENESIS_TX="90b863a727d4abf9838e8df221052e418d70baf996e2cea3211e8df4da1bb131"

# Unique identifiers for NITO (to avoid conflicts)
MONGODB_DATABASE="explorerdb-nito"
MONGODB_USER="eiquidus-nito"
MONGODB_PASSWORD="Nd^p2d77ceBX!L"
PM2_APP_NAME="explorer-nito"

################################################################################
# GLOBAL VARIABLES
################################################################################
SCRIPT_VERSION="4.0-NITO"
LOG_FILE="/var/log/nito-explorer-install.log"
BACKUP_DIR="/backup/explorer-nito-$(date +%Y%m%d-%H%M%S)"

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
    echo -e "${MAGENTA}[NITO]${NC} $1" | tee -a "$LOG_FILE"
}

fatal() {
    error "$1"
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
    echo "3) Exit"
    read -p "Your choice (1/2/3): " choice
    
    case $choice in
        1) return 0 ;;
        2) warning "Step skipped, continuing..."; return 0 ;;
        *) exit 1 ;;
    esac
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

safe_backup() {
    local source="$1"
    local name="$2"
    
    if [ -e "$source" ]; then
        mkdir -p "$BACKUP_DIR"
        info "Backing up $name to $BACKUP_DIR"
        
        if [ -d "$source" ]; then
            cp -r "$source" "$BACKUP_DIR/$name" || warning "Failed to backup $name"
        else
            cp "$source" "$BACKUP_DIR/$name" || warning "Failed to backup $name"
        fi
        
        success "Backup created: $BACKUP_DIR/$name"
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
    echo ""
    highlight "=== NITO EXPLORER CONFIGURATION ==="
    echo ""
    
    # Domain
    while true; do
        read -p "Domain name (e.g., nito-explorer.nitopool.fr): " DOMAIN
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
    INSTALL_DIR="/var/explorer-$INSTALL_NAME"
    EXPLORER_DIR="$INSTALL_DIR/explorer"
    
    info "Installation directory: $INSTALL_DIR"
    
    # Check if installation already exists
    if [ -d "$EXPLORER_DIR" ]; then
        warning "Installation already exists: $EXPLORER_DIR"
        echo ""
        echo "Options:"
        echo "1) Keep existing and exit (SAFE)"
        echo "2) Backup existing and start fresh"
        read -p "Your choice (1/2): " install_choice
        
        case $install_choice in
            1)
                info "Installation cancelled - existing data preserved"
                exit 0
                ;;
            2)
                safe_backup "$INSTALL_DIR" "explorer-$INSTALL_NAME-old"
                confirm "Delete old installation after backup?" || {
                    info "Keeping old installation"
                    exit 0
                }
                rm -rf "$EXPLORER_DIR"
                success "Old installation removed (backup saved)"
                ;;
            *)
                fatal "Invalid choice"
                ;;
        esac
    fi
    
    echo ""
    highlight "=== NITO NODE CONNECTION ==="
    
    # RPC Host
    read -p "Node RPC host (IP or DNS) [127.0.0.1]: " RPC_HOST
    RPC_HOST=${RPC_HOST:-127.0.0.1}
    
    # RPC Port
    read -p "Node RPC port [$DEFAULT_RPC_PORT]: " RPC_PORT
    RPC_PORT=${RPC_PORT:-$DEFAULT_RPC_PORT}
    
    # RPC Credentials
    read -p "RPC username [user]: " RPC_USER
    RPC_USER=${RPC_USER:-user}
    
    read -sp "RPC password [pass]: " RPC_PASSWORD
    echo ""
    RPC_PASSWORD=${RPC_PASSWORD:-pass}
    
    # Test RPC connection
    info "Testing RPC connection..."
    test_rpc_connection || fatal "Cannot continue without working RPC connection"
    
    echo ""
    highlight "=== PORT CONFIGURATION ==="
    
    # Explorer Port - find available
    EXPLORER_PORT=$DEFAULT_EXPLORER_PORT
    while ! check_port $EXPLORER_PORT; do
        warning "Port $EXPLORER_PORT already in use"
        EXPLORER_PORT=$((EXPLORER_PORT+1))
    done
    success "Explorer port: $EXPLORER_PORT"
    
    # Check for existing MongoDB container
    if docker ps | grep -q "mongodb-explorer"; then
        MONGODB_CONTAINER="mongodb-explorer"
        MONGODB_PORT=27017
        USE_EXISTING_MONGODB=true
        success "Using existing MongoDB container: $MONGODB_CONTAINER"
    else
        MONGODB_CONTAINER="mongodb-$INSTALL_NAME"
        MONGODB_PORT=27017
        while ! check_port $MONGODB_PORT; do
            warning "Port $MONGODB_PORT already in use"
            MONGODB_PORT=$((MONGODB_PORT+1))
        done
        USE_EXISTING_MONGODB=false
        info "Will create new MongoDB container: $MONGODB_CONTAINER"
    fi
    
    MONGODB_DATA_DIR="/data/db-$INSTALL_NAME"
    MONGODB_LOG_DIR="/var/log/mongodb-$INSTALL_NAME"
    
    echo ""
    highlight "========== CONFIGURATION SUMMARY =========="
    echo "Coin             : $COIN_NAME ($COIN_SYMBOL)"
    echo "Domain           : $DOMAIN"
    echo "Installation     : $EXPLORER_DIR"
    echo "Explorer Port    : $EXPLORER_PORT"
    echo "MongoDB Container: $MONGODB_CONTAINER"
    echo "MongoDB Database : $MONGODB_DATABASE"
    echo "MongoDB User     : $MONGODB_USER"
    echo "PM2 App Name     : $PM2_APP_NAME"
    echo "RPC Node         : $RPC_HOST:$RPC_PORT"
    echo "RPC User         : $RPC_USER"
    highlight "==========================================="
    echo ""
    
    confirm "Confirm this configuration?" Y || fatal "Installation cancelled"
}

################################################################################
# STEP 4: Test RPC Connection
################################################################################
test_rpc_connection() {
    info "Connecting to NITO node..."
    
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
    BLOCKCHAIN_BLOCKS=$(extract_json_value "$test_response" "blocks")
    highlight "Connected to NITO - Current blocks: $BLOCKCHAIN_BLOCKS"
    
    return 0
}

################################################################################
# STEP 5: Create Directories
################################################################################
create_directories() {
    info "Creating directories..."
    mkdir -p "$INSTALL_DIR" "$EXPLORER_DIR" "$BACKUP_DIR" || fatal "Failed to create directories"
    
    if [ "$USE_EXISTING_MONGODB" = false ]; then
        mkdir -p "$MONGODB_DATA_DIR" "$MONGODB_LOG_DIR" || fatal "Failed to create MongoDB directories"
    fi
    
    success "Directories created"
}

################################################################################
# STEP 6: Install System Dependencies
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
# STEP 7: Install Node.js
################################################################################
install_nodejs() {
    info "Installing Node.js via NVM..."
    
    export NVM_DIR="/root/.nvm"
    
    if [ -d "$NVM_DIR" ]; then
        info "NVM already installed"
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
# STEP 8: Install Docker
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
# STEP 9: Configure MongoDB - Multi-Explorer Compatible
################################################################################
configure_mongodb() {
    info "Configuring MongoDB for NITO..."
    
    if [ "$USE_EXISTING_MONGODB" = true ]; then
        info "Using existing MongoDB container: $MONGODB_CONTAINER"
        
        # Create NITO-specific database and user
        info "Creating NITO database and user..."
        docker exec "$MONGODB_CONTAINER" mongosh --quiet --eval "
            conn = new Mongo('mongodb://eiquidus:Nd^p2d77ceBX!L@localhost:27017/admin');
            db = conn.getDB('$MONGODB_DATABASE');
            try {
                db.createUser({
                    user: '$MONGODB_USER',
                    pwd: '$MONGODB_PASSWORD',
                    roles: [{ role: 'readWrite', db: '$MONGODB_DATABASE' }]
                });
                print('User $MONGODB_USER created for database $MONGODB_DATABASE');
            } catch(e) { 
                if (e.code !== 51003) throw e;
                print('User already exists');
            }
        " || warning "Database user creation had issues (may already exist)"
        
        success "MongoDB configured for NITO"
        return 0
    fi
    
    # Create new MongoDB container if needed
    if docker ps -a | grep -q "$MONGODB_CONTAINER"; then
        warning "Container $MONGODB_CONTAINER already exists"
        if ! docker ps | grep -q "$MONGODB_CONTAINER"; then
            info "Starting existing container..."
            docker start "$MONGODB_CONTAINER"
        fi
    else
        mkdir -p "$MONGODB_DATA_DIR" "$MONGODB_LOG_DIR"
        
        info "Downloading MongoDB 7.0.2..."
        docker pull mongo:7.0.2 || fatal "Failed to download MongoDB"
        
        info "Creating MongoDB container: $MONGODB_CONTAINER..."
        docker run -d --name "$MONGODB_CONTAINER" \
            --restart unless-stopped \
            -p "$MONGODB_PORT":27017 \
            -v "$MONGODB_DATA_DIR":/data/db \
            -v "$MONGODB_LOG_DIR":/var/log/mongodb \
            -e MONGO_INITDB_ROOT_USERNAME=eiquidus \
            -e MONGO_INITDB_ROOT_PASSWORD=Nd^p2d77ceBX!L \
            mongo:7.0.2 || fatal "Failed to create MongoDB container"
        
        info "Waiting for MongoDB..."
        local attempts=30
        while [ $attempts -gt 0 ]; do
            docker exec "$MONGODB_CONTAINER" mongosh --quiet --eval "db.version()" &>/dev/null && break
            attempts=$((attempts-1))
            sleep 1
        done
        
        [ $attempts -eq 0 ] && fatal "MongoDB not responding"
    fi
    
    sleep 3
    
    info "Creating NITO database user..."
    docker exec "$MONGODB_CONTAINER" mongosh --quiet --eval "
        conn = new Mongo('mongodb://eiquidus:Nd^p2d77ceBX!L@localhost:27017/admin');
        db = conn.getDB('$MONGODB_DATABASE');
        try {
            db.createUser({
                user: '$MONGODB_USER',
                pwd: '$MONGODB_PASSWORD',
                roles: [{ role: 'readWrite', db: '$MONGODB_DATABASE' }]
            });
        } catch(e) { if (e.code !== 51003) throw e; }
    " &>/dev/null
    
    success "MongoDB configured"
}

################################################################################
# STEP 10: Install Nginx
################################################################################
install_nginx() {
    info "Installing Nginx..."
    command -v nginx &> /dev/null || apt install -y nginx || fatal "Failed to install Nginx"
    systemctl start nginx && systemctl enable nginx
    systemctl is-active --quiet nginx && success "Nginx operational" || fatal "Nginx not starting"
}

################################################################################
# STEP 11: Install eIquidus
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
# STEP 12: Generate settings.json for NITO
################################################################################
generate_settings() {
    info "Generating settings.json for NITO..."
    
    [ -f "$EXPLORER_DIR/settings.json" ] && safe_backup "$EXPLORER_DIR/settings.json" "settings-old.json"
    
    cat > "$EXPLORER_DIR/settings.json" <<'SETTINGS_EOF'
{
  "locale": "locale/en.json",

  "dbsettings": {
    "user": "MONGODB_USER_PLACEHOLDER",
    "password": "MONGODB_PASSWORD_PLACEHOLDER",
    "database": "MONGODB_DATABASE_PLACEHOLDER",
    "address": "localhost",
    "port": MONGODB_PORT_PLACEHOLDER
  },

  "wallet": {
    "host": "RPC_HOST_PLACEHOLDER",
    "port": RPC_PORT_PLACEHOLDER,
    "username": "RPC_USER_PLACEHOLDER",
    "password": "RPC_PASSWORD_PLACEHOLDER"
  },

  "webserver": {
    "port": EXPLORER_PORT_PLACEHOLDER,
    "tls": {
      "enabled": false,
      "port": 443,
      "always_redirect": true,
      "cert_file": "/etc/letsencrypt/live/DOMAIN_PLACEHOLDER/cert.pem",
      "chain_file": "/etc/letsencrypt/live/DOMAIN_PLACEHOLDER/chain.pem",
      "key_file": "/etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem"
    },
    "cors": {
      "enabled": true,
      "corsorigin": "*"
    }
  },

  "coin": {
    "name": "NITO",
    "symbol": "NITO"
  },

  "network_history": {
    "enabled": true,
    "max_saved_records": 10080
  },

  "shared_pages": {
    "theme": "Cyborg",
    "page_title": "NITO Explorer",
    "favicons": {
      "favicon32": "favicon-32.png",
      "favicon128": "favicon-128.png",
      "favicon180": "favicon-180.png",
      "favicon192": "favicon-192.png"
    },
    "logo": "/img/logo.png",
    "date_time": {
      "display_format": "LLL dd, yyyy HH:mm:ss ZZZZ",
      "timezone": "utc",
      "enable_alt_timezone_tooltips": false
    },
    "table_header_bgcolor": "",
    "confirmations": 6,
    "difficulty": "POW",
    "show_hashrate": true,
    "page_header": {
      "menu": "side",
      "sticky_header": true,
      "bgcolor": "",
      "home_link": "logo",
      "home_link_logo": "/img/header-logo.png",
      "home_link_logo_height": 50,
      "panels": {
        "network_panel": {
          "enabled": true,
          "display_order": 1,
          "nethash": "getnetworkhashps",
          "nethash_units": "G"
        },
        "difficulty_panel": {
          "enabled": true,
          "display_order": 2
        },
        "masternodes_panel": {
          "enabled": false,
          "display_order": 0
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
          "display_order": 0
        },
        "market_cap_panel": {
          "enabled": false,
          "display_order": 0
        },
        "usd_market_cap_panel": {
          "enabled": false,
          "display_order": 0
        },
        "logo_panel": {
          "enabled": true,
          "display_order": 4
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
        "image_path": "/img/page-title-img.png",
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
          "url": "https://github.com/NitoNetwork/Nito-core",
          "fontawesome_class": "fa-brands fa-github",
          "image_path": ""
        },
        {
          "enabled": true,
          "tooltip_text": "Twitter",
          "url": "https://x.com/NitoCoin",
          "fontawesome_class": "fa-brands fa-twitter",
          "image_path": ""
        },
        {
          "enabled": true,
          "tooltip_text": "Discord",
          "url": "https://discord.gg/nito",
          "fontawesome_class": "fa-brands fa-discord",
          "image_path": ""
        },
        {
          "enabled": true,
          "tooltip_text": "Website",
          "url": "https://nito.network/",
          "fontawesome_class": "",
          "image_path": "/img/external.png"
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
      "page_length_options": [ 10, 25, 50, 75, 100 ],
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
    "genesis_block": "00000000103d1acbedc9bb8ff2af8cb98a751965e784b4e1f978f3d5544c6c3c",
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
    "show_sent_received": true,
    "enable_hidden_address_view": false,
    "enable_unknown_address_view": false,
    "history_table": {
      "page_length_options": [ 10, 25, 50, 75, 100 ],
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
      "page_length_options": [ 10, 25, 50, 75, 100 ],
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
      "page_length_options": [ 10, 25, 50, 75, 100 ],
      "items_per_page": 10,
      "reload_table_seconds": 45,
      "min_amount": 100,
      "low_warning_flag": 1000,
      "high_warning_flag": 5000
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
    "connections_table": {
      "page_length_options": [ 10, 25, 50, 75, 100 ],
      "items_per_page": 10,
      "port_filter": -1,
      "hide_protocols": [ ]
    },
    "addnodes_table": {
      "page_length_options": [ 10, 25, 50, 75, 100 ],
      "items_per_page": 10,
      "port_filter": -1,
      "hide_protocols": [ ]
    },
    "onetry_table": {
      "page_length_options": [ 10, 25, 50, 75, 100 ],
      "items_per_page": 10,
      "port_filter": -1,
      "hide_protocols": [ ]
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
    "show_current_balance": true,
    "show_received_coins": true,
    "wealth_distribution": {
      "show_distribution_table": true,
      "show_distribution_chart": true,
      "colors": [ "#e73cbd", "#00bc8c", "#3498db", "#e3ce3e", "#adb5bd", "#e74c3c" ]
    },
    "burned_coins": {
      "addresses": [ ],
      "include_burned_coins_in_distribution": false
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
      "show_exchange_url": true,
      "show_description": true
    },
    "show_market_dropdown_menu": false,
    "show_market_select": false,
    "exchanges": {
      "altmarkets": { "enabled": false, "trading_pairs": [ ] },
      "dextrade": { "enabled": false, "trading_pairs": [ ] },
      "freiexchange": { "enabled": false, "trading_pairs": [ ] },
      "nonkyc": { "enabled": false, "trading_pairs": [ ] },
      "poloniex": { "enabled": false, "trading_pairs": [ ] },
      "xeggex": { "enabled": false, "trading_pairs": [ ] },
      "yobit": { "enabled": false, "trading_pairs": [ ] }
    },
    "market_price": "AVERAGE",
    "coingecko_currency": "BTC",
    "coingecko_api_key": "",
    "default_exchange": {
      "exchange_name": "",
      "trading_pair": ""
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
      "blockindex": 10,
      "blockhash": "00000000103d1acbedc9bb8ff2af8cb98a751965e784b4e1f978f3d5544c6c3c",
      "txhash": "90b863a727d4abf9838e8df221052e418d70baf996e2cea3211e8df4da1bb131",
      "address": ""
    },
    "public_apis": {
      "rpc": {
        "getdifficulty": { "enabled": true },
        "getconnectioncount": { "enabled": true },
        "getblockcount": { "enabled": true },
        "getblockhash": { "enabled": true },
        "getblock": { "enabled": true },
        "getrawtransaction": { "enabled": true },
        "getnetworkhashps": { "enabled": true },
        "getvotelist": { "enabled": false },
        "getmasternodecount": { "enabled": false }
      },
      "ext": {
        "getmoneysupply": { "enabled": true },
        "getdistribution": { "enabled": true },
        "getaddress": { "enabled": true },
        "getaddresstxs": { "enabled": true, "max_items_per_query": 100 },
        "gettx": { "enabled": true },
        "getbalance": { "enabled": true },
        "getlasttxs": { "enabled": true, "max_items_per_query": 100 },
        "getcurrentprice": { "enabled": false },
        "getnetworkpeers": { "enabled": true },
        "getbasicstats": { "enabled": true },
        "getsummary": { "enabled": true },
        "getmasternodelist": { "enabled": false },
        "getmasternoderewards": { "enabled": false },
        "getmasternoderewardstotal": { "enabled": false }
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
    "show_header_menu": false,
    "enable_bad_word_filter": true,
    "enable_captcha": false
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
      "page_length_options": [ 10, 25, 50, 75, 100 ],
      "items_per_page": 10
    }
  },

  "sync": {
    "block_parallel_tasks": 1,
    "update_timeout": 10,
    "check_timeout": 250,
    "save_stats_after_sync_blocks": 100,
    "show_sync_msg_when_syncing_more_than_blocks": 1000,
    "supply": "COINBASE"
  },

  "captcha": {
    "google_recaptcha3": { "enabled": false, "pass_score": 0.5, "site_key": "", "secret_key": "" },
    "google_recaptcha2": { "enabled": false, "captcha_type": "checkbox", "site_key": "", "secret_key": "" },
    "hcaptcha": { "enabled": false, "site_key": "", "secret_key": "" }
  },

  "labels": {},

  "default_coingecko_ids": [
    { "symbol": "btc", "id": "bitcoin" },
    { "symbol": "eth", "id": "ethereum" },
    { "symbol": "usdt", "id": "tether" },
    { "symbol": "nito", "id": "nitocoin" }
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
    "getvotelist": "",
    "getmasternodecount": "",
    "getmasternodelist": "",
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
    "heavycoin": { "enabled": false },
    "zksnarks": { "enabled": false }
  },

  "plugins": {
    "plugin_secret_code": "NITO2025SecureKey!@#$",
    "allowed_plugins": []
  }
}
SETTINGS_EOF

    # Replace placeholders
    sed -i "s/MONGODB_USER_PLACEHOLDER/$MONGODB_USER/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/MONGODB_PASSWORD_PLACEHOLDER/$MONGODB_PASSWORD/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/MONGODB_DATABASE_PLACEHOLDER/$MONGODB_DATABASE/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/MONGODB_PORT_PLACEHOLDER/$MONGODB_PORT/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/RPC_HOST_PLACEHOLDER/$RPC_HOST/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/RPC_PORT_PLACEHOLDER/$RPC_PORT/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/RPC_USER_PLACEHOLDER/$RPC_USER/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/RPC_PASSWORD_PLACEHOLDER/$RPC_PASSWORD/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/EXPLORER_PORT_PLACEHOLDER/$EXPLORER_PORT/g" "$EXPLORER_DIR/settings.json"
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$EXPLORER_DIR/settings.json"
    
    success "settings.json generated for NITO"
}

################################################################################
# STEP 13: Setup Logo
################################################################################
setup_logo() {
    info "Setting up default logo..."
    mkdir -p "$EXPLORER_DIR/public/img"
    info "To customize the logo, replace: $EXPLORER_DIR/public/img/logo.png"
}

################################################################################
# STEP 14: Configure Firewall
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
# STEP 15: Install SSL Certificate
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
    
    # Check if certificate already exists
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        success "SSL certificate already exists for $DOMAIN"
        return 0
    fi
    
    # Use unique temporary config
    info "Configuring Nginx for Certbot..."
    cat > "/etc/nginx/sites-available/certbot-$INSTALL_NAME" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF
    
    ln -sf "/etc/nginx/sites-available/certbot-$INSTALL_NAME" "/etc/nginx/sites-enabled/certbot-$INSTALL_NAME"
    nginx -t && systemctl reload nginx
    
    info "Generating SSL certificate..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || warning "SSL generation failed (non-critical)"
    
    # Remove temporary config
    rm -f "/etc/nginx/sites-enabled/certbot-$INSTALL_NAME"
    
    success "SSL configured"
}

################################################################################
# STEP 16: Final Nginx Configuration
################################################################################
configure_nginx_final() {
    info "Final Nginx configuration..."
    
    local nginx_config="/etc/nginx/sites-available/$INSTALL_NAME-explorer"
    
    [ -f "$nginx_config" ] && safe_backup "$nginx_config" "nginx-$INSTALL_NAME-old"
    
    cat > "$nginx_config" <<EOF
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
    
    ln -sf "$nginx_config" "/etc/nginx/sites-enabled/$INSTALL_NAME-explorer"
    nginx -t && systemctl reload nginx
    success "Nginx configured"
}

################################################################################
# STEP 17: Install PM2 and Start Explorer - Unique Name
################################################################################
install_pm2() {
    info "Installing PM2..."
    command -v pm2 &> /dev/null || "$NPM_PATH" install -g pm2
    
    export PATH="$PATH:/root/.nvm/versions/node/v16.20.2/bin"
    
    cd "$EXPLORER_DIR"
    
    # Check for existing PM2 process with same name
    if pm2 list | grep -q "$PM2_APP_NAME"; then
        warning "PM2 process $PM2_APP_NAME already exists"
        confirm "Restart it?" Y && pm2 restart "$PM2_APP_NAME"
        return 0
    fi
    
    info "Starting NITO explorer as $PM2_APP_NAME..."
    
    # Start with unique name
    pm2 start bin/instance --name "$PM2_APP_NAME" -i 1 || {
        error "Failed to start explorer"
        cat "$EXPLORER_DIR/tmp/explorer.log" 2>/dev/null
        fatal "Explorer start failed"
    }
    
    success "Explorer started as $PM2_APP_NAME"
    
    pm2 save
    
    # Setup PM2 startup if not already configured
    if ! systemctl is-enabled --quiet pm2-root 2>/dev/null; then
        pm2 startup systemd -u root --hp /root
        systemctl daemon-reload
        systemctl enable pm2-root
        systemctl start pm2-root
    fi
    
    sleep 2
    systemctl is-active --quiet pm2-root && success "PM2 service active" || warning "PM2 service issue"
}

################################################################################
# STEP 18: Setup Synchronization
################################################################################
setup_sync() {
    info "Configuring synchronization..."
    cd "$EXPLORER_DIR"
    
    cat > "$EXPLORER_DIR/sync-$INSTALL_NAME.sh" <<EOF
#!/bin/bash
export NVM_DIR="/root/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
cd $EXPLORER_DIR
npm run sync-blocks >> $EXPLORER_DIR/sync-cron.log 2>&1
EOF
    
    chmod +x "$EXPLORER_DIR/sync-$INSTALL_NAME.sh"
    nohup "$EXPLORER_DIR/sync-$INSTALL_NAME.sh" > "$EXPLORER_DIR/sync-initial.log" 2>&1 &
    
    # Add cron job only if not already present
    if ! crontab -l 2>/dev/null | grep -q "$EXPLORER_DIR/sync-$INSTALL_NAME.sh"; then
        (crontab -l 2>/dev/null; echo "*/1 * * * * /bin/bash $EXPLORER_DIR/sync-$INSTALL_NAME.sh") | crontab -
    fi
    
    success "Synchronization configured"
}

################################################################################
# STEP 19: Final Validation
################################################################################
final_validation() {
    info "Running final validation..."
    
    systemctl is-active --quiet pm2-root && success "✅ PM2 service: active" || error "❌ PM2 service: inactive"
    docker ps | grep -q "$MONGODB_CONTAINER" && success "✅ MongoDB: running" || error "❌ MongoDB: stopped"
    systemctl is-active --quiet nginx && success "✅ Nginx: active" || error "❌ Nginx: inactive"
    pm2 list | grep -q "$PM2_APP_NAME" && success "✅ Explorer ($PM2_APP_NAME): running" || error "❌ Explorer: stopped"
    crontab -l | grep -q "$EXPLORER_DIR/sync-$INSTALL_NAME.sh" && success "✅ Cron: configured" || error "❌ Cron: missing"
}

################################################################################
# STEP 20: Show Summary
################################################################################
show_summary() {
    echo ""
    echo "=========================================="
    success "🎉 NITO EXPLORER INSTALLATION COMPLETE!"
    echo "=========================================="
    echo ""
    highlight "NITO EXPLORER INFORMATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Coin             : $COIN_NAME ($COIN_SYMBOL)"
    echo "Genesis Block    : ${GENESIS_BLOCK:0:32}..."
    echo "Genesis TX       : ${GENESIS_TX:0:32}..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "EXPLORER ACCESS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "URL              : https://$DOMAIN"
    echo "Local            : http://localhost:$EXPLORER_PORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "INSTALLATION DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Directory        : $EXPLORER_DIR"
    echo "PM2 App Name     : $PM2_APP_NAME"
    echo "MongoDB Container: $MONGODB_CONTAINER"
    echo "MongoDB Database : $MONGODB_DATABASE"
    echo "MongoDB User     : $MONGODB_USER"
    echo "Explorer Port    : $EXPLORER_PORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "USEFUL COMMANDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  pm2 list                          # Check all explorers"
    echo "  pm2 logs $PM2_APP_NAME            # View NITO logs"
    echo "  pm2 restart $PM2_APP_NAME         # Restart NITO explorer"
    echo "  docker ps                         # View containers"
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
    echo "║     NITO Explorer Installer v$SCRIPT_VERSION     ║"
    echo "║     Multi-Explorer Compatible              ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    install_cron
    collect_configuration
    create_directories
    install_system_dependencies
    install_nodejs
    install_docker
    configure_mongodb
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
