#!/bin/bash
# ============================================================
# Uninstall DePINZcash Node
# ============================================================

set -e

echo "Stopping services..."
systemctl stop depinzcash-relay 2>/dev/null || true
systemctl disable depinzcash-relay 2>/dev/null || true
rm -f /etc/systemd/system/depinzcash-relay.service
systemctl daemon-reload

echo "Stopping Zebra container..."
docker rm -f zebra 2>/dev/null || true

echo "Remove blockchain data? (120GB+)"
read -p "[y/N]: " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf /root/zebra/state
    echo "Blockchain data removed."
else
    echo "Blockchain data kept at /root/zebra/state"
fi

echo ""
echo "Uninstall complete."
echo "Keypair preserved at: config/solana-keypair.json"
echo "Back it up if you want to keep your wallet!"
