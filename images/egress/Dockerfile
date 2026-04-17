FROM alpine:3.19

RUN apk add --no-cache dnsmasq py3-pip ca-certificates \
        gcc musl-dev python3-dev openssl-dev rust cargo \
 && pip3 install --break-system-packages mitmproxy==10.2.* \
 && apk del gcc musl-dev python3-dev openssl-dev rust cargo

RUN mkdir -p /etc/mitmproxy /opt/cliff

# Bake cliff CA so app containers trust the egress proxy.
# mitmproxy-ca.pem must be key + cert concatenated (mitmproxy's expected format).
COPY images/ca/cliff-egress.crt /etc/mitmproxy/mitmproxy-ca-cert.pem
COPY images/ca/cliff-egress.key /tmp/cliff-egress.key
RUN cat /tmp/cliff-egress.key /etc/mitmproxy/mitmproxy-ca-cert.pem \
    > /etc/mitmproxy/mitmproxy-ca.pem \
 && rm /tmp/cliff-egress.key

COPY images/egress/mitmproxy-addon.py /opt/cliff/mitmproxy-addon.py
COPY images/egress/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 53/udp
ENTRYPOINT ["/entrypoint.sh"]
