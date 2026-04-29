# Cliff — Containerized Dev Environment

## What Cliff Is

"Cliff gets you up close to the cloud without forcing you to learn to fly."

A containerized development environment for elastic infrastructure work, plus a host-side launcher (`bin/cliff`) for hardened, profile-driven, ephemeral container sessions safe for LLM use.

Full narrative: `docs/cliff.html`. Quick reference: `README.md`.

## Current State

Post-sprint expansion mode. Latest tagged release: **v0.3.0** (LLM sandbox).

- **v0.3.0** — `bin/cliff` CLI + profiles + hardened ephemeral sessions. Spec at `docs/superpowers/specs/2026-04-17-cliff-llm-sandbox-design.md`, plan at `docs/superpowers/plans/2026-04-17-cliff-llm-sandbox.md`.
- **v0.2.0** — package versions refreshed.
- **v0.1.0** — four Docker images built, smoke-tested, published to `ghcr.io/imsmith`.

The Feb 2026 sprint that produced v0.1.0 closed on schedule; the sprint plan (`/home/imsmith/Documents/remote.vault.001/src/099 Katachora/SPRINT-2026-02.md`) is historical reference, not active work.

## Architecture

```
build/
  Dockerfile.base    # Alpine 3.23 + shell QoL + Elixir/OTP + Tcl + Nix + devuser
  Dockerfile.dev     # FROM cliff-base + IaC stack + cloud CLIs
  Dockerfile.obsv    # FROM cliff-base + Prometheus, Grafana, Loki, Vector, osquery, psql
  Dockerfile.full    # FROM cliff-dev + obsv tools layered on
bin/cliff            # Tcl entrypoint; dispatches to lib/cliff
lib/cliff/           # launcher implementation (Tcl)
profiles/            # *.tcl profiles: base, dev-offline, yolo-dev, dev-aws-read, dev-aws-write, obsv-local
images/              # cliff-egress CA, mitmproxy assets
helpers/             # credential helpers (aws-sts, etc.)
src/                 # auxiliary source
test/                # smoke tests + lib/CLI integration tests
docs/cliff.html      # canonical user-facing narrative
docs/superpowers/    # design specs and plans
Makefile             # build-base, build-dev, build-obsv, build-full, build-all, test, clean
docker-compose.yml   # services for each variant; mount ~/github as /workspace
```

## Out of Scope

Not currently planned. Decide deliberately before adding.

- QCOW2/VM images, Packer configs (cloud-init reference example exists at `examples/cloud-init/` only)
- CI/CD pipeline for image builds
- Exotic provider CLIs (Equinix, Fastly, Fly, Hetzner, Vultr, Linode)
- Common Lisp, Prolog, Scheme runtimes
- SSH server inside the container
