# Cliff

Cliff is a containerized development environment for elastic infrastructure work. It gets you up close to the cloud without forcing you to learn to fly.

## Status

**v0.1.0** — 4 Docker images build and pass smoke tests.

## Image Variants

| Image | Base | Contents |
|---|---|---|
| **cliff/base** | Alpine 3.19 | QoL tools, Fish shell, Elixir/OTP, Tcl/Tk, Nix, sqlite3 |
| **cliff/dev** | cliff/base | Terraform, Ansible, kubectl, Helm, Packer, Vault, AWS/Azure/GCloud CLIs, Tailscale, Wrangler, Smallstep |
| **cliff/obsv** | cliff/base | Prometheus, Grafana, Loki, LogCLI, Vector, psql |
| **cliff/full** | cliff/dev | Everything in dev + obsv |

## What's Included

### cliff/base
- **Shell**: bash, fish (default), sudo
- **Tools**: curl, wget, git, jq, yq, tmux, mosh, ssh, wireguard-tools, sqlite3, coreutils
- **Languages**: Elixir 1.15 + Erlang/OTP 26, Tcl/Tk 8.6, Nix
- **User**: `devuser` with passwordless sudo

### cliff/dev (adds to base)
- **IaC**: Terraform 1.7, Ansible, kubectl 1.29, Helm 3, Packer 1.10
- **Provider CLIs**: AWS CLI, Azure CLI, Google Cloud SDK, Tailscale, Cloudflare Wrangler
- **Security**: Vault 1.15, Smallstep CLI

### cliff/obsv (adds to base)
- **Monitoring**: Prometheus 2.50, promtool, Grafana 10.4
- **Logging**: Loki 2.9, LogCLI, Vector 0.36
- **Database**: PostgreSQL client (psql)

### cliff/full
Everything from dev + obsv combined.

## Building

```bash
make build-base    # Build base image only
make build-dev     # Build base + dev
make build-obsv    # Build base + obsv
make build-full    # Build base + dev + full
make build-all     # Build all 4 images
make test          # Run smoke tests
make clean         # Remove all cliff images
```

## Usage

### Docker Compose

```bash
# Start a dev environment with ~/github mounted as /workspace
docker compose run --rm cliff-dev

# Start an observability environment
docker compose run --rm cliff-obsv

# Start the full environment
docker compose run --rm cliff-full
```

The compose file mounts `~/github` as `/workspace` and uses a shared volume for the devuser home directory.

### Direct Docker Run

```bash
docker run -it --rm \
  -v ~/github:/workspace \
  cliff/dev:latest
```

## Running Tests

```bash
make test
```

Runs `test/smoke.sh` which verifies each image has its expected binaries installed and functional. Currently 34 checks across all 4 images.

## License

AGPL v3 — see LICENSE.
