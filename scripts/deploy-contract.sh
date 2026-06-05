#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
export ROOT_DIR

# shellcheck source=scripts/render.sh
source "${SCRIPT_DIR}/render.sh"

BESU_RPC="${BESU_RPC:-http://besu-node1.paladin.svc:8545}"
export BESU_RPC
PF_PID=""

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Try port-forward if running outside cluster
if ! curl -sf --max-time 3 "${BESU_RPC}" -X POST \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' >/dev/null 2>&1; then
  echo "In-cluster RPC unreachable, starting port-forward..."
  kubectl port-forward -n paladin svc/besu-node1 18545:8545 &
  PF_PID=$!
  BESU_RPC="http://localhost:18545"
  export BESU_RPC
  for _i in $(seq 1 15); do
    if curl -sf --max-time 2 "http://localhost:18545" -X POST \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

# Verify chain is producing blocks
BLOCK_HEX=$(curl -sf --max-time 10 "${BESU_RPC}" -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])")

if [[ "${BLOCK_HEX}" == "null" || -z "${BLOCK_HEX}" ]]; then
  echo "ERROR: eth_blockNumber returned null — chain not started or RPC error" >&2
  exit 1
fi

BLOCK_NUM=$(python3 -c "print(int('${BLOCK_HEX}', 16))")
if [[ "${BLOCK_NUM}" -le 0 ]]; then
  echo "ERROR: chain not producing blocks (blockNumber=${BLOCK_NUM})" >&2
  exit 1
fi
echo "Chain OK — current block: ${BLOCK_NUM}"

# Compile and deploy Firefly.sol via python3
CONTRACT_ADDR=$(python3 - <<'PYEOF'
import sys, os, json

try:
    from solcx import compile_files, install_solc
    from web3 import Web3
except ImportError:
    print("ERROR: py-solc-x and web3 required (pip install py-solc-x web3)", file=sys.stderr)
    sys.exit(1)

BESU_RPC = os.environ["BESU_RPC"]
ROOT_DIR = os.environ["ROOT_DIR"]
CONTRACTS_DIR = os.path.join(ROOT_DIR, "fireflycontracts")

install_solc("0.8.19", show_progress=False)

compiled = compile_files(
    [os.path.join(CONTRACTS_DIR, "Firefly.sol")],
    output_values=["abi", "bin"],
    solc_version="0.8.19",
    import_remappings=[f"{CONTRACTS_DIR}={CONTRACTS_DIR}"],
)

key = [k for k in compiled if "Firefly" in k and "IBatchPin" not in k][0]
abi = compiled[key]["abi"]
bytecode = compiled[key]["bin"]

w3 = Web3(Web3.HTTPProvider(BESU_RPC))
assert w3.is_connected(), "Cannot connect to Besu RPC"

# Deployer account
if w3.eth.accounts:
    deployer = w3.eth.accounts[0]
    tx_params = {"from": deployer}
else:
    # Well-known Besu dev key
    dev_key = "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
    account = w3.eth.account.from_key(dev_key)
    deployer = account.address
    tx_params = {}

Contract = w3.eth.contract(abi=abi, bytecode=bytecode)
nonce = w3.eth.get_transaction_count(deployer)
build_tx = Contract.constructor().build_transaction({
    **tx_params,
    "nonce": nonce,
    "gas": 3000000,
    "chainId": int(os.environ.get("BESU_CHAIN_ID", "1337")),
})

if w3.eth.accounts:
    tx_hash = w3.eth.send_transaction(build_tx)
else:
    dev_key = "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
    account = w3.eth.account.from_key(dev_key)
    signed = account.sign_transaction(build_tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)

receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
assert receipt.status == 1, f"Deploy tx failed: {receipt}"
print(receipt.contractAddress)
PYEOF
)

if [[ -z "${CONTRACT_ADDR}" ]]; then
  echo "ERROR: no contract address returned" >&2
  exit 1
fi

echo "Deployed FireFly contract: ${CONTRACT_ADDR}"

# Save to .env.local
ENV_LOCAL="${ROOT_DIR}/.env.local"
if grep -q "^FIREFLY_CONTRACT_ADDR=" "${ENV_LOCAL}" 2>/dev/null; then
  sed -i "s|^FIREFLY_CONTRACT_ADDR=.*|FIREFLY_CONTRACT_ADDR=${CONTRACT_ADDR}|" "${ENV_LOCAL}"
else
  echo "FIREFLY_CONTRACT_ADDR=${CONTRACT_ADDR}" >> "${ENV_LOCAL}"
fi

# Patch YAML manifests
for f in \
  "${ROOT_DIR}/middleware/firefly/firefly-config.yaml" \
  "${ROOT_DIR}/middleware/firefly/multiparty-app.yaml"; do
  if [[ -f "${f}" ]]; then
    if grep -q "PLACEHOLDER_CONTRACT_ADDR" "${f}"; then
      sed -i "s|PLACEHOLDER_CONTRACT_ADDR|${CONTRACT_ADDR}|g" "${f}"
      echo "Patched ${f}"
    else
      echo "Already patched (or no placeholder): ${f}"
    fi
  fi
done

echo "Contract address: ${CONTRACT_ADDR}"
