#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/render.sh
source "${SCRIPT_DIR}/render.sh"

CROSS_ORG_MODE="${CROSS_ORG_MODE:-}"

if [[ "${CROSS_ORG_MODE}" != "shared-chain-group" ]]; then
  echo "ERROR: crossOrg.mode must be 'shared-chain-group', got '${CROSS_ORG_MODE}'" >&2
  exit 1
fi

PEER_ENODE="${1:-}"
PEER_NAME="${2:-}"

if [[ -z "${PEER_ENODE}" || -z "${PEER_NAME}" ]]; then
  echo "Usage: $0 <peer-enode-url> <peer-name>" >&2
  exit 1
fi

echo "Adding peer ${PEER_NAME} to besu-node1..."

kubectl exec -n paladin deploy/besu-node1 -- \
  curl -sf -X POST \
    -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"${PEER_ENODE}\"],\"id\":1}" \
    http://localhost:8545

echo "Peer ${PEER_NAME} added."
echo ""
echo "Verify with:"
echo "  kubectl exec -n paladin deploy/besu-node1 -- curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"admin_peers\",\"params\":[],\"id\":1}' http://localhost:8545 | python3 -m json.tool"
