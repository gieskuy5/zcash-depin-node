#!/bin/bash
# ============================================================
# Check DePINZcash Node Status
# ============================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== DePINZcash Node Status ===${NC}\n"

# Zebra container
echo -e "${CYAN}[Zebra Node]${NC}"
if docker ps --filter name=zebra --format "{{.Status}}" | grep -q "Up"; then
    echo -e "  Status: ${GREEN}Running${NC}"
    SYNC=$(docker logs zebra 2>&1 | grep "sync_percent" | tail -1 | grep -oP 'sync_percent=\K[0-9.]+')
    HEIGHT=$(docker logs zebra 2>&1 | grep "current_height" | tail -1 | grep -oP 'current_height=Height\(\K[0-9]+')
    echo -e "  Sync:   ${YELLOW}${SYNC:-?}%${NC}"
    echo -e "  Height: ${HEIGHT:-?}"
else
    echo -e "  Status: ${RED}Stopped${NC}"
fi

echo ""

# Relay service
echo -e "${CYAN}[Relay Service]${NC}"
if systemctl is-active --quiet depinzcash-relay; then
    echo -e "  Status: ${GREEN}Active${NC}"
    LAST_LOG=$(journalctl -u depinzcash-relay --no-pager -n 3 2>/dev/null | tail -3)
    echo "  Last logs:"
    echo "$LAST_LOG" | sed 's/^/    /'
else
    echo -e "  Status: ${RED}Inactive${NC}"
fi

echo ""

# Wallet info
echo -e "${CYAN}[Wallet]${NC}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/config/solana-keypair.json" ]]; then
    echo "  Keypair: $SCRIPT_DIR/config/solana-keypair.json"
    cat "$SCRIPT_DIR/config/solana-keypair.json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if 'public_key' in d:
    print(f'  Public key: {d[\"public_key\"]}')
" 2>/dev/null
else
    echo "  Keypair: not found"
fi

echo ""

# Disk usage
echo -e "${CYAN}[Resources]${NC}"
DISK_USED=$(du -sh /root/zebra/state 2>/dev/null | awk '{print $1}')
echo "  Blockchain data: ${DISK_USED:-0}"
echo "  Disk available:  $(df -h / | awk 'NR==2 {print $4}')"
echo "  Memory:          $(free -h | awk '/Mem:/ {printf "%s / %s", $3, $2}')"
