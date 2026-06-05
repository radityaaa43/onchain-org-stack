# Architecture

## Overview

`onchain-org-stack` is a per-org template for deploying a private blockchain stack on a single k3s cluster. Each org runs:

- **Hyperledger Besu** (QBFT consensus) as the EVM-compatible chain node
- **LF Paladin** (privacy layer) with Noto, Zeto, and Pente domains for private transactions
- **Hyperledger FireFly** (multiparty middleware) for on-chain anchoring, off-chain messaging, and event streaming

All configuration is derived from a single `config.yaml` via `scripts/render.sh`.

---

## Per-Org Topology

One k3s cluster = one org. Each org owns its own chain by default (`crossOrg.mode: standalone`). Multiple orgs can share a chain via `crossOrg.mode: shared-chain-group` (see `docs/CROSS-ORG.md`).

```
┌─────────────────────────────────────────────────┐
│  k3s cluster (org1)                             │
│                                                 │
│  platform/      cert-manager, traefik, argocd   │
│  secrets/       vault                           │
│  data/          postgres, mongodb, redis,        │
│                 kafka, scylla, ipfs             │
│  chain/         besu (QBFT), paladin operator   │
│  middleware/    firefly signer, core,            │
│                 evmconnect, dataexchange         │
└─────────────────────────────────────────────────┘
```

---

## Component Layers

### Platform

| Component    | Role                                              |
|--------------|---------------------------------------------------|
| cert-manager | TLS certificate issuance (Let's Encrypt or self-signed) |
| traefik      | Ingress controller with TLS termination           |
| argocd       | GitOps controller — all apps deployed as ArgoCD Applications |
| monitoring   | kube-prometheus-stack + Loki                      |

### Secrets

| Component | Role                                            |
|-----------|-------------------------------------------------|
| Vault     | KV secret store. `unseal-init.sh` handles init and unseal on first boot. |

### Data

| Component | Role                                            |
|-----------|-------------------------------------------------|
| PostgreSQL | FireFly core state store                        |
| MongoDB    | FireFly off-chain data store                    |
| Redis      | FireFly cache / pub-sub                         |
| Kafka (Strimzi) | FireFly event bus                          |
| ScyllaDB   | Paladin state store (high-throughput tx history) |
| IPFS       | FireFly blob/document storage                   |

### Chain

| Component        | Role                                         |
|------------------|----------------------------------------------|
| Besu validator   | Single-node QBFT chain (expandable to multi-validator via `besu.nodeCount`) |
| Paladin operator | Deploys Paladin node in devnet mode, attaches to Besu RPC |

### Middleware

| Component             | Role                                       |
|-----------------------|--------------------------------------------|
| FireFly Signer        | Key management, EIP-155 signing            |
| FireFly Core          | Multiparty orchestration, REST/WS API      |
| EVMConnect            | FireFly <-> Besu JSON-RPC bridge           |
| DataExchange          | Off-chain point-to-point file/message relay |
| Token connectors      | ERC-20/ERC-721 connector (optional)        |

---

## Single Source of Truth

```
config.yaml
    │
    └──> scripts/render.sh --write
              │
              ├── platform/cert-manager/cluster-issuers.yaml
              ├── platform/argocd/root-app.yaml
              ├── secrets/vault/vault-app.yaml
              ├── data/kafka/kafka-cluster-app.yaml
              ├── chain/values.yaml          (Paladin Helm values)
              ├── chain/paladin-app.yaml
              └── middleware/firefly/*.yaml   (signer, multiparty configs)
```

Every value that must be consistent across components (org name, domain, chainId, image arch, repo URL) is written once in `config.yaml` and propagated by `render.sh`.

---

## ChainId Flow

```
config.yaml
  besu.chainId: 1337
       │
       ├──> chain/values.yaml        (Paladin operator genesis → Besu)
       ├──> middleware/firefly/signer-app.yaml  (EIP-155 signing domain)
       └──> middleware/firefly/evmconnect/evmconnect-app.yaml
```

This resolves the original EIP-155 mismatch: the source repo had Besu genesis hardcoded to `chainId: 2025` while FireFly signer was configured for `1337`. All three components now derive the value from the same field.

---

## Bootstrap Flow

| Step | Action |
|------|--------|
| 0    | `render.sh --write` — generate all manifests, commit rendered files |
| 1    | Install cert-manager via Helm; apply ClusterIssuers |
| 2    | Apply traefik IngressClass / middleware config |
| 3    | Install ArgoCD (`platform/argocd/install.sh`); apply root-app |
| 4    | Apply vault-app; wait for pod ready; run `unseal-init.sh` |
| 5    | `scripts/deploy-data.sh` — postgres, mongodb, redis |
| 6    | Apply kafka operator + kafka cluster; apply ipfs + scylla |
| 7    | Apply `chain/paladin-app.yaml`; poll `eth_blockNumber` until > 0 |
| 8    | `scripts/deploy-contract.sh` — deploy FireFly batch pin contract |
| 9    | Apply all FireFly apps: signer, core, evmconnect, dataexchange, ipfs, ingress, CORS |
| 10   | Apply monitoring apps (kube-prometheus-stack, Loki) |

---

## Cross-Org Modes

| Mode               | Chain          | Private TX across orgs | FireFly multiparty |
|--------------------|----------------|------------------------|--------------------|
| `standalone`       | Per-org isolated | No                   | Off-chain DX only  |
| `shared-chain-group` | Shared QBFT  | Yes (Paladin Pente)  | Full on+off chain  |

NodePort assignments (default):

| Service         | NodePort              |
|-----------------|-----------------------|
| Besu P2P        | `besu.baseNodePort + 2` (default 31547) |
| Paladin transport | `paladin.baseNodePort` (default 31548) |
| FireFly DX      | configured in dataexchange app |

---

## Bugs Fixed vs onchain-dev-stack

| # | Bug | Fix |
|---|-----|-----|
| 1 | chainId mismatch (Besu=2025, signer=1337) causing EIP-155 failures | Single `besu.chainId` in config.yaml propagated to all three components |
| 2 | Paladin ArgoCD app had 3 hardcoded `nodeCount` blocks instead of a loop | `paladin-app.tmpl.yaml` loops over `besu.nodeCount` |
| 3 | Images locked to `arm64` Linux node selector | `arch: amd64` in config.yaml; no hardcoded node selectors in templates |
| 4 | Postgres password hardcoded in connection URL with a typo (`pasword`) | Password injected from Kubernetes Secret; render.sh generates the Secret |
| 5 | Kafka ingress had `namespace: kafka` hardcoded | `namespace` templated from `org.name` context |
| 6 | Paladin middleware ConfigMap referenced `namespace: default` | Templated to `namespace: paladin` |
| 7 | ArgoCD Applications had 13 different hardcoded `repoURL` values | Single `repo.url` from config.yaml injected by render.sh |
| 8 | FireFly batch pin contract required manual deploy step | `bootstrap.sh` step 8 calls `scripts/deploy-contract.sh` automatically |
