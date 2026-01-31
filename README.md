# Cliff

Cliff is a containerized dev environment for working with elastic infrastructure projects.  It provides a consistent toolbox for working with Elastic Compute, Connectivity, and Storage Infrastructure, Infrastructure as Code, and Information and Event Management.

Cliff is called Cliff because it gets you up close to the cloud without forcing you to learn to fly.

## Tools

Cliff includes the following tools:

### Infrastructure Provider CLIs

- Aviatrix CLI (aviatrixcli)
- AWS CLI
- Azure CLI
- Cloudflare CLI (flarectl)
- DigitalOcean CLI (doctl)
- Equinix Metal CLI (metalctl)
- Fastly CLI (fastly)
- Fly.io CLI (flyctl)
- Google Cloud SDK
- Hetzner Cloud CLI (hcloud)
- Linode CLI
- Proxmox VE CLI (pvesh)
- Tailscale CLI (tailscale)
- Vultr CLI (vultr-cli)

### Infrastructure as Code tools

- Ansible
- Helm
- kubectl
- Packer
- podman
- Smallstep CLI (step)
- Terraform
- Vault

### Information and Event Management tools

- Cortex CLI (cortex-cli)
- Fluent Bit CLI (fluent-bit)
- Fluentd CLI (fluentd)
- Grafana CLI (grafana-cli)
- Loki CLI (loki-canary)
- Osquery CLI (osqueryd)
- PostgreSQL CLI (psql)
- Prometheus CLI (prometheus-canary)
- Promtail CLI (promtail-canary)
- sqlite3 CLI (sqlite3)
- Tempo CLI (tempo-canary)
- Vector CLI (vector)

### Linux environment quality of life tools

- bash
- curl
- fish
- git
- jq
- mosh
- tmux
- wireguard-tools
- yq

### Language Runtimes

- Common Lisp (SBCL)
- Elixir
- Nix
- Prolog (SWI-Prolog)
- Scheme (Guile)
- Tcl/Tk

## Usage

Cliff is distributed as a Virtual Machine image and as a set of Docker images.

### Virtual Machine

The Virtual Machine image can be run in any hypervisor that supports the QCOW2 format, such as QEMU/KVM, VirtualBox, or VMware.

1. Download the latest Cliff QCOW2 image from the [releases page]
2. Import the QCOW2 image into your hypervisor of choice.
3. Update the cloud-init configuration to set your username and SSH keys, and volumes to mount.  Cliff will not accept password logins by default and requires a remote filesystem to mount for persistent storage.
4. Start the VM and SSH into it using the username you configured in cloud-init.  Using mosh is recommended for a more resilient connection.
5. You can now use Cliff as your dev environment.
6. To update Cliff, download the latest QCOW2 image and replace your existing VM's disk with the new image.  No data is stored in the image itself, so your home directory and configuration will be preserved.

### Container

Cliff is also available as a set of Docker images.  There are three images available: `cliff/full`, `cliff/dev`, and `cliff/obsv`.  `cliff/base` is also available as a minimal base image, without any infrastructure tools included; it is used to build the other images.

- `cliff/full` is the full environment with all tools included.
- `cliff/dev` is the development environment with infrastructure provider CLIs and Infrastructure as Code tools included.
- `cliff/obsv` is the observability environment with monitoring and logging tools included.
- `cliff/base` is a minimal base image with just the Linux environment quality of life tools and language runtimes.

To run Cliff as a container, create an environment file `cliff.env` with the following minimum contents:

```text
CLIFF_HOME=/path/to/your/persistent/home
CLIFF_SSH_AUTH_SOCK=/path/to/your/ssh/auth/socket
```

Then, launch the container using compose:

```yaml
version: '3.8'
services:
  cliff:
    image: cliff/full:latest
    container_name: cliff
    env_file:
      - ./cliff.env
    volumes:
      - $CLIFF_HOME:/home/devuser
      - $CLIFF_SSH_AUTH_SOCK:/ssh-agent
    environment:
      - SSH_AUTH_SOCK=/ssh-agent
    tty: true
    stdin_open: true
```

You can then login to the container with ssh at `username@cliff.local`.
