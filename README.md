# Zcash DePIN Node

One-click setup for DePINZcash node operators. Earn $ZePIN rewards on Solana for running Zcash infrastructure.

Supports both **Zebra Full Node** (higher rewards) and **Lightwalletd** (lighter setup).

## Requirements

| | Zebra Full Node | Lightwalletd |
|---|---|---|
| CPU | 2+ cores | 2 cores |
| RAM | 4-8 GB | 1-2 GB |
| Disk | 120 GB SSD | 30 GB SSD |
| Network | 10+ Mbps | 10 Mbps |
| OS | Ubuntu 22.04+ | Ubuntu 22.04+ |

## Quick Start

```bash
git clone https://github.com/gieskuy5/zcash-depin-node.git
cd zcash-depin-node
chmod +x setup.sh
./setup.sh
```

The setup script will:
1. Install Docker
2. Pull Zebra/Lightwalletd image
3. Start the node
4. Install Rust and build `depinzcash-relay`
5. Generate Solana keypair
6. Register your node
7. Start relay service (auto-submit proofs every 5 minutes)

## Choose Your Node Type

```bash
# Full node (higher rewards, needs 120GB+ disk)
./setup.sh --full

# Lightwalletd (lower rewards, only 30GB disk)
./setup.sh --light
```

## After Setup

- Node syncs automatically (4-24 hours for full node)
- Relay submits proofs every 5 minutes once synced
- Launch bonus: ~$40 in $ZePIN after 24h online

## Check Status

```bash
# Node sync progress
docker logs zebra 2>&1 | grep sync_percent | tail -3

# Relay status
systemctl status depinzcash-relay

# Your wallet
cat config/solana-keypair.json
```

## Reward Formula

```
points = tier x (1 + freshness) + min(uptime_hours, 24) + min(peers/4, 3)
tier = 10 (zebra-full) | 6 (lightwalletd)
```

## Links

- [DePINZcash Site](https://www.zcashdepin.com/)
- [Leaderboard](https://www.zcashdepin.com/leaderboard)
- [Dashboard](https://www.zcashdepin.com/dashboard)
- [GitHub (Official)](https://github.com/ZcashDePIN/DePINZcash)

## License

MIT
