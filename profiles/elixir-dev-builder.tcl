inherit base
describe "Dev image, egress to Hex/GitHub/Alpine for mix deps.get and apk add"
image    cliff-dev:0.3.0
workspace mode=rw
home      mode=tmpfs size=1g

# No cloud creds. This profile is for fetching build dependencies, not
# touching cloud APIs. Pair with a separate session for deploys.

egress {
    # Hex package registry + tarballs
    allow repo.hex.pm:443
    allow builds.hex.pm:443
    allow s3.amazonaws.com:443
    allow s3.hex.pm:443

    # GitHub source deps ({:foo, github: "..."} in mix.exs)
    allow github.com:443
    allow api.github.com:443
    allow codeload.github.com:443
    allow objects.githubusercontent.com:443
    allow raw.githubusercontent.com:443

    # Alpine package repos for in-session `sudo apk add`
    allow dl-cdn.alpinelinux.org:443

    # rebar3 / hex_core occasionally pull from these
    allow s3.eu-central-1.amazonaws.com:443
}

limits { cpus 4; memory 6g; pids 1024 }

# Erlang/OTP doesn't read the OS CA trust store. Egress traffic transits
# the cliff-egress mitmproxy, which presents the cliff-egress CA — that
# CA is in /etc/ssl/certs system-wide, but Hex/Mix's :httpc won't see it
# unless pointed at the bundle explicitly.
env {
    HEX_CACERTS_PATH /etc/ssl/certs/ca-certificates.crt
    SSL_CERT_FILE    /etc/ssl/certs/ca-certificates.crt
    SSL_CERT_DIR     /etc/ssl/certs
}
