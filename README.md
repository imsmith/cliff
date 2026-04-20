# Cliff

Cliff is a containerized development environment for elastic infrastructure work. It gets you up close to the cloud without forcing you to learn to fly.

## Status

**v0.2.0** - update all packages to current/latest as of 20260220

**v0.1.0** — 4 Docker images build and pass smoke tests.

## Image Variants

| Image | Base | Contents |
|---|---|---|
| **cliff/base** | Alpine Linux | QoL tools, Fish shell, Elixir/OTP, Tcl/Tk, Nix, sqlite3 |
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

## Cliff CLI (v0.3.0)

`bin/cliff` launches hardened, profile-driven, ephemeral container sessions safe for LLM
use. Each session runs under a profile declaring image, mount posture, credentials, egress
allowlist, and resource limits. Credentials are minted on the host and written to a
container-private tmpfs; egress (if any) is proxied through a per-session mitmproxy sidecar
enforcing the profile's allowlist; hostnames outside the allowlist resolve to 127.0.0.1.

### Quick start

```bash
bin/cliff list                                          # show profiles
bin/cliff describe yolo-dev                             # show resolved profile
bin/cliff run yolo-dev --project=$PWD                   # interactive shell
bin/cliff exec yolo-dev --project=$PWD -- terraform init # one-shot command
bin/cliff sessions                                      # recent sessions
bin/cliff session <id>                                  # session detail
```

### Profiles shipped

| Profile | Image | Workspace | Creds | Egress |
|---|---|---|---|---|
| `base` | cliff-base | ro | none | none |
| `dev-offline` | cliff-dev | rw | none | none |
| `yolo-dev` | cliff-dev | rw | none | package registries |
| `dev-aws-read` | cliff-dev | rw | STS read role | `*.amazonaws.com` |
| `dev-aws-write` | cliff-dev | rw | STS write role | `*.amazonaws.com` |
| `obsv-local` | cliff-obsv | ro | none | none |

Replace `READ_ROLE_ARN` / `WRITE_ROLE_ARN` in the AWS profiles with your account's role ARNs
before using.

### For LLMs

Expose `bin/cliff` on PATH. In project-level `CLAUDE.md` (or equivalent), add:

> For any infrastructure command (terraform, kubectl, aws, helm, etc.), invoke via
> `cliff exec <profile> --project=<path> -- <cmd>`. Do not run these tools directly on the
> host. See `cliff list` for available profiles.

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
