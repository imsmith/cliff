#!/bin/bash
source "$(dirname "$0")/harness.sh"

# No host cred directory ever appears in a container
set +e
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'ls /host 2>/dev/null; test -e /host'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "/host is visible in container"
pass "/host not mounted"

# No ~/.aws in any profile without creds
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    test ! -e /home/devuser/.aws
' || fail "yolo-dev has ~/.aws (should not)"
pass "yolo-dev has no AWS creds"

# /run/creds exists but is empty for no-creds profile
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    test -d /run/creds && [ -z "$(ls -A /run/creds)" ]
' || fail "/run/creds not empty for yolo-dev"
pass "/run/creds is empty absent cred declarations"

echo "enforcement_creds: all passed"
