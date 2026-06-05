#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/render.sh
source "${SCRIPT_DIR}/render.sh"

echo "================================================"
echo " Deploy Data Layer"
echo "================================================"

# Postgres secret
bash "${ROOT_DIR}/data/postgres/create-secret.sh"

# Add bitnami repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Postgres
helm upgrade --install postgres bitnami/postgresql \
  --namespace database \
  --create-namespace \
  --values "${ROOT_DIR}/data/postgres/postgres-values.yaml" \
  --wait --timeout 300s

# MongoDB
helm upgrade --install mongodb bitnami/mongodb \
  --namespace database \
  --create-namespace \
  --values "${ROOT_DIR}/data/mongodb/mongodb-values.yaml" \
  --wait --timeout 300s

# Redis
helm upgrade --install redis bitnami/redis \
  --namespace database \
  --create-namespace \
  --values "${ROOT_DIR}/data/redis/redis-values.yaml" \
  --wait --timeout 300s

echo "Data layer ready"
