# Cliff LLM Sandbox — Design

**Date:** 2026-04-17
**Status:** Approved, ready for implementation planning
**Target:** Cliff v0.3.0

## Problem

Cliff v0.1.0 shipped four container images that work, but the human workflow around them is hand-rolled `docker run` lines. The goal now is to make Cliff a sandbox an LLM can drive for infrastructure tasks without risk of losing host data, exfiltrating credentials, running up cloud bills, or persisting anything across sessions. The bar is "goblin-mode safe": an LLM can misbehave arbitrarily inside a session, and the blast radius is bounded by the profile it ran under. Setup cost per invocation must be zero — the human picks (or the LLM picks) a profile name, and everything else is enforced by the tool.

## Non-goals

- Protecting against a malicious LLM *inside the container* exfiltrating the scoped credentials it was legitimately given during their TTL. Scope and TTL are the defense.
- Host credential management. The host's base credentials (aws-vault, 1Password, etc.) are the user's problem.
- Cloud-platform-specific guardrails. Cliff is platform-agnostic — it does not rely on AWS IAM, Kubernetes RBAC, or any provider's permission model to backstop. Sandbox enforcement happens at the container boundary (egress allowlist, mount mode, cred absence), not at the remote API.
- QCOW2/VM images, CI/CD, SSH server, exotic provider CLIs — deferred.

## Architecture

A tcl script `bin/cliff` is the single entry point. It reads a **profile** (a tcl file describing a sandbox configuration), translates it into a hardened `docker run` invocation, and execs it. No daemon, no shared state, no magic — a deterministic translator from profile to container pair.

```
bin/cliff run|exec <profile> [--project=<path>] [--override=key:val]
       │                │
       │                reads profiles/<profile>.tcl, resolves inheritance,
       │                validates, materializes creds, renders egress allowlist
       │
       runs docker: creates a per-session network, starts egress container
       (if any), starts app container with hardened defaults, attaches or execs.
```

Three layers:

1. **Profiles** (`profiles/*.tcl`) — declarative: which image, which mounts, which creds, which egress, which limits.
2. **Cliff CLI** (`bin/cliff`) — resolves the profile, enforces invariants, builds the docker command.
3. **Runtime hardening** — applied to every container regardless of profile: non-root user (`devuser`), dropped capabilities, `--security-opt no-new-privileges`, read-only rootfs + overlay tmpfs, tmpfs `/tmp`, cgroup limits from profile, seccomp default.

**Default posture is deny-all.** A profile opens specific holes. The `yolo-dev` profile isn't "no sandbox" — it's "the sandbox I trust an LLM to go feral inside."

## Profile model

A profile is a tcl file. Single-parent inheritance via `inherit <name>`. Each top-level block (`creds`, `egress`, `limits`, `env`, `workspace`, `home`) is replaced wholesale in the child — no deep merging. Parents are resolved first, children override. Cycles detected at parse time and fail loud.

Example:

```tcl
# profiles/dev-aws-read.tcl
inherit dev-base

describe    "Dev image with scoped read-only AWS access"
image       cliff-dev:0.2.0

workspace   mode=ro
home        mode=tmpfs size=512m

creds {
    aws     helper=aws-sts args={role=arn:aws:iam::...:role/cliff-read ttl=1h}
}

egress {
    allow   *.amazonaws.com:443
    allow   registry-1.docker.io:443
}

limits {
    cpus    2
    memory  4g
    pids    512
}

env {
    AWS_REGION  us-east-1
}
```

### Profile set shipped in v0.3.0

- `base` — floor. Read-only workspace, tmpfs home, no creds, no egress, tight limits.
- `dev-offline` — base + dev image + workspace writable. No network. For terraform `plan` against local state, editing code.
- `dev-aws-read` / `dev-aws-write` — scoped AWS creds via `aws-sts` helper, egress allowlisted to AWS endpoints.
- `obsv-local` — obsv image, workspace read-only, egress to localhost only.
- `yolo-dev` — dev image, workspace writable, no creds, egress to package registries only.

### Discovery

- `cliff list` — one line per profile: `<name>  <describe>  [image]  [egress-summary]`.
- `cliff describe <profile>` — full resolved profile (after inheritance) as tcl, plus a rendered human summary.

## Credential injection

Core rule: **credentials never live in images or on mounted host paths; they materialize at container start, inside the container, on a container-private tmpfs, with a lifetime shorter than the session.**

Two credential sources, declared per-profile:

| Source | How it works |
|---|---|
| `none` | No creds. Default. |
| `cred-helper` | Profile names a host-side tcl script under `helpers/`. Cliff execs it with `args`, captures stdout, writes to `/run/creds/<name>`. |

AWS STS, Vault, gcloud, etc. are **shipped helpers**, not first-class concepts. `helpers/aws-sts.tcl`, `helpers/vault-token.tcl`, `helpers/gcloud-impersonate.tcl`, etc. The core wrapper knows only `none` and `cred-helper`. This keeps Cliff platform-agnostic — adding a new credential source is a new script, not a change to the wrapper.

Mechanics:

- `/run/creds` is a tmpfs mounted into the container at create time, owned by devuser, mode 0700.
- Cliff runs helpers on the host, collects stdout, writes into the tmpfs *before* handing the shell to the user. The host never writes to a bind-mounted host path.
- Environment variables like `AWS_SHARED_CREDENTIALS_FILE=/run/creds/aws` point tooling at the right location. The profile declares the env bindings alongside the cred entry.
- On container exit, tmpfs is freed. No cleanup step to forget.

**Hard bans:**

- No host credential directory is ever bind-mounted into any container. `~/.aws/`, `~/.kube/`, `~/.ssh/` are invisible to every profile. If you need SSH keys, a cred-helper either generates an ephemeral key or fetches from an agent and writes to `/run/creds/`.
- No bypass flag.

**The base-trust assumption:** the host `cliff` process needs some base credential to mint scoped ones. That lives on the host under `~/.config/cliff/base-creds/`, never in any container. The container only ever sees derivatives.

## Egress policy

**Mechanism: per-session egress proxy sidecar.**

Every container that needs network gets a companion container on a private docker network with no external route:

```
cliff-session-<id> (docker network, no external gateway)
    ├── app container      — http(s)_proxy=http://egress:3128, DNS → egress
    └── egress container   — mitmproxy with cliff CA, allowlist from profile,
                             upstream: host network, real DNS
```

- App container has no external network interface. Bypassing proxy env vars does not help; raw sockets to the outside world have nowhere to go.
- Egress container runs **mitmproxy** with a cliff-specific CA baked into every cliff image at build time (`/usr/local/share/ca-certificates/cliff-egress.crt`, `update-ca-certificates` run during image build). This means TLS is transparently inspected; the allowlist can operate on URL path, not just host:port; and we have per-request audit logs for the future.
- DNS: app container's resolv.conf points at the egress container, which runs a stub resolver. Allowlisted names get real answers. Non-allowlisted names get `127.0.0.1` (pi-hole style). DNS always succeeds; connections fail at transport layer where applications already handle it cleanly. No NXDOMAIN leakage via DNS queries.
- Non-HTTP(S) protocols (e.g., postgres, SSH): allowlisted via explicit CONNECT rules to specific `host:port`. Not allowlisted → transport fails.

**Profile → allowlist:**

```tcl
egress {
    allow   *.amazonaws.com:443
    allow   registry.terraform.io:443
}
```

Rendered to a mitmproxy config at session start, loaded, network created, both containers started, app shell attached.

**Special cases:**

- `egress { deny * }` — no egress container spawned. App container gets no network interface at all. Used by `dev-offline`, `base`. Fastest startup.
- **No unrestricted-egress escape hatch.** If unrestricted egress is needed, fork cliff under a different name. The tool's contract is "egress is always either denied or allowlisted" with no bypass.

**Logging:** egress container logs every allowed and denied request with timestamp and app-container id to `~/.local/share/cliff/sessions/<id>/egress.log`. Last 100 sessions retained, then pruned.

## Session semantics

A session is one container pair (app + egress, or just app for offline profiles) from `cliff run`/`cliff exec` to exit. Independent and ephemeral.

**Identity:** short hash of `<timestamp>-<profile>-<pid>`, e.g. `7f3a21`. Used as container name suffix, network name, session log directory.

**Host-side session dir:** `~/.local/share/cliff/sessions/<id>/` contains resolved profile, start metadata (image digest, command, start time), egress log, exit code. Retention: 100 sessions.

**State policy:**

- `/workspace` — bind mount of `--project=<path>`. Mode (`ro`/`rw`) from profile. Read-only default.
- `/home/devuser` — tmpfs, size from profile, 512m default. Dotfiles seeded from `/etc/skel` at image build time. Host dotfiles are never mounted.
- `/run/creds` — tmpfs, container-private, written by cliff before shell start.
- **Read-only rootfs** with overlay tmpfs. `/etc`, `/usr`, `/bin` are immutable per session. `apk add foo` works but only for this session. Minor compatibility cost accepted.
- **No named docker volumes.** A profile cannot request one. The workspace mount is the only persistent surface; anything else vanishes at exit.

**Lifecycle:**

```
cliff run <profile> [--project=<path>]
  → resolve profile
  → run cred helpers (if any) on host, capture outputs
  → create docker network cliff-<id>
  → start egress container (if profile has egress allows)
  → start app container; write creds to /run/creds tmpfs; exec shell
  → wait for shell exit
  → stop + rm both containers, rm network, flush tmpfs
  → write session exit record
```

**Concurrency:** parallel sessions are independent — separate IDs, networks, containers. No global lock.

**No `cliff attach` in v1.** Sessions are strictly ephemeral from the wrapper's perspective. For long-running work, use `tmux` inside the container; when the container exits, tmux dies with it. `cliff attach` may be revisited later.

## LLM integration surface

**Primary surface:** a single shell command.

```
cliff exec <profile> --project=<path> -- <command> [args...]
```

- Non-interactive: runs `<command>` inside a fresh session, streams stdout/stderr, exits with the container's exit code.
- Identical profile resolution, cred minting, egress enforcement, and cleanup as `cliff run`.
- Designed to be what an LLM harness's shell tool calls.

**Claude Code integration pattern (and any equivalent harness):**

- Add Cliff's `bin/` to PATH.
- A `CLAUDE.md` snippet in each project using Cliff declares: *"For any command that touches cloud/infrastructure tools, invoke via `cliff exec <profile> -- <cmd>`. Do not run these tools directly on the host. Available profiles: `cliff list`."*
- Permission surface becomes: user allows `cliff exec *` once. Every infra-touching invocation is then constrained by the profile.

**No MCP server in v1.** Bash + `cliff exec` is the MVP. MCP may be added later to expose structured profile metadata and streaming session logs.

**Profile selection is the LLM's call.** It reads `cliff list`, picks what it thinks it needs. The sandbox enforces: egress allowlist, workspace mount mode, cred absence. Cliff explicitly does not rely on platform-side permission systems (AWS IAM, k8s RBAC, etc.) to backstop selection — the container boundary is the boundary.

**Observability:**

- `cliff sessions` — recent sessions: id, profile, start time, duration, exit code, egress hit summary.
- `cliff session <id>` — full session record: resolved profile, command, exit code, egress log.

## Testing

Test layers:

1. **Profile parser tests** (tcl, fast, no docker). Inheritance resolution, cycle detection, block-replacement semantics, malformed-input failure modes. Sub-second.

2. **Wrapper translation tests.** Given profile X, assert cliff emits expected docker run args (caps dropped, read-only rootfs, correct tmpfs mounts, correct network). No containers started. Catches regressions in hardening defaults.

3. **Sandbox enforcement tests** (integration, require docker). One test per threat class:

   | Threat | Test |
   |---|---|
   | FS blast radius | `cliff exec dev-offline -- rm -rf /workspace` against ro mount; fixture intact |
   | Egress block | `cliff exec dev-offline -- curl https://example.com` fails |
   | Allowlisted egress | `cliff exec dev-aws-read -- curl https://sts.amazonaws.com` succeeds |
   | Cred absence | `cliff exec yolo-dev -- ls ~/.aws` → no such directory |
   | Host cred invisibility | `cliff exec dev-offline -- cat /host/.aws/credentials` → no such path |
   | Persistence | write to `/home/devuser/foo`, exit, new session, file absent |
   | Resource limits | fork bomb killed by pids limit |
   | Read-only rootfs | `touch /etc/foo` fails |

**Not tested in v1:** cred-helper correctness (helpers are separate, tested separately), mitmproxy TLS-interception correctness (upstream's responsibility — we verify our allowlist config is applied), performance.

No theatrical "goblin-mode" end-to-end adversarial test. Per-threat tests are crisp and individually meaningful; a staged "evil LLM" test would give false confidence.

## Out of scope

- QCOW2 / VM images
- CI/CD pipeline for cliff itself
- SSH server in images
- Additional provider CLIs beyond what's already in cliff-dev
- `cliff attach` for long-lived sessions
- MCP server surface
- TLS body logging / audit pipeline (mitmproxy groundwork is laid, but consumers come later)
- Automatic profile selection
- Host dotfile integration (users build overlay images instead)

## Open items for the implementation plan

- Exact tcl idioms for profile parsing (homebrew evaluator in a safe interpreter vs. `source` in a restricted slave interp; I lean slave interp with a whitelist of commands).
- Allowed docker versions / rootless-vs-rootful stance. Assumption: rootful docker on Linux for v0.3.0; rootless podman is v0.4.0 conversation.
- Exact set of dropped capabilities (baseline: drop all, add back CAP_NET_BIND_SERVICE only if a profile needs it — and no shipped profile does).
- Format of helper script stdout contract (raw credential file bytes? structured envelope?).
- How `cliff describe` renders "resolved profile" for LLM consumption (tcl source? normalized text? both?).
