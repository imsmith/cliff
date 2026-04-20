#!/bin/bash
source "$(dirname "$0")/harness.sh"

# Fork bomb hits pids limit (yolo-dev is 512)
set +e
timeout 10 "$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    i=0
    while [ $i -lt 2000 ]; do
        sh -c "sleep 30" &
        i=$((i+1))
    done
'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "fork bomb unrestricted"
pass "pids limit caps process count"

# Non-root uid
uid=$("$CLIFF" exec yolo-dev --project="$FIXDIR" -- id -u)
[ "$uid" != "0" ] || fail "container running as root"
pass "container runs as non-root"

echo "enforcement_limits: all passed"
