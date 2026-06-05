#!/usr/bin/env bash
set -Eeuo pipefail

NS=${VAULT_NAMESPACE:-vault}
VAULT_ADDR_INTERNAL=${VAULT_ADDR:-"http://127.0.0.1:8200"}
KEYS_FILE="vault-keys.json"

echo "[INFO] Getting vault pod in namespace: $NS"
POD=$(kubectl get pods -l app.kubernetes.io/name=vault -n "$NS" \
  -o custom-columns=":metadata.name" --no-headers 2>/dev/null | head -1)

if [ -z "$POD" ]; then
  echo "[ERROR] No vault pod found in namespace $NS" >&2
  exit 1
fi
echo "[INFO] Found pod: $POD"

echo "[INFO] Initializing vault (1 key share, threshold 1)..."
kubectl exec "$POD" -n "$NS" -- sh -c \
  "VAULT_ADDR=$VAULT_ADDR_INTERNAL vault operator init -key-shares=1 -key-threshold=1 -format=json" \
  > "$KEYS_FILE"

echo "[INFO] Saved keys to $KEYS_FILE"

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$KEYS_FILE")
ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")

echo "[INFO] Unsealing vault..."
kubectl exec "$POD" -n "$NS" -- sh -c \
  "VAULT_ADDR=$VAULT_ADDR_INTERNAL vault operator unseal $UNSEAL_KEY"

export ROOT_TOKEN
echo ""
echo "[INFO] Vault initialized and unsealed."
echo "[INFO] Root token exported as ROOT_TOKEN"
echo ""
echo "  VAULT_TOKEN=$ROOT_TOKEN"
echo ""
echo "Next steps:"
echo "  1. Store $KEYS_FILE in a secure location."
echo "  2. Set VAULT_TOKEN=\$ROOT_TOKEN before running vault CLI commands."
echo "  3. Run: kubectl exec $POD -n $NS -- sh -c 'VAULT_ADDR=$VAULT_ADDR_INTERNAL VAULT_TOKEN=$ROOT_TOKEN vault status'"
