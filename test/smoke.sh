#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/imsmith}"
PASS=0
FAIL=0
SKIP=0

check() {
  local image="$1"
  local label="$2"
  local cmd="$3"

  if ! docker image inspect "$image" &>/dev/null; then
    echo "  SKIP  $label (image $image not found)"
    SKIP=$((SKIP + 1))
    return
  fi

  if docker run --rm "$image" sh -c "$cmd" &>/dev/null; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Cliff Smoke Tests ==="
echo ""

echo "--- ${REGISTRY}/cliff-base ---"
check ${REGISTRY}/cliff-base "bash"            "bash --version"
check ${REGISTRY}/cliff-base "fish"            "fish --version"
check ${REGISTRY}/cliff-base "curl"            "curl --version"
check ${REGISTRY}/cliff-base "git"             "git --version"
check ${REGISTRY}/cliff-base "jq"              "jq --version"
check ${REGISTRY}/cliff-base "yq"              "yq --version"
check ${REGISTRY}/cliff-base "tmux"            "tmux -V"
check ${REGISTRY}/cliff-base "sqlite3"         "sqlite3 --version"
check ${REGISTRY}/cliff-base "wireguard (wg)"  "wg --version 2>&1 || wg help 2>&1"
check ${REGISTRY}/cliff-base "elixir"          "elixir --version"
check ${REGISTRY}/cliff-base "erl"             "erl -eval 'halt()' -noshell"
check ${REGISTRY}/cliff-base "tclsh"           "echo 'puts ok' | tclsh"
check ${REGISTRY}/cliff-base "devuser exists"  "id devuser"
echo ""

echo "--- ${REGISTRY}/cliff-dev ---"
check ${REGISTRY}/cliff-dev "terraform"   "terraform version"
check ${REGISTRY}/cliff-dev "vault"       "vault version"
check ${REGISTRY}/cliff-dev "packer"      "packer version"
check ${REGISTRY}/cliff-dev "kubectl"     "kubectl version --client"
check ${REGISTRY}/cliff-dev "helm"        "helm version"
check ${REGISTRY}/cliff-dev "ansible"     "ansible --version"
check ${REGISTRY}/cliff-dev "aws"         "aws --version"
check ${REGISTRY}/cliff-dev "gcloud"      "gcloud version"
check ${REGISTRY}/cliff-dev "step"        "step version"
check ${REGISTRY}/cliff-dev "wrangler"    "wrangler --version"
echo ""

echo "--- ${REGISTRY}/cliff-obsv ---"
check ${REGISTRY}/cliff-obsv "prometheus"  "prometheus --version 2>&1"
check ${REGISTRY}/cliff-obsv "promtool"    "promtool --version 2>&1"
check ${REGISTRY}/cliff-obsv "loki"        "loki --version 2>&1 || loki -version 2>&1"
check ${REGISTRY}/cliff-obsv "logcli"      "logcli --version 2>&1"
check ${REGISTRY}/cliff-obsv "vector"      "vector --version"
check ${REGISTRY}/cliff-obsv "psql"        "psql --version"
echo ""

echo "--- ${REGISTRY}/cliff-full ---"
check ${REGISTRY}/cliff-full "terraform"   "terraform version"
check ${REGISTRY}/cliff-full "prometheus"  "prometheus --version 2>&1"
check ${REGISTRY}/cliff-full "vector"      "vector --version"
check ${REGISTRY}/cliff-full "psql"        "psql --version"
check ${REGISTRY}/cliff-full "elixir"      "elixir --version"
echo ""

echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
