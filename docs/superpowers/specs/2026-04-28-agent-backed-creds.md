# Agent-backed cloud credentials for cliff

**Status:** roadmap
**Date:** 2026-04-28
**Predecessor:** snapshot-mode `aws-vault` helper (`helpers/aws-vault.tcl`, `profiles/dev-aws-vault.tcl`) shipped same day

## The grievance

Logging into a cloud provider is the dumbest form of punishment. The current cliff cred-helper model (`aws-sts`, `aws-vault` snapshot) freezes credentials at session start. They expire mid-session. The user must exit and re-`run`. This is fine — even desirable — for short exploratory sandboxes (see `feedback_expiring_creds`: expiry is the seatbelt). It is wrong for long-running work: build daemons, watchers, test loops that legitimately outlive a 1h STS session.

What we want for the long-running case is `ssh-agent` semantics for cloud creds:
- Identity is held by a host-side agent, unlocked once.
- Tools inside the sandbox don't see secrets; they see an *endpoint*.
- Creds rotate transparently. Sandbox processes never observe expiry.

## Existing primitives

- **`aws-vault exec --server`** runs a metadata-service shim on the host (default `http://127.0.0.1:9099`) and exports `AWS_CONTAINER_CREDENTIALS_FULL_URI` / `AWS_CONTAINER_AUTHORIZATION_TOKEN` into the child process environment. Any AWS SDK auto-discovers it.
- **`gcloud auth application-default`** + GCE metadata emulation — same shape for GCP.
- **Azure managed-identity emulation** via `az login` and IMDS shims — same shape for Azure.

All three reduce to: *a local HTTP endpoint speaking the cloud's metadata-service protocol*. The cliff job is to wire that endpoint into the sandbox.

## Proposed cliff change

Two new pieces:

### 1. Profile syntax: `creds-agent` block (sibling to `creds`)

```tcl
creds-agent {
    aws aws-vault profile=avx
    # later: gcp gcloud-adc project=foo
    # later: azure az-cli subscription=bar
}
```

Distinct from `creds { ... helper=... }` because the semantics are different: long-lived agent + endpoint forwarding, not one-shot file materialization.

### 2. Sandbox plumbing: host-endpoint forwarding primitive

cliff needs a generic way to expose a host-side TCP endpoint into the sandbox network namespace, plus pass associated env vars. Concretely:

- Spawn the agent on the host (`aws-vault exec --server avx -- sleep infinity`, or similar long-lived).
- Capture `AWS_CONTAINER_CREDENTIALS_FULL_URI` and the auth token from the agent process environment.
- Make `127.0.0.1:9099` (or whatever the agent chose) reachable from inside the sandbox — likely via a port-forward into the network namespace, or a unix-socket bind-mount if the agent supports it.
- Set the env vars inside the sandbox.

Same primitive lets you wire in `ssh-agent`, `gpg-agent`, `pass-agent`, etc. later. The credential domain is just the first user.

## Open questions

- **Agent lifecycle.** Does cliff start/stop the agent per-`run`, or assume the user runs it once at login? `ssh-agent` precedent: the user starts it; tools just consume the socket. Probably the same here.
- **Network reachability.** `aws-vault exec --server` binds TCP. A unix-socket variant would be cleaner (file permissions, no port conflicts). Worth upstream patch?
- **Multi-cloud composition.** A profile that needs both AWS and GCP at once — `creds-agent { aws ...; gcp ... }` — implies the sandbox sees both metadata endpoints. SDK auto-discovery handles each independently, so probably fine.
- **Audit trail.** When creds rotate transparently, the human loses the "I just logged in" tactile signal. Worth a passive notification? (`cliff status` shows last rotation time?)

## Out of scope

- Replacing snapshot mode. Snapshot stays for `dev-*` / `yolo-*` profiles where expiry is the point.
- Implementing the host-side agent. cliff consumes existing agents (`aws-vault`, `gcloud`, `az`); it does not become one.

## Trigger to start

When a real long-running cliff use case appears (build watcher, test loop, scheduled job inside a session) and snapshot expiry becomes a daily pain. Until then: snapshot mode is enough.
