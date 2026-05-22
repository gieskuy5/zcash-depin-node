#!/bin/bash
# ============================================================
# Zcash DePIN Node - Multi-Lightwalletd Setup
# Run 4 lightwalletd nodes on a single VPS
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

API_URL="https://api.zcashdepin.com"
NODE_COUNT="${1:-4}"
LABEL_PREFIX="${2:-$(hostname)-light}"

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║   Zcash DePIN Multi-Lightwalletd Setup  ║"
echo "║   Running $NODE_COUNT nodes on single VPS         ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# Step 1: Install Docker
# ============================================================
echo -e "\n${CYAN}[1/5] Installing Docker${NC}"
if command -v docker &>/dev/null; then
    log "Docker already installed"
else
    curl -fsSL https://get.docker.com | sh
    log "Docker installed"
fi

# ============================================================
# Step 2: Start Zebra nodes
# ============================================================
echo -e "\n${CYAN}[2/5] Starting $NODE_COUNT Zebra nodes${NC}"

BASE_RPC_PORT=8232
BASE_NET_PORT=8233

for i in $(seq 1 $NODE_COUNT); do
    RPC_PORT=$((BASE_RPC_PORT + (i-1)*2))
    NET_PORT=$((BASE_NET_PORT + (i-1)*2))
    CONTAINER="zebra${i}"
    STATE_DIR="/root/zebra/state${i}"
    
    docker rm -f "$CONTAINER" 2>/dev/null || true
    mkdir -p "$STATE_DIR"
    
    docker run -d \
        --name "$CONTAINER" \
        --restart unless-stopped \
        -p ${RPC_PORT}:8232 \
        -p ${NET_PORT}:8233 \
        -v ${STATE_DIR}:/root/.cache/zebra \
        -e ZEBRA_NETWORK__LISTEN_ADDR=0.0.0.0:8233 \
        -e ZEBRA_RPC__LISTEN_ADDR=0.0.0.0:8232 \
        -e ZEBRA_RPC__ENABLE_COOKIE_AUTH=false \
        -e UID=0 -e GID=0 \
        zfnd/zebra:latest
    
    log "Node $i started (RPC: $RPC_PORT, Net: $NET_PORT)"
done

# ============================================================
# Step 3: Install Rust & build relay
# ============================================================
echo -e "\n${CYAN}[3/5] Building depinzcash-relay${NC}"

RELAY_BIN="/usr/local/bin/depinzcash-relay"

if [[ -f "$RELAY_BIN" ]]; then
    log "Relay binary already exists"
else
    # Install Rust
    if ! command -v rustc &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true
    
    apt-get install -y -qq build-essential pkg-config libssl-dev clang libclang-dev 2>/dev/null
    
    rm -rf /tmp/DePINZcash
    git clone --depth 1 https://github.com/ZcashDePIN/DePINZcash.git /tmp/DePINZcash
    cd /tmp/DePINZcash/prover
    
    # Patch timeout to 30s
    sed -i 's/timeout(Duration::from_secs(5))/timeout(Duration::from_secs(30))/' src/bin/relay.rs
    sed -i 's/timeout(Duration::from_secs(15))/timeout(Duration::from_secs(30))/g' src/bin/relay.rs
    
    cargo build --release --bin depinzcash-relay
    cp target/release/depinzcash-relay "$RELAY_BIN"
    cd /root
    rm -rf /tmp/DePINZcash
    log "Relay built (timeout patched to 30s)"
fi

# ============================================================
# Step 4: Generate keypairs & register nodes
# ============================================================
echo -e "\n${CYAN}[4/5] Generating keypairs & registering${NC}"

for i in $(seq 1 $NODE_COUNT); do
    NODE_DIR="/root/node${i}/config"
    mkdir -p "$NODE_DIR"
    
    if [[ -f "$NODE_DIR/solana-keypair.json" ]]; then
        log "Node $i: keypair exists"
    else
        "$RELAY_BIN" keygen --out "$NODE_DIR/solana-keypair.json"
        log "Node $i: keypair generated"
    fi
    
    if [[ -f "$NODE_DIR/relay-state.json" ]]; then
        log "Node $i: already registered"
    else
        cd "$NODE_DIR"
        "$RELAY_BIN" register \
            --api "$API_URL" \
            --keypair "$NODE_DIR/solana-keypair.json" \
            --kind "lightwalletd" \
            --label "${LABEL_PREFIX}-${i}"
        log "Node $i: registered"
        cd /root
    fi
done

# ============================================================
# Step 5: Setup systemd services
# ============================================================
echo -e "\n${CYAN}[5/5] Setting up relay services${NC}"

for i in $(seq 1 $NODE_COUNT); do
    NODE_DIR="/root/node${i}/config"
    RPC_PORT=$((BASE_RPC_PORT + (i-1)*2))
    
    cat > /etc/systemd/system/depinzcash-relay-${i}.service << SVC
[Unit]
Description=DePINZcash Relay Node $i
After=docker.service
Wants=docker.service

[Service]
Type=simple
WorkingDirectory=$NODE_DIR
ExecStart=$RELAY_BIN watch --interval-secs 300 --api $API_URL --keypair $NODE_DIR/solana-keypair.json --state $NODE_DIR/relay-state.json --node-rpc http://127.0.0.1:${RPC_PORT}
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
SVC
    
    systemctl daemon-reload
    systemctl enable "depinzcash-relay-${i}"
    systemctl restart "depinzcash-relay-${i}"
    log "Relay $i service started (RPC port: $RPC_PORT)"
done

# ============================================================
# Done!
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Multi-Node Setup Complete!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "Nodes:  ${CYAN}$NODE_COUNT lightwalletd${NC}"
echo -e "Label:  ${CYAN}${LABEL_PREFIX}-[1-${NODE_COUNT}]${NC}"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  docker logs zebra1 2>&1 | grep sync_percent | tail -1   # Node 1 sync"
echo "  systemctl status depinzcash-relay-1                      # Relay 1 status"
echo "  journalctl -u depinzcash-relay-1 -f                      # Relay 1 logs"
echo ""
echo -e "${YELLOW}Check all nodes:${NC}"
echo "  for i in \$(seq 1 $NODE_COUNT); do docker logs zebra\$i --tail 1 2>&1 | grep sync; done"
