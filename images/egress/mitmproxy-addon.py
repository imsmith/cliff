"""Cliff egress addon: enforce host:port allowlist from $CLIFF_ALLOWLIST."""
import os
import fnmatch
from mitmproxy import http, ctx

def load_allowlist():
    raw = os.environ.get("CLIFF_ALLOWLIST", "")
    entries = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        host, _, port = line.rpartition(":")
        entries.append((host, int(port)))
    return entries

ALLOW = load_allowlist()

def _allowed(host: str, port: int) -> bool:
    return any(fnmatch.fnmatch(host, h) and p == port for h, p in ALLOW)

def http_connect(flow: http.HTTPFlow):
    host = flow.request.host
    port = flow.request.port
    if not _allowed(host, port):
        ctx.log.warn(f"DENY CONNECT {host}:{port}")
        flow.response = http.Response.make(403, b"cliff egress: host not allowlisted")
        return
    ctx.log.info(f"ALLOW CONNECT {host}:{port}")

def request(flow: http.HTTPFlow):
    host = flow.request.host
    port = flow.request.port
    if not _allowed(host, port):
        ctx.log.warn(f"DENY {flow.request.method} {host}:{port}{flow.request.path}")
        flow.response = http.Response.make(403, b"cliff egress: host not allowlisted")
        return
    ctx.log.info(f"ALLOW {flow.request.method} {host}:{port}{flow.request.path}")
