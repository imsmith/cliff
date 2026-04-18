#!/bin/bash
source "$(dirname "$0")/harness.sh"

# Workspace read-only: writes to /workspace under an ro profile fail.
echo "seed" > "$FIXDIR/file"
set +e
"$CLIFF" exec obsv-local --project="$FIXDIR" -- sh -c 'echo mutate > /workspace/file'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "workspace ro: write should have failed, rc=$rc"
grep -q "^seed$" "$FIXDIR/file" || fail "workspace ro: fixture mutated"
pass "workspace ro mount rejects writes"

# Persistence: home is tmpfs — files don't survive across sessions.
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'touch /home/devuser/marker'
if "$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'test -f /home/devuser/marker'; then
    fail "home persisted across sessions"
fi
pass "home tmpfs is ephemeral"

# Read-only rootfs: writes to /etc fail.
set +e
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'touch /etc/should-not-exist'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "read-only rootfs: /etc write should have failed"
pass "rootfs is read-only"

echo "enforcement_fs: all passed"
