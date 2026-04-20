#!/bin/bash
source "$(dirname "$0")/harness.sh"

"$CLIFF" list | grep -q "^base " || fail "list did not include base"
pass "cliff list"

"$CLIFF" describe base | grep -q "image: cliff-base" || fail "describe base malformed"
pass "cliff describe"

"$CLIFF" exec dev-offline --project="$FIXDIR" -- true
sid=$("$CLIFF" sessions | tail -1 | awk '{print $1}')
[ -n "$sid" ] || fail "no session id captured"
"$CLIFF" session "$sid" | grep -q "=== profile.tcl ===" || fail "session <id> missing sections"
pass "cliff sessions + session <id>"

echo "lifecycle: all passed"
