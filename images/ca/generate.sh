#!/bin/sh
set -eu
DIR=$(dirname "$0")
if [ -f "$DIR/cliff-egress.crt" ] && [ -f "$DIR/cliff-egress.key" ]; then
    echo "CA already present; delete files to regenerate"; exit 0
fi
openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$DIR/cliff-egress.key" \
    -out "$DIR/cliff-egress.crt" \
    -days 3650 \
    -subj "/CN=cliff-egress-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
chmod 600 "$DIR/cliff-egress.key"
echo "Generated $DIR/cliff-egress.{crt,key}"
