# Zcash DePIN Node

One-click setup for DePINZcash node operators. Earn $ZePIN rewards on Solana for running Zcash infrastructure.

Supports both **Zebra Full Node** (higher rewards) and **Lightwalletd** (lighter setup), including multi-node deployment on a single VPS.

## Requirements

| | Zebra Full Node | Lightwalletd (x4) |
|---|---|---|
| CPU | 2+ cores | 4 cores |
| RAM | 4-8 GB | 8 GB |
| Disk | 120 GB SSD | 120 GB SSD |
| Network | 10+ Mbps | 10 Mbps |
| OS | Ubuntu 22.04+ | Ubuntu 22.04+ |

## Quick Start — Single Node

```bash
git clone https://github.com/gieskuy5/zcash-depin-node.git
cd zcash-depin-node
chmod +x setup.sh
./setup.sh --full    # Zebra full node (60 pts/submit)
./setup.sh --light   # Lightwalletd (36 pts/submit)
```

## Quick Start — Multi-Node (4 Lightwalletd)

```bash
git clone https://github.com/gieskuy5/zcash-depin-node.git
cd zcash-depin-node
chmod +x setup-multi.sh
./setup-multi.sh 4 mynode    # 4 nodes, label prefix "mynode"
```

## What It Does

1. Installs Docker
2. Starts Zebra node(s) (blockchain sync)
3. Installs Rust and builds `depinzcash-relay` (with 30s timeout patch)
4. Generates Solana keypair(s)
5. Registers node(s) with DePINZcash API
6. Sets up systemd relay service(s) — auto-submits proofs every 5 minutes

## Points System

| Node Type | Points/Submit | Submit Interval |
|-----------|--------------|-----------------|
| Zebra Full | 60 pts | 5 min |
| Lightwalletd | 36 pts | 5 min |

Estimated daily earnings (after full sync):
- 1 Zebra Full: ~17,280 pts/day
- 4 Lightwalletd: ~41,472 pts/day
- Combined (1 full + 4 light): ~58,752 pts/day

## Status Check

```bash
./status.sh
```

Shows sync progress, relay status, and points earned.

## Uninstall

```bash
./uninstall.sh
```

## Architecture

```
┌─────────────────────────────────────────┐
│  VPS                                    │
│                                         │
│  ┌──────────┐    ┌──────────────────┐   │
│  │  Zebra   │◄───│ depinzcash-relay │   │
│  │  (Docker)│    │   (systemd)      │   │
│  │  RPC:8232│    │                  │   │
│  └──────────┘    └────────┬─────────┘   │
│                           │             │
└───────────────────────────┼─────────────┘
                            │ POST /api/proofs/submit
                            ▼
                ┌───────────────────────┐
                │  api.zcashdepin.com   │
                │  (Fly.io)            │
                └───────────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │  Solana (rewards)     │
                │  $ZePIN token         │
                └───────────────────────┘
```

## Patches Applied

- **Timeout fix**: API submit timeout increased from 5s/15s → 30s (Fly.io can be slow)
- **Cookie auth disabled**: `ZEBRA_RPC__ENABLE_COOKIE_AUTH=false` (relay connects without auth)

## Troubleshooting

**Relay submit timeout:**
Normal during initial sync. Relay auto-retries every 5 minutes.

**409 Conflict:**
"proof already submitted by this node" — means relay is working, just submitted same height twice. Harmless.

**Sync stuck:**
```bash
docker rm -f zebra
rm -rf /root/zebra/state
# Re-run setup.sh
```

**Check relay logs:**
```bash
journalctl -u depinzcash-relay -f          # Single node
journalctl -u depinzcash-relay-1 -f        # Multi node
```

## License

MIT
