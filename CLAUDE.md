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

## Current State (as of Feb 12, 2026)

**Nothing is implemented.** Only README.md (125 lines) + LICENSE (AGPL v3) + empty directory structure exist. No Dockerfiles, no Makefile, no build scripts, no configs. Two commits total.

## Sprint Goal for Cliff

**Exit criteria:**
```
make build-all   -> 4 images built successfully
make test        -> smoke tests pass for all variants
docker compose   -> can launch any variant and get a working shell
git tag          -> v0.1.0
README           -> documents actual contents and usage
```

## What to Build

```
build/
  Dockerfile.base    # Alpine 3.19, bash, fish, curl, git, jq, tmux, mosh, yq,
                     # wireguard-tools, sqlite3, Elixir+OTP, Tcl/Tk, Nix
  Dockerfile.dev     # FROM base + terraform, ansible, kubectl, helm, packer,
                     # vault CLI, smallstep, awscli, azure-cli, gcloud, tailscale, wrangler
  Dockerfile.obsv    # FROM base + prometheus, grafana/grafana-agent, loki, vector, osquery
  Dockerfile.full    # FROM dev + obsv tools
Makefile             # build-base, build-dev, build-obsv, build-full, build-all, test, clean
docker-compose.yml   # services for each variant, mount ~/github as /workspace
test/smoke.sh        # run key binaries in each image, check exit codes
```

## Out of Scope This Sprint

- QCOW2/VM images
- Packer configs
- CI/CD pipeline
- Cloud-init
- Exotic provider CLIs (Equinix, Fastly, Fly, Hetzner, Vultr, Linode)
- Common Lisp, Prolog, Scheme runtimes
- SSH server configuration
