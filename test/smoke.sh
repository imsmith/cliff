#!/usr/bin/env bash
set -euo pipefail

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

echo "--- cliff/base ---"
check cliff/base "bash"            "bash --version"
check cliff/base "fish"            "fish --version"
check cliff/base "curl"            "curl --version"
check cliff/base "git"             "git --version"
check cliff/base "jq"              "jq --version"
check cliff/base "yq"              "yq --version"
check cliff/base "tmux"            "tmux -V"
check cliff/base "sqlite3"         "sqlite3 --version"
check cliff/base "wireguard (wg)"  "wg --version 2>&1 || wg help 2>&1"
check cliff/base "elixir"          "elixir --version"
check cliff/base "erl"             "erl -eval 'halt()' -noshell"
check cliff/base "tclsh"           "echo 'puts ok' | tclsh"
check cliff/base "devuser exists"  "id devuser"
echo ""

echo "--- cliff/dev ---"
check cliff/dev "terraform"   "terraform version"
check cliff/dev "vault"       "vault version"
check cliff/dev "packer"      "packer version"
check cliff/dev "kubectl"     "kubectl version --client"
check cliff/dev "helm"        "helm version"
check cliff/dev "ansible"     "ansible --version"
check cliff/dev "aws"         "aws --version"
check cliff/dev "gcloud"      "gcloud version"
check cliff/dev "step"        "step version"
check cliff/dev "wrangler"    "wrangler --version"
echo ""

echo "--- cliff/obsv ---"
check cliff/obsv "prometheus"  "prometheus --version 2>&1"
check cliff/obsv "promtool"    "promtool --version 2>&1"
check cliff/obsv "loki"        "loki --version 2>&1 || loki -version 2>&1"
check cliff/obsv "logcli"      "logcli --version 2>&1"
check cliff/obsv "vector"      "vector --version"
check cliff/obsv "psql"        "psql --version"
echo ""

echo "--- cliff/full ---"
check cliff/full "terraform"   "terraform version"
check cliff/full "prometheus"  "prometheus --version 2>&1"
check cliff/full "vector"      "vector --version"
check cliff/full "psql"        "psql --version"
check cliff/full "elixir"      "elixir --version"
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
