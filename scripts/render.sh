#!/usr/bin/env bash
# render.sh — parse config.yaml and export env vars
# Usage:
#   source scripts/render.sh          # export vars into current shell
#   bash scripts/render.sh --write    # render all *.tmpl.yaml files

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/config.yaml"

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found. Install python3 and PyYAML." >&2
  exit 1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
  echo "ERROR: PyYAML not found. Run: pip3 install pyyaml" >&2
  exit 1
fi

# Parse config.yaml and emit KEY=VALUE lines
_parse_config() {
  python3 - "$CONFIG" <<'PYEOF'
import sys, yaml

with open(sys.argv[1]) as f:
    c = yaml.safe_load(f)

org    = c.get("org", {})
repo   = c.get("repo", {})
besu   = c.get("besu", {})
paladin = c.get("paladin", {})
cross  = c.get("crossOrg", {})

base  = int(besu.get("baseNodePort", 31545))
pbase = int(paladin.get("baseNodePort", 31548))

pairs = [
    ("ORG_NAME",              org.get("name", "")),
    ("ORG_DOMAIN",            org.get("domain", "")),
    ("ORG_EMAIL",             org.get("email", "")),
    ("ARCH",                  c.get("arch", "amd64")),
    ("BESU_CHAIN_ID",         str(besu.get("chainId", 1337))),
    ("BESU_NODE_COUNT",       str(besu.get("nodeCount", 1))),
    ("BESU_BASE_NODE_PORT",   str(base)),
    ("BESU_WS_PORT",          str(base + 1)),
    ("BESU_P2P_PORT",         str(base + 2)),
    ("BESU_GRAPHQL_PORT",     str(base + 3)),
    ("BESU_RPC_URL",          "http://besu-node1.paladin.svc:8545"),
    ("BESU_BLOCK_PERIOD",     str(besu.get("blockPeriodSeconds", 1))),
    ("BESU_ZERO_BASE_FEE",    str(besu.get("zeroBaseFee", True)).lower()),
    ("BESU_EVM_FORK",         besu.get("evmFork", "cancun")),
    ("BESU_IMAGE_TAG",        besu.get("imageTag", "latest")),
    ("PALADIN_BASE_PORT",     str(pbase)),
    ("PALADIN_IMAGE_TAG",     paladin.get("imageTag", "latest")),
    ("CROSS_ORG_MODE",        cross.get("mode", "standalone")),
    ("REPO_URL",              repo.get("url", "")),
    ("REPO_REVISION",         repo.get("revision", "HEAD")),
]

for k, v in pairs:
    print(f"{k}={v}")
PYEOF
}

# Export all vars into current shell
_export_vars() {
  while IFS='=' read -r key val; do
    export "$key=$val"
  done < <(_parse_config)
}

_export_vars

if [[ "${1:-}" == "--write" ]]; then
  echo "Rendering templates in $REPO_ROOT ..."
  while IFS= read -r -d '' tmpl; do
    out="${tmpl%.tmpl}"
    echo "  $tmpl -> $out"
    # Replace ${VARNAME} placeholders
    content="$(cat "$tmpl")"
    # Use python3 for reliable substitution
    python3 - "$tmpl" "$out" <<'PYEOF'
import sys, os, re

tmpl_path = sys.argv[1]
out_path  = sys.argv[2]

with open(tmpl_path) as f:
    text = f.read()

def replacer(m):
    var = m.group(1)
    return os.environ.get(var, m.group(0))

result = re.sub(r'\$\{([A-Z_][A-Z0-9_]*)\}', replacer, text)

with open(out_path, "w") as f:
    f.write(result)
PYEOF
  done < <(find "$REPO_ROOT" -name "*.tmpl.yaml" -print0)
  echo "Done rendering."
fi
