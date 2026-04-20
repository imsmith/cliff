# Cliff — Containerized Dev Environment

## Sprint Context

Active sprint through Feb 28, 2026. Full plan: `/home/imsmith/Documents/remote.vault.001/src/099 Katachora/SPRINT-2026-02.md`

Cliff is Phase 2 (Feb 19-22). Read the sprint plan for day-by-day tasks.

## What Cliff Is

"Cliff gets you up close to the cloud without forcing you to learn to fly."

A containerized development environment for elastic infrastructure work. Four image variants:
- **cliff/base** — Alpine + QoL tools + language runtimes (Elixir, Tcl, Nix)
- **cliff/dev** — base + IaC tools (Terraform, Ansible, kubectl, Helm, Packer) + provider CLIs
- **cliff/obsv** — base + observability stack (Prometheus, Grafana, Loki, Vector, osquery)
- **cliff/full** — dev + obsv combined

## Current State (as of 2026-04-17)

**v0.3.0 — LLM sandbox shipped.** `bin/cliff` + profiles + hardened container sessions. See `docs/superpowers/specs/2026-04-17-cliff-llm-sandbox-design.md` and `docs/superpowers/plans/2026-04-17-cliff-llm-sandbox.md`.

**v0.2.0 — shipped.** All package versions refreshed.

**v0.1.0 — shipped.** 4 Docker images built, tested, published to ghcr.io/imsmith.

## Architecture

```
build/
  Dockerfile.base    # Alpine 3.19, bash, fish, curl, git, jq, tmux, mosh, yq,
                     # wireguard-tools, sqlite3, Elixir+OTP, Tcl/Tk, Nix, devuser
  Dockerfile.dev     # FROM cliff-base + terraform, ansible, kubectl, helm, packer,
                     # vault CLI, smallstep, awscli, azure-cli, gcloud, tailscale, wrangler
  Dockerfile.obsv    # FROM cliff-base + prometheus, grafana, loki, logcli, vector, osquery, psql
  Dockerfile.full    # FROM cliff-dev + obsv tools
Makefile             # build-base, build-dev, build-obsv, build-full, build-all, test, clean
docker-compose.yml   # services for each variant, mount ~/github as /workspace
test/smoke.sh        # smoke tests for all binaries across all 4 images
```

## Registry

Images at `ghcr.io/imsmith/cliff-{base,dev,obsv,full}:0.1.0`

## Out of Scope This Sprint

- QCOW2/VM images
- Packer configs
- CI/CD pipeline
- Cloud-init
- Exotic provider CLIs (Equinix, Fastly, Fly, Hetzner, Vultr, Linode)
- Common Lisp, Prolog, Scheme runtimes
- SSH server configuration
