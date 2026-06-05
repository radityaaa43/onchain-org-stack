#!/usr/bin/env bats
# Tests for scripts/render.sh
# Run: bats tests/render.bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RENDER_SH="$REPO_ROOT/scripts/render.sh"
FIXTURE_DEFAULT="$REPO_ROOT/tests/fixtures/config-default.yaml"
FIXTURE_CUSTOM="$REPO_ROOT/tests/fixtures/config-custom.yaml"

# ─── Helper: source render.sh with a given config ───────────────────────────
source_with_config() {
  local cfg="$1"
  CONFIG="$cfg" source "$RENDER_SH"
}

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
}

teardown() {
  rm -rf "$TMPDIR"
}

# ─── Env var export tests ────────────────────────────────────────────────────

@test "exports ORG_NAME from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$ORG_NAME" = "testorg" ]
}

@test "exports ORG_DOMAIN from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$ORG_DOMAIN" = "testorg.cluster.local" ]
}

@test "exports ORG_EMAIL from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$ORG_EMAIL" = "test@testorg.example" ]
}

@test "exports BESU_CHAIN_ID from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_CHAIN_ID" = "1337" ]
}

@test "exports BESU_NODE_COUNT from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_NODE_COUNT" = "1" ]
}

@test "exports BESU_BASE_NODE_PORT from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_BASE_NODE_PORT" = "31545" ]
}

@test "derives BESU_WS_PORT as baseNodePort plus 1" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_WS_PORT" = "31546" ]
}

@test "derives BESU_P2P_PORT as baseNodePort plus 2" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_P2P_PORT" = "31547" ]
}

@test "derives BESU_GRAPHQL_PORT as baseNodePort plus 3" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_GRAPHQL_PORT" = "31548" ]
}

@test "exports BESU_RPC_URL pointing to besu-node1 in paladin namespace" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$BESU_RPC_URL" = "http://besu-node1.paladin.svc:8545" ]
}

@test "exports PALADIN_BASE_PORT from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$PALADIN_BASE_PORT" = "31548" ]
}

@test "exports PALADIN_IMAGE_TAG from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$PALADIN_IMAGE_TAG" = "latest" ]
}

@test "exports ARCH from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$ARCH" = "amd64" ]
}

@test "exports CROSS_ORG_MODE from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$CROSS_ORG_MODE" = "standalone" ]
}

@test "exports REPO_URL from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$REPO_URL" = "https://github.com/testorg/onchain-org-stack" ]
}

@test "exports REPO_REVISION from config" {
  source_with_config "$FIXTURE_DEFAULT"
  [ "$REPO_REVISION" = "HEAD" ]
}

# ─── Custom config tests ─────────────────────────────────────────────────────

@test "custom config: chainId=2025 is exported correctly" {
  source_with_config "$FIXTURE_CUSTOM"
  [ "$BESU_CHAIN_ID" = "2025" ]
}

@test "custom config: nodeCount=3 is exported correctly" {
  source_with_config "$FIXTURE_CUSTOM"
  [ "$BESU_NODE_COUNT" = "3" ]
}

@test "custom config: baseNodePort=30000 derives ws=30001" {
  source_with_config "$FIXTURE_CUSTOM"
  [ "$BESU_BASE_NODE_PORT" = "30000" ]
  [ "$BESU_WS_PORT" = "30001" ]
}

@test "custom config: crossOrg mode shared-chain-group" {
  source_with_config "$FIXTURE_CUSTOM"
  [ "$CROSS_ORG_MODE" = "shared-chain-group" ]
}

@test "custom config: org name acme" {
  source_with_config "$FIXTURE_CUSTOM"
  [ "$ORG_NAME" = "acme" ]
}

# ─── Template rendering tests ────────────────────────────────────────────────

@test "--write renders tmpl.yaml to yaml without .tmpl in output filename" {
  # Create a temp dir with a minimal tmpl file
  local tmpdir="$(mktemp -d)"
  cp "$FIXTURE_DEFAULT" "$tmpdir/config.yaml"
  mkdir -p "$tmpdir/scripts"
  cp "$RENDER_SH" "$tmpdir/scripts/render.sh"
  # Create a simple template
  echo 'chainId: ${BESU_CHAIN_ID}' > "$tmpdir/test.tmpl.yaml"

  CONFIG="$tmpdir/config.yaml" REPO_ROOT="$tmpdir" bash "$tmpdir/scripts/render.sh" --write

  # Output file must exist
  [ -f "$tmpdir/test.yaml" ]
  # Template file still exists
  [ -f "$tmpdir/test.tmpl.yaml" ]
}

@test "--write replaces BESU_CHAIN_ID placeholder with actual value" {
  local tmpdir="$(mktemp -d)"
  cp "$FIXTURE_DEFAULT" "$tmpdir/config.yaml"
  mkdir -p "$tmpdir/scripts"
  cp "$RENDER_SH" "$tmpdir/scripts/render.sh"
  echo 'chainId: ${BESU_CHAIN_ID}' > "$tmpdir/test.tmpl.yaml"

  CONFIG="$tmpdir/config.yaml" REPO_ROOT="$tmpdir" bash "$tmpdir/scripts/render.sh" --write

  local rendered_value
  rendered_value="$(grep 'chainId' "$tmpdir/test.yaml" | awk '{print $2}')"
  [ "$rendered_value" = "1337" ]
}

@test "--write replaces ORG_NAME placeholder with actual value" {
  local tmpdir="$(mktemp -d)"
  cp "$FIXTURE_DEFAULT" "$tmpdir/config.yaml"
  mkdir -p "$tmpdir/scripts"
  cp "$RENDER_SH" "$tmpdir/scripts/render.sh"
  echo 'name: ${ORG_NAME}' > "$tmpdir/test.tmpl.yaml"

  CONFIG="$tmpdir/config.yaml" REPO_ROOT="$tmpdir" bash "$tmpdir/scripts/render.sh" --write

  local rendered_value
  rendered_value="$(grep 'name' "$tmpdir/test.yaml" | awk '{print $2}')"
  [ "$rendered_value" = "testorg" ]
}

@test "--write rendered file contains no remaining dollar-brace placeholders" {
  local tmpdir="$(mktemp -d)"
  cp "$FIXTURE_DEFAULT" "$tmpdir/config.yaml"
  mkdir -p "$tmpdir/scripts"
  cp "$RENDER_SH" "$tmpdir/scripts/render.sh"
  cat > "$tmpdir/all.tmpl.yaml" << 'EOF'
org: ${ORG_NAME}
domain: ${ORG_DOMAIN}
chainId: ${BESU_CHAIN_ID}
nodeCount: ${BESU_NODE_COUNT}
repoUrl: ${REPO_URL}
EOF

  CONFIG="$tmpdir/config.yaml" REPO_ROOT="$tmpdir" bash "$tmpdir/scripts/render.sh" --write

  # No unresolved placeholders (no ${...} remaining)
  ! grep -q '\${' "$tmpdir/all.yaml"
}

@test "--write with custom chainId=2025 renders 2025 not 1337" {
  local tmpdir="$(mktemp -d)"
  cp "$FIXTURE_CUSTOM" "$tmpdir/config.yaml"
  mkdir -p "$tmpdir/scripts"
  cp "$RENDER_SH" "$tmpdir/scripts/render.sh"
  echo 'chainId: ${BESU_CHAIN_ID}' > "$tmpdir/test.tmpl.yaml"

  CONFIG="$tmpdir/config.yaml" REPO_ROOT="$tmpdir" bash "$tmpdir/scripts/render.sh" --write

  local rendered_value
  rendered_value="$(grep 'chainId' "$tmpdir/test.yaml" | awk '{print $2}')"
  [ "$rendered_value" = "2025" ]
}

@test "fails with non-zero exit when config.yaml missing" {
  local tmpdir="$(mktemp -d)"
  CONFIG="$tmpdir/config.yaml" REPO_ROOT="$tmpdir" run bash "$RENDER_SH"
  [ "$status" -ne 0 ]
}
