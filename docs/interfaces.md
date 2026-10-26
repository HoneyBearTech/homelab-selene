# Interfaces

Everything homelab-selene reads, exposes or runs. homelab-selene has no HTTP API of its own; USAS's web UI and
API are documented by its project
([ubuntu-server-auto-setup's interfaces](https://github.com/HoneyBearTech/ubuntu-server-auto-setup/blob/main/docs/interfaces.md)).

## Settings

### `.env`

Read by `docker compose` from `.env` next to `compose.yaml` (template: [`.env.example`](../.env.example)). Every
setting is required: `docker compose` stops with an error naming any that's missing.

| Setting | Example | Meaning |
| --- | --- | --- |
| `TZ` | `Etc/UTC` | Time zone (tz database name) for logs and schedules. |
| `CONFIG_ROOT` | `/srv/config` | Host directory holding every service's data, one folder per service (`CONFIG_ROOT/<service>/config`; see [Volumes and mounts](#volumes-and-mounts)). Here only USAS's, `CONFIG_ROOT/usas/config`, owned by uid and gid 10001 with mode `0700`. Never a path inside `/var/lib/docker/volumes` ([installing.md](installing.md#where-data-lives)). |
| `USAS_BIND_ADDRESS` | `192.0.2.20` | The host address USAS's port 8080 is published on: the one the reverse proxy reaches. The `DOCKER-USER` rule lets only the proxy in ([installing.md](installing.md#the-firewall)). |
| `USAS_PUBLIC_URL` | `https://usas.example.com` | The HTTPS address USAS is opened at, through the reverse proxy (with `:port` if it isn't 443). USAS answers only to its host name (and to `localhost`), and passkeys belong to it: they must be registered again when it changes. |
| `USAS_TRUSTED_PROXIES` | `192.0.2.10` | The reverse proxy's address (comma-separated if several). USAS believes the `X-Forwarded-Proto` and `X-Forwarded-For` headers only from it. |

No secret is a setting. To move an existing USAS here, copy its data into `CONFIG_ROOT/usas/config` before the first
start ([installing.md](installing.md#moving-an-existing-usas-here)).

### `autoheal.env`

Read by the `autoheal` service (template: [`autoheal.env.example`](../autoheal.env.example)); optional, mode
`600`, gitignored.

| Setting | Meaning |
| --- | --- |
| `WEBHOOK_URL` | Where autoheal posts a notice each time it restarts a container (a secret). A Discord channel webhook works as is; empty or missing = log only |

### `backup.env`

Read by `scripts/scheduled-backup.sh` (template: [`backup.env.example`](../backup.env.example)); optional, mode
`600`, gitignored. Read as data, never run: only these keys, one `KEY=value` per line; anything else is an error.

| Setting | Default | Meaning |
| --- | --- | --- |
| `BACKUP_DIR` | `backups` | Where backups are written (relative to the checkout, or absolute). |
| `BACKUP_KEEP` | `3` | How many backups are kept in `BACKUP_DIR`; older ones are deleted. |
| `BACKUP_REMOTE` | empty | rsync destination each backup is copied to, such as `backup-host:/volume1/selene-backups` (an SSH alias); empty = no copy. |
| `BACKUP_REMOTE_KEEP` | `30` | How many backups are kept at `BACKUP_REMOTE`; older ones are deleted. |
| `BACKUP_AGE_RECIPIENT` | empty | An age public key (`age1...`). When set, the copy at `BACKUP_REMOTE` is only `backup.tar.age` (the backup directory as one tar archive, encrypted to that key) and its `SHA256SUMS`; `age -d -i <private key> backup.tar.age \| tar -x` gives back the backup directory that `scripts/restore.sh` reads. Needs `age` on the host. Empty = the backup is copied as it is. |
| `BACKUP_BUSY_TIMEOUT` | `14400` | How long, in seconds, the backup waits while USAS runs a playbook (`scripts/backup-stack.sh`): stopping USAS would end the run. After that it fails without stopping anything. `0` = don't wait. |
| `BACKUP_BUSY_INTERVAL` | `60` | How often, in seconds, it looks again while USAS is busy. |
| `BACKUP_PING_URL` | empty | A push monitor's URL, such as Uptime Kuma's (a secret), told `up` after each good run and `down` after a failed one. |

Only directories named like a backup (`<date>-<time>`) are ever deleted, here or at the remote.

### Environment

Read by `scripts/backup.sh` and `scripts/restore.sh` for the [deploy lock](installing.md#deploy-lock) they share
with the pull agent; nothing needs setting on a normal host.

| Variable | Default | Meaning |
| --- | --- | --- |
| `HOMELAB_PULL_STATE_DIR` | `$XDG_STATE_HOME/homelab-pull` | The pull agent's state root, as the agent reads it. If it has no `selene` directory, no lock is taken. |
| `XDG_STATE_HOME` | `~/.local/state` | Used for the state root when `HOMELAB_PULL_STATE_DIR` isn't set. |

## Services and ports

| Service | Image | Host port → container | What |
| --- | --- | --- | --- |
| `usas` | `honeybeartech/ubuntu-server-auto-setup` | `USAS_BIND_ADDRESS`:8080 → 8080 | USAS's web UI and JSON API over HTTP, behind its sign-in; HTTPS is the reverse proxy's. `/healthz` (open) is the health check; `/api/status` answers dashboards that hold the status token |
| `autoheal` | `willfarrell/autoheal` | none | Restarts any labelled service whose health check fails |
| `socket-proxy` | `lscr.io/linuxserver/socket-proxy` | none (internal network `docker-proxy`) | Filtered Docker API for autoheal |

USAS's port is published only on `USAS_BIND_ADDRESS`, and a `DOCKER-USER` rule lets only the reverse proxy reach
it ([installing.md](installing.md#the-firewall)). Every service has a health check (`docker compose ps` shows it).
Exact versions and digests are in [`compose.yaml`](../compose.yaml).

## Volumes and mounts

Every service's data is in a host directory under `CONFIG_ROOT`; the stack declares no Docker volumes.

| Container path | Host source | Service |
| --- | --- | --- |
| `/data` | `CONFIG_ROOT/usas/config` | usas: the inventory, the Vault and its password, the SSH key and pinned host keys, the cluster's CA, the password hash, passkeys, the status token's HMAC and the run history. Owned by uid and gid 10001, which USAS runs as, mode `0700` |
| `/tmp`, `/home/usas` | in memory (tmpfs) | usas: temporary files and Ansible's home; the root filesystem is read-only. Not backed up |
| `/run`, `/tmp` | in memory (tmpfs) | socket-proxy |
| `/var/run/docker.sock` | the Docker socket | socket-proxy (read-only); an allowed exception, see below |

## Networks

| Network | Who | Meaning |
| --- | --- | --- |
| `default` | usas, autoheal | The stack's own network; USAS reaches the Proxmox nodes, the new VMs and the internet through it |
| `docker-proxy` | socket-proxy, autoheal | Internal: no route out, nothing published |

## Labels

| Label | Meaning |
| --- | --- |
| `org.honeybeartech.selene.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `no-new-privileges`, `cap-drop`, `cap-add`, `host-network`, `host-pid`, `docker-socket`, `devices`, `healthcheck` ([security.md](security.md#policy)). In use: `socket-proxy` (`docker-socket`), `autoheal` (`latest`). |
| `autoheal` | `"true"` on every service autoheal may restart when its health check fails: usas and socket-proxy. |
| `org.honeybeartech.selene.backup.skip` | Container paths (comma-separated, exact) that `scripts/backup.sh` never archives and `scripts/restore.sh` refuses to write, even if a backup lists them: data too large to back up here or disposable. Not in use. |
| `org.honeybeartech.selene.backup.exclude` | Paths inside a service's data mounts (comma-separated, exact container paths, at any depth) that `scripts/backup.sh` leaves out of the mount's archive and `scripts/restore.sh` leaves in place. A path that isn't inside one of the service's data mounts, or contains `..` or a pattern character (`*?[\`), makes both fail before anything stops. Not in use. |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |
| `scripts/backup.sh [DIR]` | Archives every service's data mounts (every read-write volume or bind mount except the Docker socket, anonymous volumes and the paths in the service's `backup.skip` label; a mount inside another mount is archived on its own and left out of the outer archive), `.env` and any `<service>.env` into `DIR` (default `backups/<date>-<time>`, gitignored) with a `MANIFEST`, `NETWORKS` (the address range of each network the stack uses but doesn't create; none here), `VERSION` (the checkout's `git describe`) and `SHA256SUMS`, all mode `600`. Each service is stopped only while its own mounts are copied and started again (with any service Compose stopped along with it) before the copies are compressed (with `pigz` when it's installed, else `gzip`). Leaves out the paths a service's `org.honeybeartech.selene.backup.exclude` label lists. Waits for a deploy by the pull agent and holds its lock until it exits ([deploy lock](installing.md#deploy-lock)). If stopping a service fails while its container is still on its way down (a process stuck writing to a network share can outlast Docker's stop), it waits up to `BACKUP_STOP_WAIT` seconds (default 120) for the container to exit and carries on; if it still runs then, the backup fails, and the services are started again only after a second wait. Fails, naming them, if any service that was running when it began isn't running again at the end. Exit 0 = backup complete |
| `scripts/scheduled-backup.sh` | Runs `scripts/backup.sh` into `BACKUP_DIR/<date>-<time>`, copies it to `BACKUP_REMOTE` with rsync (`SHA256SUMS` last; with `BACKUP_AGE_RECIPIENT`, only the encrypted `backup.tar.age` and its `SHA256SUMS`), deletes all but the newest `BACKUP_REMOTE_KEEP` there and `BACKUP_KEEP` here, and reports to `BACKUP_PING_URL` ([`backup.env`](#backupenv)). First it waits while USAS runs a playbook (a web UI run whose record in `/data/runs` says `running`, or an `ansible-playbook` process in the container; `scripts/backup-stack.sh`), up to `BACKUP_BUSY_TIMEOUT`, and stops nothing until the run has ended. Run nightly by the systemd user units in `deploy/systemd/`. Exit 0 = backup complete and copied |
| `scripts/restore.sh [--yes] DIR [SERVICE...]` | Verifies `DIR/SHA256SUMS`, checks the `MANIFEST`, creates missing containers, asks for confirmation (unless `--yes`), stops the services, recreates a container made from an older `compose.yaml` (a missing directory is created), replaces the contents of what the service mounts at each listed container path now with its archive (owners and modes kept; a backup of a Docker volume restores into the directory that replaced it), and starts what was running. Writes only mounts the service still has read-write; never the Docker socket, a path in the service's `backup.skip` label, another mount inside the one it restores, or a path in its `backup.exclude` label. A service that bind-mounts a folder inside a mount it restores is stopped and started again with it, so it doesn't keep the replaced folder. Takes the pull agent's lock first, as `backup.sh` does. An encrypted copy is decrypted first ([rebuilding.md](rebuilding.md#3-the-backup)) |
| `make smoke` | `scripts/smoke-test.sh`: starts every service under a separate Compose project with throwaway directories (`CONFIG_ROOT` among them), volumes and networks, no fixed container names, no published ports and no env files; waits until all are healthy, round-trips a backup and restore over every data mount (one service's through a recreated container into a config directory that was removed; a test container that mounts a folder inside another service's data is started again with it), runs the scheduled backup against a stand-in backup server (and, when `age` is installed, the encrypted copy: only the archive and its checksums leave, the right key opens it, another key doesn't), makes a test container unhealthy and checks that autoheal restarts it, then removes what it created. A stack's own steps, when it has any, are in `scripts/smoke-stack.sh` (`smoke_prepare`, `smoke_check`); a `*_SUBNET` setting gets a free address range. Exit 0 = all passed |

## Outbound connections

From the host: the image registries (Docker Hub, `lscr.io`) on `docker compose pull`. From USAS: the Proxmox VE
API of the nodes (port 8006, HTTPS, checked against the cluster's CA it was given); SSH to the Proxmox nodes (to
remaster the installer ISO) and to the new VMs (for the baseline), each checked against its pinned host key;
GitHub, for the admin's public SSH keys. The nodes, not USAS, download the Ubuntu installer ISO and its signed
checksums from Ubuntu's release mirrors, and the new VMs reach Ubuntu's archive for their packages. From autoheal:
its webhook, if one is set. The scheduled backup to `BACKUP_REMOTE` (rsync, usually over SSH) and to
`BACKUP_PING_URL`, if they are set.

Inbound: only the reverse proxy, to `USAS_BIND_ADDRESS:8080`, and SSH to the host for its administrator.

## Release files

Each GitHub Release has `homelab-selene-<version>.tar.gz` (source, with `LICENSE`),
`homelab-selene-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore bundle,
and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
