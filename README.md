# Cliff

> Cliff gets you up close to the cloud without forcing you to learn to fly.

A containerized development environment for elastic infrastructure work, plus a host-side launcher (`bin/cliff`) for hardened, profile-driven, ephemeral container sessions safe for LLM use.

**Full narrative:** [`docs/cliff.html`](docs/cliff.html) — why cliff exists, what's in each image, how the launcher works, dependency tree per variant.

## Status

- **v0.3.0** — `bin/cliff` CLI, profiles, hardened sessions
- **v0.2.0** — package versions refreshed
- **v0.1.0** — four Docker images, smoke tests, published to ghcr.io

## Image variants

| Image | Base | Contents (summary) |
|---|---|---|
| `cliff-base` | Alpine 3.23 | shell QoL, Elixir/OTP, Tcl, Nix, sqlite, devuser |
| `cliff-dev` | cliff-base | Terraform, kubectl, Helm, Packer, Vault, Ansible, AWS/Azure/GCP CLIs, Tailscale, Wrangler, Smallstep |
| `cliff-obsv` | cliff-base | Prometheus, Grafana, Loki, Vector, osquery, psql |
| `cliff-full` | cliff-dev | dev + obsv |

Images live at `ghcr.io/imsmith/cliff-{base,dev,obsv,full}:0.3.0`.

## CLI

```bash
bin/cliff list                                          # show profiles
bin/cliff describe yolo-dev                             # show resolved profile
bin/cliff run yolo-dev --project=$PWD                   # interactive shell
bin/cliff exec yolo-dev --project=$PWD -- terraform init # one-shot command
bin/cliff sessions                                      # recent sessions
bin/cliff session <id>                                  # session detail
```

| Profile | Image | Workspace | Creds | Egress |
|---|---|---|---|---|
| `base` | cliff-base | ro | none | none |
| `dev-offline` | cliff-dev | rw | none | none |
| `yolo-dev` | cliff-dev | rw | none | package registries |
| `dev-aws-read` | cliff-dev | rw | STS read role | `*.amazonaws.com` |
| `dev-aws-write` | cliff-dev | rw | STS write role | `*.amazonaws.com` |
| `obsv-local` | cliff-obsv | ro | none | none |

Replace `READ_ROLE_ARN` / `WRITE_ROLE_ARN` in the AWS profiles with your account's role ARNs before using.

## For LLMs

Expose `bin/cliff` on PATH. In project-level `CLAUDE.md` (or equivalent), add:

> For any infrastructure command (terraform, kubectl, aws, helm, etc.), invoke via `cliff exec <profile> --project=<path> -- <cmd>`. Do not run these tools directly on the host. See `cliff list` for available profiles.

## Building and testing

```bash
make build-base    # base image only
make build-dev     # base + dev
make build-obsv    # base + obsv
make build-full    # base + dev + full
make build-all     # all four
make test          # smoke tests across all images
make clean         # remove all cliff images
```

## Docker Compose

```bash
docker compose run --rm cliff-dev    # ~/github mounted as /workspace
docker compose run --rm cliff-obsv
docker compose run --rm cliff-full
```

## License

AGPL-3.0 — see `LICENSE`.
