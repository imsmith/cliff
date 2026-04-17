#!/bin/sh
set -eu

: "${CLIFF_ALLOWLIST:=}"  # newline-separated host:port patterns

# Render dnsmasq config: real resolution for allowlisted hosts, 127.0.0.1 for everything else.
cat > /etc/dnsmasq.conf <<EOF
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
    printf 'server=/%s/1.1.1.1\n' "$host" >> /etc/dnsmasq.conf
done

dnsmasq -k &
exec mitmdump --mode regular@3128 \
    --set confdir=/etc/mitmproxy \
    -s /opt/cliff/mitmproxy-addon.py
