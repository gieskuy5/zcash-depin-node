#!/bin/bash
# ============================================================
# Zcash DePIN Node - Status Checker
# Shows sync progress, relay status, and points earned
# ============================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       DePINZcash Node Status            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# Detect node setup
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^zebra$"; then
    # Single node setup
    MODE="single"
    echo -e "${CYAN}Mode: Single Node${NC}"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^zebra1$"; then
    # Multi node setup
    NODE_COUNT=$(docker ps --format '{{.Names}}' | grep -c "^zebra[0-9]")
    MODE="multi"
    echo -e "${CYAN}Mode: Multi-Node ($NODE_COUNT nodes)${NC}"
else
    echo -e "${RED}No running Zebra containers found${NC}"
    exit 1
fi

echo ""

# === Sync Status ===
echo -e "${YELLOW}── Sync Status ──${NC}"

if [[ "$MODE" == "single" ]]; then
    SYNC=$(docker logs zebra --tail 5 2>&1 | grep -oP 'sync_percent=\K[0-9.]+' | tail -1)
    HEIGHT=$(docker logs zebra --tail 5 2>&1 | grep -oP 'current_height=Height\(\K[0-9]+' | tail -1)
    echo -e "  Zebra: ${GREEN}${SYNC:-?}%${NC} (height ${HEIGHT:-?})"
else
    for i in $(seq 1 $NODE_COUNT); do
        SYNC=$(docker logs zebra$i --tail 5 2>&1 | grep -oP 'sync_percent=\K[0-9.]+' | tail -1)
        HEIGHT=$(docker logs zebra$i --tail 5 2>&1 | grep -oP 'current_height=Height\(\K[0-9]+' | tail -1)
        echo -e "  Node $i: ${GREEN}${SYNC:-?}%${NC} (height ${HEIGHT:-?})"
    done
fi

echo ""

# === Relay Status ===
echo -e "${YELLOW}── Relay Status ──${NC}"

if [[ "$MODE" == "single" ]]; then
    STATUS=$(systemctl is-active depinzcash-relay 2>/dev/null)
    ACCEPTED=$(journalctl -u depinzcash-relay --no-pager 2>&1 | grep -c 'verdict=accepted')
    LAST=$(journalctl -u depinzcash-relay --no-pager -n 5 --output=cat 2>&1 | grep -E 'submitted|verdict' | tail -1)
    
    if [[ "$STATUS" == "active" ]]; then
        echo -e "  Relay: ${GREEN}active${NC} | Submissions: ${GREEN}$ACCEPTED${NC}"
    else
        echo -e "  Relay: ${RED}$STATUS${NC}"
    fi
    [[ -n "$LAST" ]] && echo -e "  Last: $LAST"
else
    TOTAL_ACCEPTED=0
    for i in $(seq 1 $NODE_COUNT); do
        STATUS=$(systemctl is-active depinzcash-relay-$i 2>/dev/null)
        ACCEPTED=$(journalctl -u depinzcash-relay-$i --no-pager 2>&1 | grep -c 'verdict=accepted')
        TOTAL_ACCEPTED=$((TOTAL_ACCEPTED + ACCEPTED))
        
        if [[ "$STATUS" == "active" ]]; then
            echo -e "  Relay $i: ${GREEN}active${NC} | Submissions: ${GREEN}$ACCEPTED${NC}"
        else
            echo -e "  Relay $i: ${RED}$STATUS${NC}"
        fi
    done
    echo -e "  Total submissions: ${GREEN}$TOTAL_ACCEPTED${NC}"
fi

echo ""

# === Points Estimate ===
echo -e "${YELLOW}── Points Estimate ──${NC}"

if [[ "$MODE" == "single" ]]; then
    # Check node type from state file
    STATE=$(find /root -name "relay-state.json" -path "*/config/*" 2>/dev/null | head -1)
    if [[ -f "$STATE" ]]; then
        KIND=$(grep -oP '"kind"\s*:\s*"\K[^"]+' "$STATE")
        if [[ "$KIND" == "zebra-full" ]]; then
            PTS_PER=60
        else
            PTS_PER=36
        fi
        echo -e "  Type: ${CYAN}$KIND${NC} ($PTS_PER pts/submit)"
        echo -e "  Total points: ${GREEN}$((ACCEPTED * PTS_PER))${NC}"
    fi
else
    TOTAL_PTS=0
    for i in $(seq 1 $NODE_COUNT); do
        STATE="/root/node${i}/config/relay-state.json"
        if [[ -f "$STATE" ]]; then
            KIND=$(grep -oP '"kind"\s*:\s*"\K[^"]+' "$STATE")
        else
            KIND="lightwalletd"
        fi
        [[ "$KIND" == "zebra-full" ]] && PTS=60 || PTS=36
        ACCEPTED=$(journalctl -u depinzcash-relay-$i --no-pager 2>&1 | grep -c 'verdict=accepted')
        NODE_PTS=$((ACCEPTED * PTS))
        TOTAL_PTS=$((TOTAL_PTS + NODE_PTS))
    done
    echo -e "  Type: ${CYAN}lightwalletd${NC} (36 pts/submit)"
    echo -e "  Total points: ${GREEN}$TOTAL_PTS${NC}"
fi

echo ""
echo -e "${CYAN}── End ──${NC}"
