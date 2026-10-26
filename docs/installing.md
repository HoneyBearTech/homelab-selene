# Installing

The [quick start](quick-start.md) is the short version of this page.

## Requirements

- Linux on amd64 with Docker Engine and the Compose v2 plugin (Docker Engine 25 or later and Compose 2.24 or
  later, for the health checks' `start_interval`). The reference host is a **dedicated Ubuntu Server 26.04 VM**,
  built by USAS itself with its hardened baseline (UFW, Fail2Ban, SSH keys only, unattended upgrades), that runs
  nothing but this stack. Install Docker from Docker's own repository
  ([docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/)).
- A user in the `docker` group to run `docker compose`. Membership is equivalent to root on the host, so keep
  that group small: here, root on the host means USAS's secrets.
- A reverse proxy on another host that serves HTTPS under a host name for USAS (`USAS_PUBLIC_URL`) and forwards to
  `USAS_BIND_ADDRESS:8080`. USAS is never opened over plain HTTP from the network.
- Little disk: USAS's data is small (its run history grows by a log per run).
- `flock` (util-linux, on Ubuntu by default) if the host runs the pull agent ([Deploy lock](#deploy-lock)).
- `age` if the backups are copied off the host encrypted ([Scheduled backups](#scheduled-backups)).
- `CONFIG_ROOT/usas/config` owned by uid and gid 10001, mode `0700`: USAS runs as that user and keeps every
  secret it has there.

## Where data lives

Every service keeps its data in its own folder under one directory, `CONFIG_ROOT` (the one required path setting):
its settings and database in `CONFIG_ROOT/<service>/config`, and any other folder of its own beside that. Here only
USAS has data.

| What | Where on the host | In the container |
| --- | --- | --- |
| USAS's inventory, Vault and Vault password, SSH key and pinned host keys, the cluster's CA, password hash, passkeys, status token and run history | `CONFIG_ROOT/usas/config` | `/data` |

```
$CONFIG_ROOT/
  usas/config/          # owned by 10001:10001, mode 0700
```

USAS stores its container paths (`/data/...`), not the host's, so `CONFIG_ROOT` can move between hosts. Details in
[interfaces.md](interfaces.md#volumes-and-mounts).

> **Never point `CONFIG_ROOT` (or any other path setting) into `/var/lib/docker/volumes`, and don't keep USAS's
> data in a named Docker volume.** `docker volume prune` and `docker system prune --volumes` delete every volume
> that no container mounts *as a volume*, and that includes a volume whose `_data` folder a service bind-mounts by
> its path: Docker counts it as unused and deletes the data under the running service. Keep the data in a
> directory of your own under `CONFIG_ROOT` (`/srv`, say), which no Docker cleanup touches.

## Installing

1. Clone the repository (or download a release's source archive and verify it,
   [verifying-releases.md](verifying-releases.md)).
2. Create `.env` from `.env.example` (mode `600`) and set every value. Optionally create `autoheal.env` from
   `autoheal.env.example` (mode `600`) with a webhook URL for restart notices.
3. Create USAS's folder: `. ./.env && sudo install -d -o 10001 -g 10001 -m 0700 "$CONFIG_ROOT/usas/config"`. A
   folder you didn't create is created by Docker, owned by root, and USAS can't write to it. To move an existing
   USAS here, fill the folder now ([Moving an existing USAS here](#moving-an-existing-usas-here)).
4. Add the firewall rule ([The firewall](#the-firewall)), then `docker compose up -d --wait`.
5. Point the reverse proxy at USAS ([Behind the reverse proxy](#behind-the-reverse-proxy)), open
   `USAS_PUBLIC_URL` and sign in with the setup code from `docker compose logs usas`.

The maintainer's server runs `main` rather than a release, and deploys every merge by itself
([upgrading.md](upgrading.md#following-main)). For your own setup, a release is the safer choice.

### The firewall

Docker publishes `USAS_BIND_ADDRESS:8080` with its own iptables rules, which run before UFW's: a published port is
open to every machine that can reach that address, whatever `ufw status` says, and a `ufw allow` or `ufw deny`
rule for 8080 has no effect on it. Docker's `DOCKER-USER` chain is the place for rules that do apply. It sees a
connection after Docker has rewritten its destination (DNAT) to the container's address and port, so the rules
below match the destination the client asked for, which conntrack remembers (`--ctorigdst`, `--ctorigdstport`),
not the rewritten one. That also keeps them from touching USAS's own outgoing connections.

Add this at the end of `/etc/ufw/after.rules` (after the `COMMIT` that ends UFW's own `*filter` section), with
your values: `192.0.2.20` is `USAS_BIND_ADDRESS`, `192.0.2.10` the reverse proxy.

```text
# homelab-selene: only the reverse proxy reaches USAS (USAS_BIND_ADDRESS:8080). Docker-published ports bypass
# UFW's own rules; DOCKER-USER sees them after DNAT, so match the original destination.
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -p tcp -m conntrack --ctorigdst 192.0.2.20 --ctorigdstport 8080 --ctdir ORIGINAL -s 192.0.2.10 -j RETURN
-A DOCKER-USER -p tcp -m conntrack --ctorigdst 192.0.2.20 --ctorigdstport 8080 --ctdir ORIGINAL -j DROP
-A DOCKER-USER -j RETURN
COMMIT
```

Then load it and look at the chain:

```sh
sudo ufw reload
sudo iptables -L DOCKER-USER -n -v      # the three rules, with packet counters
```

The first rule lets the proxy through, the second drops every other connection to port 8080 (replies to the
proxy's connections travel the other way and aren't matched), and the third hands everything else back to Docker's
own rules. UFW loads the file at every boot and keeps the chain across `ufw reload`; Docker leaves an existing
`DOCKER-USER` chain as it is. The rules are for Docker's default iptables firewall backend. If you publish USAS on
an IPv6 address too, add the same rules to `/etc/ufw/after6.rules` (with `ip6tables`).

Test it from both sides:

```sh
nc -zv -w 5 192.0.2.20 8080     # from the reverse proxy's host: "succeeded"
nc -zv -w 5 192.0.2.20 8080     # from any other machine on the LAN: times out
```

Then open `USAS_PUBLIC_URL` through the proxy. The counters in `sudo iptables -L DOCKER-USER -n -v` show which
rule each attempt met.

### Behind the reverse proxy

- **One host name, HTTPS only.** The proxy host for the name in `USAS_PUBLIC_URL` forwards to
  `http://<USAS_BIND_ADDRESS>:8080` and passes on the `Host`, `X-Forwarded-Proto` and `X-Forwarded-For` headers.
  USAS answers only to that name (and to `localhost`, for its health check), believes the forwarded headers only
  from `USAS_TRUSTED_PROXIES`, and always marks its session cookie Secure. The hop from the proxy to USAS is plain
  HTTP: keep it on a network you trust.
- **An access list.** Let the proxy accept requests for USAS only from your LAN and VPN. Nothing outside needs it,
  and its sign-in is the door to your Proxmox cluster.
- **Passkeys.** Passkeys belong to the host name in `USAS_PUBLIC_URL`: register them on the **Account** page while
  you're at that address. Once every device you use has one, turn on **Require a passkey**, so the password alone
  no longer signs in. If the host name ever changes, register the passkeys again at the new one.

### Moving an existing USAS here

If USAS already runs somewhere else (on a workstation, say), move its data rather than starting empty: it holds the
inventory, the Vault and its password, the SSH key the nodes and servers trust, and the run history. **Never start
USAS here on an empty data folder if you mean to move data**: it would make a new setup code and a new Vault
password, and a later copy over them mixes two setups. Move the data before the first `docker compose up`.

1. **On the old host**, stop USAS so nothing changes during the copy, then archive its data with the numeric
   owners and the modes kept. For a named volume (`usas-data` in USAS's own instructions):

   ```sh
   docker stop usas
   docker run --rm --network none -v usas-data:/data:ro -v "$PWD:/out" busybox:1.38.0 \
     tar --numeric-owner -cpf /out/usas-data.tar -C /data .
   ```

   For data in a directory, `sudo tar --numeric-owner -cpf usas-data.tar -C <the directory> .` does the same. Leave
   the old container stopped, not removed, until USAS works here.
2. **Copy the archive to this host over SSH only** (`scp usas-data.tar <you>@<this host>:`): it holds every secret
   USAS has. Not through a shared folder, a chat or a mail.
3. **On this host**, extract it into the new folder as 10001:10001, keeping the modes:

   ```sh
   . ./.env && sudo install -d -o 10001 -g 10001 -m 0700 "$CONFIG_ROOT/usas/config"
   sudo tar --numeric-owner -xpf ~/usas-data.tar -C "$CONFIG_ROOT/usas/config"
   sudo chown -R 10001:10001 "$CONFIG_ROOT/usas/config" && sudo chmod 0700 "$CONFIG_ROOT/usas/config"
   sudo ls -ln "$CONFIG_ROOT/usas/config"     # auth.json, inventory, ssh, ... owned by 10001 10001
   ```

4. **Start the stack** (`docker compose up -d --wait`). `docker compose logs usas` must show no new setup code: if
   it does, the data didn't land in the folder. Stop the stack, fix the folder, and start again.
5. **Check it**, at `USAS_PUBLIC_URL`: sign in with the old password; the connection test reaches the Proxmox
   cluster; the inventory and the run history are there. The nodes now see SSH from this host's address: if a node
   only accepts SSH from certain addresses, allow this one there first.
6. **Passkeys must be registered again**, on the new name: the old ones belong to the old host name. Remove them on
   the **Account** page, add new ones, then turn on **Require a passkey**.
7. **A dashboard's status token keeps working**, but its URL changes: point the dashboard at
   `USAS_PUBLIC_URL/api/status`.
8. Once everything works here, remove the old container and its data, and delete `usas-data.tar` on both
   machines.

## Scheduled backups

`scripts/scheduled-backup.sh` takes a backup (`scripts/backup.sh`), copies it to another machine with rsync
(encrypted with age, when `BACKUP_AGE_RECIPIENT` is set), keeps only the newest few in both places and reports to a
push monitor. A systemd timer runs it nightly. Every setting is in the optional `backup.env`
([interfaces.md](interfaces.md#backupenv)). The backups hold every secret USAS has: the Proxmox API token, the SSH
key the nodes trust, the Vault and its password. Copy them off the host only encrypted.

1. **On the backup server**, create a folder for the backups and a user that can write only there and use rsync
   over SSH (on a Synology: a shared folder, a non-admin user with read/write on that folder only, rsync allowed
   under Application Privileges, SSH on, the rsync service on under File Services, and the user home service on so
   the user can have an `authorized_keys`). Whoever controls this host can delete or overwrite what it copied
   there, so keep older versions where the backup user can't reach them: snapshots of the folder, or a versioned
   copy of it made on the server after the nightly backup (on a Synology without Btrfs, a Hyper Backup task with
   rotation, into a folder the backup user has no access to). A recycle bin isn't enough: Synology's doesn't keep
   files deleted over rsync.
2. **On this host**, as the user who runs the stack, install rsync, curl and age (and pigz, which compresses the
   archives on every core instead of one), and create a key used only for the backups, with an alias for it in
   `~/.ssh/config`:

   ```sh
   sudo apt install -y rsync curl age pigz
   ssh-keygen -t ed25519 -N '' -f ~/.ssh/homelab-selene-backup
   ```

   ```text
   Host backup-host
     HostName <the backup server's address>
     User <the backup user>
     IdentityFile ~/.ssh/homelab-selene-backup
     IdentitiesOnly yes
   ```

   Add the public key to the backup user's `~/.ssh/authorized_keys` on the server, prefixed with
   `restrict,from="<this host's address>"` (no shell or forwarding, and only from this host), then check that
   `rsync --list-only backup-host:/volume1/<folder>/` works without a password prompt.
3. **The encryption key**, on another machine you trust (not this host): `age-keygen -o selene-backup.key`. It
   prints the public key (`age1...`). Keep the key file where you keep your other recovery secrets, such as a
   password manager, and never copy it to this host: without it no backup off the host can be read, and with it
   any of them can.
4. **Settings**: `cp backup.env.example backup.env && chmod 600 backup.env`, then set
   `BACKUP_REMOTE=backup-host:/volume1/<folder>`, `BACKUP_AGE_RECIPIENT=age1...` and, optionally, the retention and
   `BACKUP_PING_URL`. For the ping, add a monitor of type **Push** in Uptime Kuma (or a monitor like it) with a
   heartbeat interval of 25 hours, and copy its URL.
5. **Try it**: `scripts/scheduled-backup.sh`. USAS stops only while its data is archived, for seconds. The copy
   off the host is then one folder per backup holding only `backup.tar.age` and its `SHA256SUMS`; the backup
   itself stays readable here, in `BACKUP_DIR`. On a host that follows `main` with the pull agent
   ([upgrading.md](upgrading.md#following-main)), the backup first waits for a deploy in progress to finish and
   then holds the agent's lock, so no deploy starts while USAS is stopped ([Deploy lock](#deploy-lock)).
6. **Schedule it**, with the systemd user units in [`deploy/systemd/`](../deploy/systemd/) (they expect the
   checkout at `~/homelab-selene`; edit both paths in the `.service` file if it's elsewhere). Lingering lets the
   timer run while you're logged out:

   ```sh
   mkdir -p ~/.config/systemd/user
   cp deploy/systemd/homelab-selene-backup.* ~/.config/systemd/user/
   sudo loginctl enable-linger "$USER"
   systemctl --user daemon-reload
   systemctl --user enable --now homelab-selene-backup.timer
   systemctl --user list-timers homelab-selene-backup.timer     # next run: 04:30, plus up to 10 minutes
   journalctl --user -u homelab-selene-backup                   # what the last runs did
   ```

Restore a copy from the backup server as [rebuilding.md](rebuilding.md) describes: decrypt it with the private key
(`age -d -i selene-backup.key backup.tar.age | tar -x`), which gives the backup directory `scripts/restore.sh`
reads. Check the copy's `SHA256SUMS` first; a copy that was cut off has none yet (it is sent last), and
`restore.sh` refuses a backup directory without its own.

### Deploy lock

`scripts/backup.sh` and `scripts/restore.sh` share a lock with the pull agent that deploys `main` on the
maintainer's server ([upgrading.md](upgrading.md#following-main)). Before they stop anything they wait for a
running deploy to finish (up to 30 minutes, then they fail without having stopped anything), and they hold the lock
until they exit; the agent skips its runs while the lock is taken and deploys on its next run after it. The lock is
the agent's own file, `selene/lock` in its state root (`$HOMELAB_PULL_STATE_DIR`, else
`$XDG_STATE_HOME/homelab-pull`, else `~/.local/state/homelab-pull`). Where that directory doesn't exist (no agent,
CI, a workstation) the scripts take no lock; where it does, they need `flock` (util-linux).
[interfaces.md](interfaces.md#environment) lists the variables.

## Running it securely

- **USAS only through the proxy.** Publish it only on `USAS_BIND_ADDRESS`, let only the proxy reach it
  ([The firewall](#the-firewall)), and limit the proxy's host for it to the LAN and VPN with an access list.
  Docker-published ports bypass `ufw`, so the `DOCKER-USER` rule is what keeps others out.
- **Passkeys, then require them.** Register passkeys at `USAS_PUBLIC_URL` and turn on **Require a passkey**. Until
  then, anyone who can reach the sign-in page can try the password (USAS slows them down, but doesn't stop them).
- **Nothing else on the host.** Anyone with root or `docker` access here can read USAS's data: the Proxmox API
  token, the SSH key the nodes and servers trust, the Vault and its password. Run no other service on this host,
  keep the `docker` group to the stack's user, and keep SSH to keys only.
- Keep `.env` at mode `600`; it holds no secrets by design, but it describes your host.
- Keep `autoheal.env` at mode `600`: it holds the webhook URL.
- autoheal never gets the Docker socket: it goes through `socket-proxy`, which only lets it list, inspect,
  restart and stop containers, on an internal network.
- Back up USAS's data (`scripts/backup.sh`), and schedule it with an encrypted copy off the host
  ([Scheduled backups](#scheduled-backups)). The age private key stays off this host.
- Keep `backup.env` at mode `600`: it holds the push monitor's URL. The backup key in `~/.ssh` should open only the
  backup user's account on the backup server, and that account should reach only the backup folder.
- Don't add services that mount the Docker socket, run privileged or use the host network without a documented
  reason; the policy check refuses them ([security.md](security.md)).
- Don't run an auto-updater (such as Watchtower) on these containers: it would replace the pinned, reviewed
  versions with whatever a tag points to today. A new USAS is checked by hand
  ([upgrading.md](upgrading.md#upgrading-usas)).

## Uninstalling

```sh
docker compose down          # stops and removes the containers and the stack's networks
```

`CONFIG_ROOT` is left untouched. Remove it by hand (`sudo rm -rf "$CONFIG_ROOT/usas"`) if you no longer want
USAS's data; it holds the Proxmox API token, the SSH key and the Vault. If USAS is gone for good, also revoke its
API token in Proxmox VE and remove its public key from the nodes' and servers' `authorized_keys`, and remove the
firewall rule from `/etc/ufw/after.rules`.
