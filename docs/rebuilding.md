# Rebuilding the host

How to bring the stack back on a new or wiped machine from a backup made by `scripts/backup.sh` (by hand,
[upgrading.md](upgrading.md#backing-up), or nightly, [installing.md](installing.md#scheduled-backups)), with USAS's
inventory, Vault, SSH key, pinned host keys, sign-in data and run history as they were.

The backup and restore scripts run end to end in CI on every change: the smoke test backs up the running stack,
changes it, restores it and checks the result, and copies a scheduled backup, plain and encrypted with age, to a
stand-in backup server. [Rehearse](#rehearsing-a-rebuild) the steps below on a scratch machine before you need them.

You need: a backup (copied off the old host, or on the backup server), **the age private key** it was encrypted to,
this repository, and a 64-bit amd64 machine; the reference is a **dedicated Ubuntu Server 26.04 VM**.

## 1. The operating system

The reference host is built by USAS itself, with its hardened baseline. When USAS is what's down, that needs
another USAS: start a temporary one from the backup on a workstation (steps 3 to 5 there, as in a
[rehearsal](#rehearsing-a-rebuild)) and build the VM with it, then stop it. Or install Ubuntu Server 26.04 by hand
and run USAS's baseline against it once USAS is back. Then:

```sh
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git rsync curl age pigz
```

Give the machine the same address the old one had, or update everything that reaches it by address: the reverse
proxy's forward for USAS, `USAS_BIND_ADDRESS` in `.env`, the firewall rule, and any Proxmox node that accepts SSH
only from certain addresses.

## 2. Docker

Install Docker Engine and the Compose plugin from Docker's own repository, following
[docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/) (Docker Engine 25 or
later, Compose 2.24 or later). Add your user to the `docker` group, which is equivalent to root on the host, and
log in again:

```sh
sudo usermod -aG docker "$USER"
```

Don't install an auto-updater such as Watchtower ([installing.md](installing.md#running-it-securely)).

## 3. The backup

The copies on the backup server are encrypted; open one on the machine that holds the age private key, never on
the backup server. List the backups (named `<date>-<time>`), copy the newest and check it:

```sh
rsync --list-only backup-host:/volume1/<folder>/
rsync -rlpt backup-host:/volume1/<folder>/<date>-<time>/ ~/sealed/
cd ~/sealed && sha256sum -c --quiet SHA256SUMS && cd -
```

A copy that was cut off has no `SHA256SUMS` (it's sent last): take the one before. Then decrypt it, which gives the
backup directory as it was written on the old host, and copy that to the new host over SSH:

```sh
(umask 077 && age -d -i selene-backup.key ~/sealed/backup.tar.age | tar -x -C ~)   # ~/<date>-<time>/
rsync -rlpt ~/<date>-<time>/ <you>@<the new host>:restore/
rm -rf ~/sealed ~/<date>-<time>
```

On the new host, check it before using it:

```sh
cd ~/restore && sha256sum -c --quiet SHA256SUMS && cd -
cat ~/restore/VERSION      # the release (or commit) the old host ran
```

Keep `~/restore` private: it holds every secret USAS has. (A backup still on the old host's `BACKUP_DIR`, or one
made by hand, isn't encrypted: copy it over SSH and check it the same way.) To reach the backup server from the
new host later, it needs a new backup key and SSH alias, as in [installing.md](installing.md#scheduled-backups)
step 2: the old host's key went with it.

## 4. The repository and settings

```sh
git clone https://github.com/HoneyBearTech/homelab-selene.git && cd homelab-selene
git checkout vX.Y.Z      # the release in VERSION, or newer; verify it (verifying-releases.md)
cp ~/restore/env/.env .env && chmod 600 .env
```

A server that follows `main` ([upgrading.md](upgrading.md#following-main)) stays on `main` here instead
(skip the `git checkout`), and gets its pull agent back once the stack is healthy.

Copy any other file from the backup's `env/` (such as `autoheal.env` and `backup.env`) the same way (mode `600`).
Edit `CONFIG_ROOT` in `.env` if the new host keeps the data elsewhere (never inside `/var/lib/docker/volumes`:
[installing.md](installing.md#where-data-lives)), and `USAS_BIND_ADDRESS` if its address changed. Create USAS's
folder:

```sh
. ./.env && sudo install -d -o 10001 -g 10001 -m 0700 "$CONFIG_ROOT/usas/config"
```

Add the firewall rule before USAS starts ([installing.md](installing.md#the-firewall)). Then:

```sh
docker compose config --quiet && docker compose pull
```

## 5. Restore and start

```sh
scripts/restore.sh ~/restore          # verifies SHA256SUMS, creates the containers, asks first
docker compose up -d --wait           # waits until every service reports healthy
docker compose ps
```

Then check USAS:

- `docker compose logs usas` shows no new setup code (it would mean an empty data folder).
- `sudo ls -ln "$CONFIG_ROOT/usas/config"`: everything belongs to 10001.
- At `USAS_PUBLIC_URL`, through the proxy: the passkeys and the password sign in, the connection test reaches the
  Proxmox cluster, and the inventory and run history are there.
- A dashboard that reads `/api/status` with the status token gets answers again.

## 6. Scheduled backups again

The settings came back with `backup.env`. Create the backup key and SSH alias as in
[installing.md](installing.md#scheduled-backups) step 2, install the timer as in step 6, then run
`scripts/scheduled-backup.sh` once by hand and check that it reaches the backup server and the push monitor.
Delete `~/restore`.

## What the backup doesn't bring back

- **Host settings**: the address, the firewall rule in `/etc/ufw/after.rules`, SSH keys (including the backup key),
  Docker itself.
- **Other machines' view of this one**: the reverse proxy's forward and access list, any Proxmox node that accepts
  SSH from this host's address only, and anything that reaches the host by address.
- **The age private key**: it never was on this host. Without it, no copy off the host can be opened.
- **The Proxmox cluster and the servers**: USAS's backup holds what it knows about them, not the VMs. Back those up
  with Proxmox.

## Rehearsing a rebuild

Run steps 3 to 5 on a scratch machine now and then, so the first real rebuild isn't the first try, and so you
know how long it takes. Any amd64 machine with Docker will do for those steps: a spare VM, or Docker Desktop
(there, put `CONFIG_ROOT` under your home directory in `.env`; macOS checks the backup with `shasum -a 256 -c`
instead of `sha256sum -c`). Use the newest backup, and leave the live host alone.

**A restored USAS is the real one**: it holds the live Proxmox API token, the SSH key the nodes and servers trust,
and the Vault. It can create and wipe VMs like the live one. In a rehearsal:

- set `USAS_BIND_ADDRESS=127.0.0.1` in the scratch machine's `.env`, so nothing else can reach it;
- don't run a playbook, a connection test or anything else that reaches the cluster: two USAS at once is a race;
- don't copy `autoheal.env` or `backup.env`, and don't install the timer: they'd post to your restart channel and
  write to the backup server;
- stop it and remove everything as soon as the checks are done.

Before you start, clear what would clash with the stack on the scratch machine, and put it back afterwards:
**container names** are fixed (`usas`, `autoheal`, `socket-proxy`), and **port** 8080 must be free on the bind
address.

The checks for a rehearsal: every service healthy, no new setup code in `docker compose logs usas`, and the files in
`CONFIG_ROOT/usas/config` owned by 10001.

Note how long each step took and anything this page got wrong or left out, and fix the page in a pull request.
Then remove everything the rehearsal created; it all holds secrets:

```sh
. ./.env && docker compose down
sudo rm -rf "$CONFIG_ROOT/usas" ~/restore .env ./*.env
```

Then put back anything you renamed, stopped or removed for the rehearsal.
