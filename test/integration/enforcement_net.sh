#!/bin/bash
source "$(dirname "$0")/harness.sh"

# Offline profile: no network at all
set +e
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'wget -q -T 3 -O- https://example.com'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "dev-offline reached example.com"
pass "dev-offline has no network"

# Yolo-dev: registries allowed, other hosts blocked
set +e
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c 'wget -q -T 5 -O- https://example.com'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "yolo-dev reached example.com (should be blocked)"
pass "yolo-dev blocks non-allowlisted host"

# Allowlisted: should succeed
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c 'wget -q -T 10 -O- https://registry.terraform.io/.well-known/terraform.json' \
    || fail "yolo-dev could not reach allowlisted registry.terraform.io"
pass "yolo-dev allows registry.terraform.io"

# DNS: non-allowlisted names return 127.0.0.1 (via egress dnsmasq catch-all)
# Docker's embedded DNS forwards to the egress dnsmasq as upstream.
# nslookup output: "Address: 127.0.0.1" (no port) for catch-all responses.
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    # Extract first Address line where the value has no colon (no port suffix)
    addr=$(nslookup example.com 2>/dev/null | awk "/^Address:/{if (index(\$NF, \":\")==0) {print \$NF; exit}}")
    [ "$addr" = "127.0.0.1" ] || exit 1
' || fail "DNS: non-allowlisted name did not return 127.0.0.1"
pass "DNS: non-allowlisted names return 127.0.0.1"

echo "enforcement_net: all passed"
