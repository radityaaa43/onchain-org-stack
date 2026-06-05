#!/usr/bin/env bash
# check-prereqs.sh — verify required tools are installed

set -uo pipefail

MISSING=0

check() {
  local label="$1"
  local ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "OK      $label"
  else
    echo "MISSING $label"
    MISSING=1
  fi
}

command -v kubectl &>/dev/null && check "kubectl" 1 || check "kubectl" 0
command -v helm    &>/dev/null && check "helm"    1 || check "helm"    0
command -v python3 &>/dev/null && check "python3" 1 || check "python3" 0
command -v git     &>/dev/null && check "git"     1 || check "git"     0

if command -v python3 &>/dev/null; then
  python3 -c "import yaml" 2>/dev/null && check "pyyaml (python)" 1 || check "pyyaml (python)" 0
else
  check "pyyaml (python)" 0
fi

if [[ "$MISSING" -eq 1 ]]; then
  echo ""
  echo "ERROR: one or more prerequisites missing."
  exit 1
fi

echo ""
echo "All prerequisites OK."
