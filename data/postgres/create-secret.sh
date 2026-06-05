#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=database
SECRET_NAME=postgres-credentials

# Create namespace if not exists
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

# Generate password if not set
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
  POSTGRES_PASSWORD="$(openssl rand -base64 20 | tr -dc 'A-Za-z0-9' | head -c 20)"
fi
export POSTGRES_PASSWORD

# Create/update secret
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=postgres-password="$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Append to .env.local
echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> .env.local

echo "Secret '${SECRET_NAME}' applied in namespace '${NAMESPACE}'."
