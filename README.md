# homelab-selene

[![CI](https://github.com/HoneyBearTech/homelab-selene/actions/workflows/ci.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-selene/actions/workflows/ci.yml)
[![CodeQL](https://github.com/HoneyBearTech/homelab-selene/actions/workflows/codeql.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-selene/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/HoneyBearTech/homelab-selene/badge)](https://scorecard.dev/viewer/?uri=github.com/HoneyBearTech/homelab-selene)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15944/badge)](https://www.bestpractices.dev/projects/15944)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/15944/baseline)](https://www.bestpractices.dev/projects/15944)

Docker Compose stack for Selene, a homelab Ubuntu Server 26.04 (amd64) VM that runs USAS, the web UI of
[ubuntu-server-auto-setup](https://github.com/HoneyBearTech/ubuntu-server-auto-setup), with autoheal and a
filtering Docker socket proxy.
Version-pinned and kept as code for easy upgrades and rebuilds.

> [!WARNING]
> USAS holds a Proxmox VE API token that can create and wipe VMs, an SSH key that logs in to the Proxmox nodes
> and to every server it set up, and the Ansible Vault with its password. Whoever controls this host or its
> backups controls those. Keep USAS behind the reverse proxy and the firewall rule
> ([docs/installing.md](docs/installing.md#the-firewall)), and encrypt the backups that leave the host.

## Documentation

- [Quick start](docs/quick-start.md): getting the stack running on a fresh Docker host
- [Installing](docs/installing.md): host preparation, where data lives, the firewall, moving an existing USAS,
  running it securely, uninstalling
- [Upgrading](docs/upgrading.md): moving to a new release or a new USAS, backup and restore, rolling back
- [Rebuilding](docs/rebuilding.md): a new or wiped host, from a backup
- [Architecture](docs/architecture.md): the services, actors, data flow and how updates reach the host
- [Interfaces](docs/interfaces.md): every setting, port, volume, label and command
- [Verifying releases](docs/verifying-releases.md): checking signatures, checksums, provenance and the SBOM
- [Security requirements](docs/security.md): what the stack protects, what it doesn't, where secrets live
- [Assurance case](docs/assurance-case.md): threat model, trust boundaries, secure design, common weaknesses
- [Dependencies](docs/dependencies.md): how images and tools are chosen, pinned, tracked and patched
- [Roadmap](docs/roadmap.md): the next year, and what homelab-selene will not do
- Project policies: [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · [GOVERNANCE](GOVERNANCE.md) ·
  [SUPPORT](SUPPORT.md) · [CODE OF CONDUCT](CODE_OF_CONDUCT.md) · [CHANGELOG](CHANGELOG.md)

## What's in the stack

([architecture](docs/architecture.md), ports in [interfaces](docs/interfaces.md#services-and-ports)):

- **USAS** (Unattended Server Auto-Setup): a web UI and Ansible playbooks for cloud-image provisioning of Ubuntu,
  Debian and RHEL-family VMs on Proxmox VE, a hardened baseline, fleet updates and k3s clusters
  ([upstream documentation](https://github.com/HoneyBearTech/ubuntu-server-auto-setup))
- **autoheal**: restarts labelled unhealthy services (`usas` and `socket-proxy`) through the socket proxy
- **socket-proxy**: exposes a filtered Docker API to autoheal on an internal network, with no host port;
  permits only listing, inspecting, restarting and stopping containers

Every service has a health check, and every image is pinned by tag **and** digest, for `linux/amd64`. New
versions arrive as Dependabot pull requests that CI checks before they're merged. A new USAS is never merged
automatically: it changes how VMs are created, so it is bumped by hand after checking its signature
([upgrading](docs/upgrading.md#upgrading-usas)). The maintainer's server follows `main`: a pull agent there
applies each merge within a couple of minutes ([upgrading](docs/upgrading.md#following-main)). Nothing updates
from a registry tag by itself: what runs is always a commit in `main`.

## Repository layout

- [compose.yaml](compose.yaml): services, image pins, networks and mounts
- [.env.example](.env.example), [autoheal.env.example](autoheal.env.example) and
  [backup.env.example](backup.env.example): required settings and optional notification/backup templates
- [scripts/](scripts/): policy checks, backup, restore and smoke tests;
  [deploy/systemd/](deploy/systemd/): scheduled-backup service and timer
- [tests/](tests/): policy and operational tests; [docs/](docs/README.md): setup and operations
- [Makefile](Makefile), [requirements-dev.in](requirements-dev.in),
  [requirements-dev.txt](requirements-dev.txt) and [pyproject.toml](pyproject.toml): development commands and tools

## Getting started

You need Linux on amd64, Docker Engine 25 or later, Compose v2 2.24 or later, a user in the `docker` group,
and a reverse proxy on another host serving HTTPS. If moving an existing USAS, follow the
[migration procedure](docs/installing.md#moving-an-existing-usas-here) before the first startup.

Clone and configure the stack using the required settings below:

```sh
git clone https://github.com/HoneyBearTech/homelab-selene.git && cd homelab-selene
cp .env.example .env && chmod 600 .env    # then set every required setting
. ./.env && sudo install -d -o 10001 -g 10001 -m 0700 "$CONFIG_ROOT/usas/config"
```

[Restrict port 8080 to the reverse proxy](docs/installing.md#the-firewall) before starting:

```sh
docker compose config --quiet
docker compose up -d --wait
docker compose logs usas                  # the setup code for the first sign-in
```

The full steps are in the [quick start](docs/quick-start.md).

## Usage

```sh
docker compose ps                 # what's running
docker compose logs -f <service>  # one service's log
make check                        # policy check: every image pinned, nothing privileged
scripts/backup.sh                 # back up USAS's data (stops it briefly)
```

Manual backup can interrupt a playbook: check USAS's **History** page first. See
[scheduled backups](docs/installing.md#scheduled-backups) for the busy-run wait, and
[restore and rollback](docs/upgrading.md#rolling-back) for recovery.

Upgrading to a new release, or following `main` the way the maintainer's server does:
[docs/upgrading.md](docs/upgrading.md).

## Configuration

The following settings are required in `.env` (template [`.env.example`](.env.example)), which holds no secrets.

| Setting | Meaning |
| --- | --- |
| `TZ` | Time zone |
| `CONFIG_ROOT` | USAS's data, in `CONFIG_ROOT/usas/config` (uid and gid 10001, mode `0700`) |
| `USAS_BIND_ADDRESS` | The host address port 8080 is published on: the one the reverse proxy reaches |
| `USAS_PUBLIC_URL` | The HTTPS address USAS is opened at, through the proxy; passkeys belong to its host name |
| `USAS_TRUSTED_PROXIES` | The reverse proxy's address, whose forwarded headers USAS believes |

`CONFIG_ROOT` holds every secret USAS has: back it up (`scripts/backup.sh`), encrypt the copy that leaves the
host (`BACKUP_AGE_RECIPIENT`, [installing](docs/installing.md#scheduled-backups)), and never point it into
`/var/lib/docker/volumes`, where `docker volume prune` deletes it
([installing](docs/installing.md#where-data-lives)). autoheal's optional webhook URL (restart notices, for example
to Discord) uses `WEBHOOK_URL` in `autoheal.env` (template [`autoheal.env.example`](autoheal.env.example), mode `600`,
gitignored). Scheduled backup settings use [`backup.env.example`](backup.env.example); see the
[configuration reference](docs/interfaces.md#backupenv) for optional names and meanings.

Ports, volumes and labels: [docs/interfaces.md](docs/interfaces.md).

## Running it securely

- Reach USAS only through a reverse proxy that serves HTTPS, limited to your LAN and VPN. Docker-published ports
  bypass host firewalls such as `ufw`, so a `DOCKER-USER` rule lets only the proxy reach port 8080
  ([the firewall](docs/installing.md#the-firewall)).
- Register passkeys at the public address, then turn on USAS's **Require a passkey**, so the password alone can't
  sign in.
- Give the host nothing else to do: USAS's data is the key to the Proxmox cluster and to every server it built.
  autoheal never gets the Docker socket: it goes through a proxy that only lets it list, inspect, restart and
  stop containers.
- Secrets (the API token, the SSH key, the Vault and its password, the password hash, passkeys, the status token)
  live only in USAS's data, never in this repository or `.env`. Backups contain them: encrypt the copy off the
  host with age, and keep the private key off this host.
- Don't run an auto-updater such as Watchtower on these containers; upgrade from this repository instead (a
  release, or `main`).
- The policy check constrains added capabilities to Docker's default set and refuses privileged containers,
  host networking and Docker socket mounts unless a service documents an explicit exception
  ([docs/security.md](docs/security.md)).

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
