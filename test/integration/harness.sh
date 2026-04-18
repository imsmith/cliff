#!/bin/bash
# Sourced by each enforcement test.
set -eu
CLIFF="${CLIFF:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/cliff}"
FIXDIR="$(mktemp -d)"
trap 'rm -rf "$FIXDIR"' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
assert_exit() {
    local want=$1; shift
    local got
    set +e
    "$@" >/dev/null 2>&1
    got=$?
    set -e
    if [ "$got" -ne "$want" ]; then
        fail "expected exit $want, got $got: $*"
    fi
}
