# Architecture

homelab-selene is the Docker Compose definition of **Selene**, the homelab host that runs USAS (Unattended Server
Auto-Setup), the web UI of [ubuntu-server-auto-setup](https://github.com/HoneyBearTech/ubuntu-server-auto-setup):
it installs Ubuntu Server on fresh Proxmox VE VMs with nobody at the keyboard, loads the admin's GitHub SSH keys and
applies a hardened baseline. Selene is a dedicated Ubuntu Server 26.04 VM on amd64, built by USAS itself, and runs
nothing else: USAS's data is the key to the Proxmox cluster and to every server it set up. The repository holds
configuration, not application code: the services run from their published images, pinned by digest.

## Services

| Service | Image source | Role |
| --- | --- | --- |
| USAS | the project's own image (signed with cosign by its release workflow) | Web UI and Ansible playbooks: builds the hands-off installer ISO on the Proxmox nodes, creates VMs through the Proxmox VE API, applies the hardened baseline over SSH, keeps the run history, and answers a status summary for dashboards |
| autoheal | the project's own image | Restarts USAS if its health check fails, and can post a notice to a webhook (Docker on its own only restarts a container that exits) |
| socket-proxy | linuxserver.io | Gives autoheal a filtered view of the Docker API (list, inspect, restart and stop containers only) on an internal network |

Every service has a health check, so `docker compose ps` shows a broken one, and autoheal restarts it.

USAS is reached only through the homelab's reverse proxy (such as Nginx Proxy Manager), on another host, which
terminates HTTPS under one host name and limits access to the LAN and VPN. The proxy isn't part of this stack.

## Actors and actions

| Actor | Does |
| --- | --- |
| Maintainer | Merges pull requests (a merge deploys), checks and bumps USAS by hand, tags releases, uses USAS in its web UI |
| Dependabot | Opens a pull request when an image (tag and digest), a check tool or an Action has a new version; patch, minor and major updates are auto-merged once the checks pass, except USAS's |
| CI | Lints, scans for secrets, tests the checker, resolves the Compose file, enforces the policy and smoke-tests the stack on amd64 on every pull request |
| Pull agent | On the maintainer's server, about every 90 seconds: fetches `main` and, when it moved, fast-forwards the checkout and runs `docker compose pull` and `docker compose up -d` (it lives in the maintainer's private orchestration repository) |
| Release workflow | On a version tag: checks the policy, writes the SBOM, signs the checksums, publishes the GitHub Release |
| LAN and VPN users | Reach USAS through the reverse proxy, behind its password or passkeys |
| Reverse proxy | Terminates HTTPS for `USAS_PUBLIC_URL` and forwards to `USAS_BIND_ADDRESS:8080`, the only address the firewall lets reach it |
| USAS | Calls the Proxmox VE API, logs in to the nodes and to new VMs over SSH, fetches the admin's public keys from GitHub |
| Dashboards | Read USAS's status summary (`/api/status`) through the proxy, with the status token |

## Data flow

```
browser (LAN, VPN) ──HTTPS──▶ reverse proxy (another host) ──HTTP──▶ USAS (USAS_BIND_ADDRESS:8080)
dashboard ──HTTPS + status token──▶ reverse proxy ──▶ USAS /api/status

USAS ──HTTPS, API token──▶ Proxmox VE API (8006): create, configure and start VMs
USAS ──SSH, pinned host keys──▶ Proxmox nodes: build the installer ISO ──▶ Ubuntu's release mirrors (signed SHA256SUMS)
USAS ──SSH, pinned host keys──▶ new VMs: the hardened baseline
USAS ──HTTPS──▶ GitHub (the admin's public SSH keys)
autoheal ──(internal network)──▶ socket-proxy ──read-only socket, filtered──▶ Docker on Selene (restart unhealthy)
scheduled backup ──rsync over SSH, age-encrypted──▶ backup server
```

USAS keeps everything in its folder under `CONFIG_ROOT` on the host, no Docker volumes (see
[interfaces.md](interfaces.md#volumes-and-mounts)), which is what `scripts/backup.sh` archives.

## How changes reach the host

1. Dependabot (or the maintainer) opens a pull request that changes an image's tag and digest.
2. CI resolves the Compose file, runs the policy check and the smoke test; the maintainer reads the service's
   release notes. For USAS, the maintainer also checks the new image's signature by digest
   ([upgrading.md](upgrading.md#upgrading-usas)).
3. The pull request is squash-merged (automatically for Dependabot's patch, minor and major updates and image
   rebuilds of autoheal and socket-proxy, once every check passes; by the maintainer, after a backup, for USAS and
   for updates Dependabot can't classify).
4. Within about 90 seconds the pull agent on the host sees `main` move, fast-forwards its checkout and runs
   `docker compose pull && docker compose up -d --remove-orphans --wait`
   ([upgrading.md](upgrading.md#following-main)). A rollback is a revert pull request, deployed the same way.
   Backups and restores share the agent's lock, so a deploy never starts while they have a service stopped
   ([deploy lock](installing.md#deploy-lock)).
5. A version tag makes a signed release: a named, verifiable snapshot of `main`.

Nothing updates from a registry by itself: a version that runs is always a version that's in `main`. The host
only pulls; nothing connects in to it to deploy.

## Repository layout

| Path | What |
| --- | --- |
| `compose.yaml` | The stack |
| `.env.example`, `autoheal.env.example`, `backup.env.example` | Templates for the settings, autoheal's optional webhook and the scheduled backup |
| `scripts/check_compose.py` | The policy check and SBOM generator (standard-library Python) |
| `scripts/backup.sh`, `scripts/restore.sh` | Backup and restore of every service's data |
| `scripts/scheduled-backup.sh`, `deploy/systemd/` | Nightly backup, copied off the host with rsync (encrypted with age) and pruned, reported to a push monitor |
| `scripts/smoke-test.sh` | Starts the stack in isolation, waits for health, and round-trips a backup |
| `tests/` | The checker's tests, with JSON fixtures |
| `docs/` | This documentation |
| `.github/` | CI, release and security workflows, Dependabot, templates |
| `.gitlab-ci.yml` | The pipeline of the copy on the maintainer's GitLab: mirrors GitHub, re-runs the daemon-free checks |
