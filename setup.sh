#!/bin/bash
# ============================================================
# Zcash DePIN Node - One-click Setup
# Supports: Zebra Full Node | Lightwalletd
# Earn $ZePIN rewards on Solana
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$INSTALL_DIR/config"
API_URL="https://api.zcashdepin.com"

# Default to empty (will prompt)
NODE_TYPE=""

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║       Zcash DePIN Node Setup            ║"
    echo "║       Earn \$ZePIN on Solana              ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --full) NODE_TYPE="zebra-full"; shift ;;
        --light) NODE_TYPE="lightwalletd"; shift ;;
        --label) NODE_LABEL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: ./setup.sh [--full|--light] [--label NAME]"
            echo "  --full   Run Zebra full node (higher rewards, 120GB disk)"
            echo "  --light  Run Lightwalletd (lower rewards, 30GB disk)"
            echo "  --label  Custom node label (default: hostname)"
            exit 0 ;;
        *) shift ;;
    esac
done

print_banner

# Interactive node type selection if not passed via args
if [[ -z "$NODE_TYPE" ]]; then
    echo -e "${YELLOW}Select node type:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Zebra Full Node  ${GREEN}(60 pts/submit, needs 120GB disk)${NC}"
    echo -e "  ${CYAN}2)${NC} Lightwalletd     ${GREEN}(36 pts/submit, lighter setup)${NC}"
    echo ""
    while true; do
        read -p "Choose [1/2]: " choice
        case $choice in
            1) NODE_TYPE="zebra-full"; break ;;
            2) NODE_TYPE="lightwalletd"; break ;;
            *) echo -e "${RED}Invalid choice. Enter 1 or 2.${NC}" ;;
        esac
    done
    echo ""
fi

# Interactive label if not passed
if [[ -z "$NODE_LABEL" ]]; then
    DEFAULT_LABEL="$(hostname)-${NODE_TYPE}"
    read -p "Node label [${DEFAULT_LABEL}]: " NODE_LABEL
    NODE_LABEL="${NODE_LABEL:-$DEFAULT_LABEL}"
fi

echo -e "Node type: ${CYAN}$NODE_TYPE${NC}"
echo -e "Label:     ${CYAN}$NODE_LABEL${NC}"
echo ""

# ============================================================
# Step 1: System checks
# ============================================================
echo -e "\n${CYAN}[1/7] System checks${NC}"

# Check disk space
AVAIL_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ "$NODE_TYPE" == "zebra-full" ]] && [[ $AVAIL_GB -lt 120 ]]; then
    err "Need 120GB+ disk for full node. Available: ${AVAIL_GB}GB. Use --light instead."
fi
if [[ "$NODE_TYPE" == "lightwalletd" ]] && [[ $AVAIL_GB -lt 30 ]]; then
    err "Need 30GB+ disk. Available: ${AVAIL_GB}GB"
fi
log "Disk: ${AVAIL_GB}GB available"

# Check RAM
RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
log "RAM: ${RAM_GB}GB"

# Check CPU
CORES=$(nproc)
log "CPU: ${CORES} cores"

# ============================================================
# Step 2: Install Docker
# ============================================================
echo -e "\n${CYAN}[2/7] Installing Docker${NC}"

if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    log "Docker installed: $(docker --version)"
fi

# ============================================================
# Step 3: Start Zcash Node
# ============================================================
echo -e "\n${CYAN}[3/7] Starting Zcash node ($NODE_TYPE)${NC}"

# Stop existing container
docker rm -f zebra 2>/dev/null || true

mkdir -p /root/zebra/state

if [[ "$NODE_TYPE" == "zebra-full" ]]; then
    docker pull zfnd/zebra:latest
    docker run -d \
        --name zebra \
        --restart unless-stopped \
        -p 8232:8232 \
        -p 8233:8233 \
        -v /root/zebra/state:/root/.cache/zebra \
        -e ZEBRA_NETWORK__LISTEN_ADDR=0.0.0.0:8233 \
        -e ZEBRA_RPC__LISTEN_ADDR=0.0.0.0:8232 \
        -e ZEBRA_RPC__ENABLE_COOKIE_AUTH=false \
        -e UID=0 \
        -e GID=0 \
        zfnd/zebra:latest
    log "Zebra full node started (syncing blockchain ~4-24h)"
else
    # Lightwalletd setup — still needs backing Zebra node
    docker pull zfnd/zebra:latest
    docker run -d \
        --name zebra \
        --restart unless-stopped \
        -p 8232:8232 \
        -p 8233:8233 \
        -v /root/zebra/state:/root/.cache/zebra \
        -e ZEBRA_NETWORK__LISTEN_ADDR=0.0.0.0:8233 \
        -e ZEBRA_RPC__LISTEN_ADDR=0.0.0.0:8232 \
        -e ZEBRA_RPC__ENABLE_COOKIE_AUTH=false \
        -e UID=0 \
        -e GID=0 \
        zfnd/zebra:latest
    log "Lightwalletd backing node started"
fi

# ============================================================
# Step 4: Install Rust
# ============================================================
echo -e "\n${CYAN}[4/7] Installing Rust${NC}"

if command -v rustc &>/dev/null; then
    log "Rust already installed: $(rustc --version)"
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    log "Rust installed: $(rustc --version)"
fi
source "$HOME/.cargo/env" 2>/dev/null || true

# Install build deps
apt-get install -y -qq build-essential pkg-config libssl-dev clang libclang-dev 2>/dev/null

# ============================================================
# Step 5: Build depinzcash-relay
# ============================================================
echo -e "\n${CYAN}[5/7] Building depinzcash-relay${NC}"

RELAY_BIN="$INSTALL_DIR/bin/depinzcash-relay"

if [[ -f "$RELAY_BIN" ]]; then
    log "Relay binary already exists"
else
    mkdir -p "$INSTALL_DIR/bin"
    
    if [[ -d /tmp/DePINZcash ]]; then
        rm -rf /tmp/DePINZcash
    fi
    
    git clone --depth 1 https://github.com/ZcashDePIN/DePINZcash.git /tmp/DePINZcash
    cd /tmp/DePINZcash/prover
    
    # Patch timeout from 5s/15s to 30s (Fly.io API can be slow)
    sed -i 's/timeout(Duration::from_secs(5))/timeout(Duration::from_secs(30))/' src/bin/relay.rs
    sed -i 's/timeout(Duration::from_secs(15))/timeout(Duration::from_secs(30))/g' src/bin/relay.rs
    
    cargo build --release --bin depinzcash-relay
    cp target/release/depinzcash-relay "$RELAY_BIN"
    cd "$INSTALL_DIR"
    rm -rf /tmp/DePINZcash
    log "Relay built successfully (timeout patched to 30s)"
fi

# ============================================================
# Step 6: Generate keypair and register
# ============================================================
echo -e "\n${CYAN}[6/7] Generating keypair and registering node${NC}"

mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_DIR/solana-keypair.json" ]]; then
    log "Keypair already exists"
else
    "$RELAY_BIN" keygen --out "$CONFIG_DIR/solana-keypair.json"
    log "Keypair generated"
fi

# Show wallet
WALLET=$("$RELAY_BIN" keygen --out /dev/null 2>&1 | grep -oP 'wallet.*: \K.*' || cat "$CONFIG_DIR/solana-keypair.json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('public_key',''))" 2>/dev/null || echo "check config/solana-keypair.json")

# Register node
if [[ -f "$CONFIG_DIR/relay-state.json" ]]; then
    log "Node already registered"
else
    cd "$CONFIG_DIR"
    "$RELAY_BIN" register \
        --api "$API_URL" \
        --keypair "$CONFIG_DIR/solana-keypair.json" \
        --kind "$NODE_TYPE" \
        --label "$NODE_LABEL"
    log "Node registered"
    cd "$INSTALL_DIR"
fi

# ============================================================
# Step 7: Setup relay systemd service
# ============================================================
echo -e "\n${CYAN}[7/7] Setting up relay service${NC}"

cat > /etc/systemd/system/depinzcash-relay.service << SVC
[Unit]
Description=DePINZcash Relay
After=docker.service
Wants=docker.service

[Service]
Type=simple
WorkingDirectory=$CONFIG_DIR
ExecStart=$RELAY_BIN watch --interval-secs 300 --api $API_URL --keypair $CONFIG_DIR/solana-keypair.json --state $CONFIG_DIR/relay-state.json --node-rpc http://127.0.0.1:8232
Restart=always
RestartSec=60
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable depinzcash-relay
systemctl restart depinzcash-relay
log "Relay service started (submits proofs every 5 minutes)"

# ============================================================
# Done!
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Setup Complete!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "Node type:  ${CYAN}$NODE_TYPE${NC}"
echo -e "Label:      ${CYAN}$NODE_LABEL${NC}"
echo -e "Keypair:    ${CYAN}$CONFIG_DIR/solana-keypair.json${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Wait for blockchain sync (check: docker logs zebra 2>&1 | grep sync_percent | tail -1)"
echo "  2. Relay auto-submits proofs once synced"
echo "  3. Check rewards: https://www.zcashdepin.com/dashboard"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  docker logs zebra 2>&1 | grep sync_percent | tail -3   # Sync progress"
echo "  systemctl status depinzcash-relay                       # Relay status"
echo "  journalctl -u depinzcash-relay -f                       # Relay logs"
echo "  cat $CONFIG_DIR/solana-keypair.json                     # Your wallet"
