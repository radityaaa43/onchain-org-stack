#!/usr/bin/env bash
# Helm template tests for onchain-org-stack
# Run: bash tests/helm_test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

pass() { echo "ok $((PASS+FAIL+1)) $1"; PASS=$((PASS+1)); }
fail() { echo "not ok $((PASS+FAIL+1)) $1"; echo "  # $2"; FAIL=$((FAIL+1)); }

run_test() {
  local name="$1"; local fn="$2"
  if $fn 2>/dev/null; then pass "$name"; else fail "$name" "assertion failed"; fi
}

# ─── chain/ Helm chart tests ─────────────────────────────────────────────────

_chain_template() {
  local extra_args=("$@")
  helm template test-release "$REPO_ROOT/chain" \
    --set "org.name=testorg" \
    --set "org.domain=testorg.cluster.local" \
    --set "besu.chainId=1337" \
    --set "besu.nodeCount=1" \
    --set "besu.imageTag=latest" \
    --set "besu.baseNodePort=31545" \
    --set "besu.blockPeriod=1" \
    --set "besu.zeroBaseFee=true" \
    --set "besu.evmFork=cancun" \
    --set "paladin.imageTag=latest" \
    --set "paladin.baseNodePort=31548" \
    --set "paladin.domains.noto=true" \
    --set "paladin.domains.zeto=true" \
    --set "paladin.domains.pente=true" \
    "${extra_args[@]}" 2>&1
}

test_ingress_nodecount1_generates_1_ingressroute() {
  local out
  out="$(_chain_template --set besu.nodeCount=1)"
  local count
  count="$(echo "$out" | grep -c 'kind: IngressRoute' || true)"
  [[ "$count" -eq 2 ]]  # 1 node → paladin1-ingress + paladin1-ui-ingress = 2
}

test_ingress_nodecount3_generates_6_ingressroutes() {
  local out
  out="$(_chain_template --set besu.nodeCount=3)"
  local count
  count="$(echo "$out" | grep -c 'kind: IngressRoute' || true)"
  [[ "$count" -eq 6 ]]  # 3 nodes × 2 routes each = 6
}

test_ingress_uses_template_namespace_not_hardcoded() {
  local out
  out="$(_chain_template)"
  # Must NOT contain hardcoded 'paladin' as literal namespace value
  # (should be rendered as the release namespace, i.e. 'default' in test context or parameterized)
  # The template uses {{ $.Release.Namespace }} — in helm template it renders as 'default' or --namespace value
  # Key: it should NOT contain 'namespace: paladin' as a hardcoded string in the source template
  ! grep -q 'namespace: paladin' "$REPO_ROOT/chain/templates/ingress.yaml"
}

test_ingress_node1_name_contains_1() {
  local out
  out="$(_chain_template --set besu.nodeCount=1)"
  echo "$out" | grep -q 'name: paladin1-ingress'
}

test_ingress_node3_contains_paladin3() {
  local out
  out="$(_chain_template --set besu.nodeCount=3)"
  echo "$out" | grep -q 'name: paladin3-ingress'
}

test_ingress_uses_org_domain_in_host() {
  local out
  out="$(_chain_template --set org.domain=myorg.example.com)"
  echo "$out" | grep -q 'myorg.example.com'
}

test_paladin_cr_has_chainid_from_values() {
  local out
  out="$(_chain_template --set besu.chainId=9999)"
  echo "$out" | grep -q 'chainID: 9999'
}

test_paladin_cr_uses_nodecount_from_values() {
  local out
  out="$(_chain_template --set besu.nodeCount=2)"
  echo "$out" | grep -q 'nodeCount: 2'
}

test_paladin_cr_has_amd64_nodeselector_not_arm64() {
  local out
  out="$(_chain_template)"
  # Must have amd64 arch
  echo "$out" | grep -q 'amd64'
  # Must NOT have arm64
  ! echo "$out" | grep -q 'arm64'
}

test_paladin_cr_uses_paladin_image_tag_from_values() {
  local out
  out="$(_chain_template --set paladin.imageTag=v0.0.12)"
  echo "$out" | grep -q 'v0.0.12'
}

# ─── data/kafka/ Helm chart tests ────────────────────────────────────────────

_kafka_template() {
  helm template test-kafka "$REPO_ROOT/data/kafka" \
    --set "kafka.replicas=1" \
    --set "kafka.storage=8Gi" \
    --set "kafka.version=3.9.0" \
    "$@" 2>&1
}

test_kafka_namespace_not_hardcoded_in_template_source() {
  # The template source must use {{ .Release.Namespace }} not literal 'kafka'
  ! grep -q 'namespace: kafka' "$REPO_ROOT/data/kafka/templates/kafka-cluster.yaml"
}

test_kafka_template_renders_without_error() {
  _kafka_template >/dev/null
}

test_kafka_uses_release_namespace_in_rendered_output() {
  local out
  out="$(_kafka_template --namespace kafka-dev)"
  echo "$out" | grep -q 'namespace: kafka-dev'
}

# ─── Run all tests ────────────────────────────────────────────────────────────

echo "1..13"

run_test "chain ingress nodeCount=1 generates 2 IngressRoutes (1 node × 2)" test_ingress_nodecount1_generates_1_ingressroute
run_test "chain ingress nodeCount=3 generates 6 IngressRoutes (3 nodes × 2)" test_ingress_nodecount3_generates_6_ingressroutes
run_test "chain ingress template uses Release.Namespace not hardcoded paladin" test_ingress_uses_template_namespace_not_hardcoded
run_test "chain ingress node 1 has name paladin1-ingress" test_ingress_node1_name_contains_1
run_test "chain ingress nodeCount=3 renders paladin3-ingress" test_ingress_node3_contains_paladin3
run_test "chain ingress uses org.domain in Host match" test_ingress_uses_org_domain_in_host
run_test "chain paladin CR has chainID from values (9999)" test_paladin_cr_has_chainid_from_values
run_test "chain paladin CR uses nodeCount from values" test_paladin_cr_uses_nodecount_from_values
run_test "chain paladin CR has amd64 nodeSelector not arm64" test_paladin_cr_has_amd64_nodeselector_not_arm64
run_test "chain paladin CR uses paladin.imageTag from values" test_paladin_cr_uses_paladin_image_tag_from_values
run_test "kafka namespace not hardcoded in template source" test_kafka_namespace_not_hardcoded_in_template_source
run_test "kafka Helm chart renders without error" test_kafka_template_renders_without_error
run_test "kafka rendered output uses --namespace value not literal" test_kafka_uses_release_namespace_in_rendered_output

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
