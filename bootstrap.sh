#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# onchain-org-stack bootstrap
# Usage: bash bootstrap.sh
# Requires: kubectl, helm, git, python3+pyyaml
# ─────────────────────────────────────────────

log() {
  echo ""
  echo "════════════════════════════════════════════════"
  echo "  $*"
  echo "════════════════════════════════════════════════"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─── Pre-flight ───────────────────────────────
log "RENDER: generating derived manifests from config.yaml"
bash scripts/render.sh --write

git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: rendered manifests from config.yaml"
fi

# Read org domain for final output
ORG_DOMAIN="${ORG_DOMAIN:-$(python3 -c "import yaml; c=yaml.safe_load(open('config.yaml')); print(c['org']['domain'])")}"

# ─── STEP 1: cert-manager ─────────────────────
log "STEP 1: cert-manager"
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update jetstack
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.3 \
  --set crds.enabled=true \
  --wait

kubectl apply -f platform/cert-manager/cluster-issuers.yaml

# ─── STEP 2: traefik config ───────────────────
log "STEP 2: traefik config"
kubectl apply -f platform/traefik/traefik-config.yaml

# ─── STEP 3: ArgoCD ───────────────────────────
log "STEP 3: ArgoCD"
bash platform/argocd/install.sh
kubectl apply -f platform/argocd/root-app.yaml

# ─── STEP 4: Vault ────────────────────────────
log "STEP 4: Vault - deploy and unseal"
kubectl apply -f secrets/vault/vault-app.yaml

echo "Waiting for ArgoCD to sync vault application..."
kubectl wait application/vault \
  --namespace argocd \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=300s 2>/dev/null || true
echo "Waiting for vault pod to be ready..."
kubectl wait pod \
  --selector app.kubernetes.io/name=vault \
  --namespace vault \
  --for=condition=Ready \
  --timeout=300s

bash secrets/vault/unseal-init.sh

# ─── STEP 5: data layer ───────────────────────
log "STEP 5: data layer (postgres, mongodb, redis)"
bash scripts/deploy-data.sh

# ─── STEP 6: kafka, ipfs, scylla ─────────────
log "STEP 6: kafka, ipfs, scylla"
kubectl apply -f data/kafka/kafka-operator-app.yaml
echo "Waiting for Strimzi cluster operator to be ready..."
kubectl wait deployment/strimzi-cluster-operator \
  --namespace kafka \
  --for=condition=Available \
  --timeout=300s
kubectl apply -f data/kafka/kafka-cluster-app.yaml

kubectl apply -f data/ipfs/ipfs-app.yaml
kubectl apply -f data/scylla/scylla-app.yaml

# ─── STEP 7: chain (Paladin + Besu) ──────────
log "STEP 7: Paladin + Besu chain"
kubectl apply -f chain/paladin-app.yaml

echo "Waiting for Besu to produce blocks (max 5 min)..."
BESU_POD=""
for i in $(seq 1 30); do
  BESU_POD=$(kubectl get pod -n paladin -l app.kubernetes.io/name=besu --no-headers -o name 2>/dev/null | head -1 || true)
  if [[ -n "$BESU_POD" ]]; then
    break
  fi
  echo "  [$i/30] waiting for Besu pod to appear..."
  sleep 10
done

if [[ -z "$BESU_POD" ]]; then
  echo "ERROR: Besu pod not found after 5 min" >&2
  exit 1
fi

echo "Found Besu pod: $BESU_POD"
BLOCK_NUM=0
for i in $(seq 1 60); do
  BLOCK_HEX=$(kubectl exec -n paladin "$BESU_POD" -- \
    curl -sf -X POST http://localhost:8545 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" || echo "0x0")
  BLOCK_NUM=$(python3 -c "print(int('$BLOCK_HEX', 16))" 2>/dev/null || echo 0)
  echo "  [$i/60] block height: $BLOCK_NUM"
  if [[ "$BLOCK_NUM" -gt 0 ]]; then
    echo "  Besu is producing blocks."
    break
  fi
  sleep 5
done

if [[ "$BLOCK_NUM" -eq 0 ]]; then
  echo "ERROR: Besu still at block 0 after 60 attempts (5 min). Check paladin namespace." >&2
  exit 1
fi

# ─── STEP 8: smart contracts ─────────────────
log "STEP 8: deploy smart contracts"
bash scripts/deploy-contract.sh

# ─── STEP 9: FireFly middleware ───────────────
log "STEP 9: FireFly middleware"
kubectl apply -f middleware/firefly/signer-app.yaml
kubectl apply -f middleware/firefly/multiparty-app.yaml
kubectl apply -f middleware/firefly/evmconnect/evmconnect-app.yaml
kubectl apply -f middleware/firefly/dataexchange/dataexchange-app.yaml
kubectl apply -f middleware/firefly/ipfs-app.yaml
kubectl apply -f middleware/firefly/firefly-ingress-app.yaml
kubectl apply -f middleware/firefly/firefly-cors-middleware-app.yaml

# ─── STEP 10: monitoring ─────────────────────
log "STEP 10: monitoring"
kubectl apply -f platform/argocd/apps/monitoring.yaml
kubectl apply -f platform/argocd/apps/loki.yaml

# ─── Done ─────────────────────────────────────
log "BOOTSTRAP COMPLETE"
echo ""
echo "Verify commands:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -n paladin"
echo "  kubectl get pods -n firefly"
echo ""
echo "FireFly API:  https://firefly.${ORG_DOMAIN}/api/v1"
echo "FireFly UI:   https://firefly.${ORG_DOMAIN}/ui"
echo "Paladin UI:   https://paladin1.${ORG_DOMAIN}"
echo "ArgoCD:       https://argocd.${ORG_DOMAIN}"
echo ""
