#!/bin/sh
set -eu

: "${CLIFF_ALLOWLIST:=}"  # newline-separated host:port patterns

# Render dnsmasq config to /tmp (writable even with --read-only rootfs).
cat > /tmp/dnsmasq.conf <<EOF
no-hosts
no-resolv
server=1.1.1.1
server=8.8.8.8
address=/#/127.0.0.1
EOF

echo "$CLIFF_ALLOWLIST" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    host="${line%:*}"
    # Let dnsmasq resolve allowlisted hosts normally
    printf 'server=/%s/1.1.1.1\n' "$host" >> /tmp/dnsmasq.conf
done

dnsmasq -k -C /tmp/dnsmasq.conf --pid-file=/tmp/dnsmasq.pid &

# Copy mitmproxy CA into /tmp so it can write dhparam and other runtime files.
mkdir -p /tmp/mitmproxy
cp /etc/mitmproxy/mitmproxy-ca.pem /tmp/mitmproxy/mitmproxy-ca.pem
cp /etc/mitmproxy/mitmproxy-ca-cert.pem /tmp/mitmproxy/mitmproxy-ca-cert.pem

export PYTHONUNBUFFERED=1
exec mitmdump --mode regular@3128 \
    --set confdir=/tmp/mitmproxy \
    -s /opt/cliff/mitmproxy-addon.py \
    >> /opt/cliff/log/egress.log 2>&1
