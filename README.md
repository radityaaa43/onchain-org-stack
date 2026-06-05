# onchain-org-stack

Per-org template for deploying a private blockchain stack on a single k3s cluster: Hyperledger Besu QBFT consensus, LF Paladin privacy layer (Noto/Zeto/Pente domains), and Hyperledger FireFly multiparty middleware. All configuration is driven from a single `config.yaml`; `render.sh` propagates values to every manifest before deployment.

## Quick Start

```bash
# 1. Clone and configure for your org
git clone https://github.com/YOUR_ORG/onchain-org-stack
cd onchain-org-stack
# Edit org.name, org.domain, repo.url in config.yaml

# 2. Render all derived manifests
bash scripts/render.sh --write
git add -A && git commit -m "configure <org-name>" && git push

# 3. Bootstrap the full stack (~10-15 min)
bash bootstrap.sh
```

## Components

| Layer      | Components                                              |
|------------|---------------------------------------------------------|
| Platform   | cert-manager, traefik, ArgoCD, kube-prometheus-stack, Loki |
| Secrets    | HashiCorp Vault                                         |
| Data       | PostgreSQL, MongoDB, Redis, Kafka (Strimzi), ScyllaDB, IPFS |
| Chain      | Hyperledger Besu (QBFT validator), LF Paladin operator  |
| Middleware | FireFly Signer, FireFly Core, EVMConnect, DataExchange  |

## Adding a New Org

Each org is a separate clone of this repo on its own k3s cluster. See [docs/ADD-NEW-ORG.md](docs/ADD-NEW-ORG.md) for the full walkthrough.

## Cross-Org Peering

Orgs can operate standalone (isolated chains) or join a shared QBFT chain for cross-org Paladin private transactions and FireFly multiparty anchoring. See [docs/CROSS-ORG.md](docs/CROSS-ORG.md).

## Architecture

Full component diagram, chainId flow, bootstrap steps, and list of bugs fixed vs the original dev-stack: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
