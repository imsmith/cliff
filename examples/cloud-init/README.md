# cloud-init examples

Out-of-sprint reference. Sprint 2026-02 (cliff Phase 2) excludes cloud-init and
VM image work; these files exist so the design isn't lost between sprints.

## Files

- `debian12-cliff-dev.yaml` — Debian 12 cloud image + rootless podman, pulls
  `ghcr.io/imsmith/cliff-dev:0.3.0` at first boot.

## Notes

- cloud-init is YAML by upstream spec. The project's no-YAML rule does not
  apply here — this is the format the ecosystem tool requires.
- Test locally with `cloud-localds` + qemu before pushing to a cloud provider.
- First boot takes 1–3 minutes (apt install + image pull). Watch
  `/var/log/cloud-init-output.log` on the guest if it seems stuck.
