# Cross-Org Connectivity

## Standalone Mode (default)

Each org runs its own isolated QBFT chain. This is the default (`crossOrg.mode: standalone` in `config.yaml`).

In standalone mode:
- **FireFly DataExchange** handles off-chain point-to-point messaging between orgs (HTTPS, mTLS). This works across org boundaries without any chain coordination.
- **Paladin private transactions** are local to each org's chain. Cross-org private tx is not possible in this mode.
- **FireFly multiparty on-chain anchoring** uses each org's own chain. There is no shared ledger.

Standalone is the right choice when orgs need off-chain coordination only, or when each org maintains independent ledger sovereignty.

---

## Shared-Chain-Group Mode

Multiple orgs share a single QBFT chain (same genesis block + same `chainId`). This enables:
- **Paladin Pente privacy groups** spanning multiple orgs
- **FireFly multiparty** with on-chain batch pinning visible to all orgs
- **Noto token transfers** across org boundaries

Set in `config.yaml`:

```yaml
crossOrg:
  mode: shared-chain-group
  sharedGenesisRef: ""   # see below
  peers: []              # see below
```

---

## Setting Up a Shared Chain

### Step 1: Bootstrap the first org normally

Run `bootstrap.sh` on org1's cluster as usual. Note the Besu enode URL:

```bash
kubectl exec -n paladin deploy/besu-node-0 -- \
  curl -sf -X POST http://localhost:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['enode'])"
```

Note org1's cluster host IP and the Besu P2P NodePort (`besu.baseNodePort + 2`, default `31547`).

Replace the `@<IP>` part of the enode with `<org1-host-ip>:31547`.

### Step 2: Configure org2 to join

In org2's `config.yaml`:

```yaml
besu:
  chainId: 1337          # must match org1 exactly

crossOrg:
  mode: shared-chain-group
  sharedGenesisRef: "https://raw.githubusercontent.com/YOUR_ORG/onchain-org-stack/main/chain/genesis.json"
  peers:
    - enode://...@<org1-host-ip>:31547
```

`sharedGenesisRef` points to org1's rendered genesis file (committed to the repo). Alternatively, copy the genesis JSON directly into org2's repo.

### Step 3: Render and join

```bash
bash scripts/render.sh --write
git add -A && git commit -m "configure org2 shared-chain-group" && git push
bash scripts/join-chain.sh <org1-host-ip>:31547
bash bootstrap.sh
```

`scripts/join-chain.sh` configures Besu to boot with the existing chain state rather than creating a new genesis.

---

## NodePort Assignments

| Service             | NodePort formula                    | Default value |
|---------------------|-------------------------------------|---------------|
| Besu P2P (TCP/UDP)  | `besu.baseNodePort + 2`             | 31547         |
| Paladin transport   | `paladin.baseNodePort`              | 31548         |
| FireFly DataExchange | configured in `dataexchange-app.yaml` | 31550 (example) |

When running multiple orgs on the same physical host, set different `besu.baseNodePort` and `paladin.baseNodePort` values in each org's `config.yaml` to avoid port conflicts.

---

## Security

NodePorts are exposed on all k3s cluster host interfaces by default. In production:
- Restrict NodePort access with firewall rules (iptables / cloud security groups) to only allow specific peer IPs.
- Use a VPN or private network between org clusters rather than exposing NodePorts to the public internet.
- Rotate Paladin and FireFly TLS certificates via cert-manager and store private keys in Vault.
