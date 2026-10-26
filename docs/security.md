# Security requirements

What homelab-selene is meant to guarantee, what it leaves to the operator and the services, and where secrets
live. The reasoning behind these requirements is in the [assurance case](assurance-case.md).

## What homelab-selene protects

1. **Only reviewed versions run.** Every image is pinned as `name:tag@sha256:<digest>`. A registry tag
   that is moved or hijacked doesn't change what `docker compose pull` fetches; a new version arrives only
   as a pull request that changes the digest. A new USAS is merged only by hand, after its cosign signature is
   checked by digest ([upgrading.md](upgrading.md#upgrading-usas)).
2. **No container gets more of the host than it needs.** Every service drops every Linux capability, adds back
   only the ones its image needs (never more than Docker's default set) and can't gain privileges from setuid
   binaries or file capabilities. No service runs privileged, shares the host's network or PID namespace, or
   mounts the Docker socket (which is root on the host), unless the exception is written into the service as a
   reasoned label and reviewed. Where an image allows it, its root filesystem is read-only
   ([Hardening](#hardening)).
3. **USAS is reachable only through the reverse proxy.** Its port is published only on `USAS_BIND_ADDRESS`, a
   `DOCKER-USER` rule lets only the proxy reach it, it answers only to the host name in `USAS_PUBLIC_URL`, and it
   believes forwarded headers only from `USAS_TRUSTED_PROXIES` ([installing.md](installing.md#the-firewall)).
4. **No secrets in the repository.** USAS keeps the Proxmox API token, its SSH key, the Vault and its password,
   the password hash, passkeys and the status token in its own data, outside the repository. `.env` holds settings
   only. Secret scanning with push protection and a gitleaks scan of the whole history in CI back this up.
5. **No host details in the repository.** It is public: no hostnames, IP addresses, domains or host paths are
   committed. Examples use placeholders.
6. **Releases are verifiable.** Release files are listed in a `SHA256SUMS` signed keylessly by the release
   workflow, with SLSA provenance and an SBOM of the pinned images ([verifying-releases.md](verifying-releases.md)).
7. **Backups don't leak.** `scripts/backup.sh` writes archives readable only by the user who ran it. With
   `BACKUP_AGE_RECIPIENT` set, the scheduled copy off the host is encrypted to an age key whose private half
   isn't on this host, so the backup server holds nothing it can read. `scripts/restore.sh` writes only the mounts
   the backup's checksummed `MANIFEST` lists and the service still has, never the Docker socket.

## Policy

`scripts/check_compose.py` enforces requirements 1 and 2 on the resolved Compose file in CI and before
every release. A service may break a rule only with the label `org.honeybeartech.selene.allow.<rule>` and a
non-empty reason:

| Rule | Fails when a service |
| --- | --- |
| `image` | has no `image` |
| `digest` | uses an image without both a tag and a `sha256` digest |
| `latest` | uses the `latest` tag |
| `build` | builds an image instead of pulling a pinned one |
| `privileged` | sets `privileged: true` |
| `no-new-privileges` | doesn't set `security_opt: [no-new-privileges:true]` |
| `cap-drop` | doesn't drop every capability (`cap_drop: [ALL]`) |
| `cap-add` | adds a capability outside Docker's default set (adding back one of those only narrows the default) |
| `host-network` / `host-pid` | uses the host's network or PID namespace |
| `docker-socket` | mounts the Docker socket |
| `devices` | maps a host device into the container (a GPU reservation under `deploy.resources` is allowed) |
| `healthcheck` | has no health check, or disables it (one defined only in the image isn't visible to the check) |

## Hardening

What each service runs with, beyond the policy. Every service has `cap_drop: [ALL]` and
`no-new-privileges:true`; the smoke test proves each one still starts healthy and survives a backup and restore
with these settings.

| Service | Capabilities added back | Read-only root filesystem | Why |
| --- | --- | --- | --- |
| usas | none | yes (`/tmp`, `/home/usas` in memory) | Runs as uid 10001 and writes only its data directory and temporary files, as in USAS's own Compose file |
| autoheal | none | yes | Only talks to socket-proxy |
| socket-proxy | none | yes (`/run`, `/tmp` in memory) | Only reads the socket |

autoheal and socket-proxy still run as root inside their containers, since their images offer nothing else.
Without capabilities that root can only reach what it owns.

## What it doesn't protect

- **USAS itself.** A vulnerability in USAS is its project's to fix
  ([its security policy](https://github.com/HoneyBearTech/ubuntu-server-auto-setup/blob/main/SECURITY.md));
  homelab-selene ships the fixed version once it's released and checked ([dependencies.md](dependencies.md)).
- **USAS's reach.** USAS holds a Proxmox API token that can create, configure and wipe VMs, and an SSH key that the
  Proxmox nodes and every server it set up trust. Anyone who controls USAS, its data or this host controls those.
  This is why the host runs nothing else.
- **Access to USAS.** Its password, its passkeys and **Require a passkey** are the operator's to set
  ([installing.md](installing.md#behind-the-reverse-proxy)). Until a passkey is required, anyone who reaches the
  sign-in page can try the password. homelab-selene doesn't add single sign-on.
- **The reverse proxy.** It holds USAS's TLS certificate and sees every request in the clear; the access list that
  keeps USAS on the LAN and VPN is configured there, not in this repository. The hop from the proxy to USAS is
  plain HTTP on the network between them, which is trusted.
- **autoheal's reach.** autoheal never holds the socket: `socket-proxy` does (the one allowed `docker-socket`
  exception) and passes on only listing, inspecting, restarting and stopping containers, on an internal network
  with no published port. Whoever controls autoheal or the proxy can still stop any container on the host and read
  containers' settings, including their environment; this stack keeps no secrets in environment variables.
- **Restart loops.** autoheal restarts an unhealthy service every few minutes for as long as it stays unhealthy;
  that keeps a hung service available but can hide a real fault, and a restart cuts off a playbook USAS is
  running. Restarts are logged (and sent to the webhook if one is set).
- **Backups off the host from the host itself.** The scheduled backup can delete old backups on the backup
  server, so whoever controls this host can delete or overwrite them too (though not read them, when they're
  encrypted). Snapshots or a versioned copy on the backup server, outside this host's reach, are what protect them;
  a recycle bin may not see deletions made over rsync (Synology's doesn't). The backups in `BACKUP_DIR` on the host
  aren't encrypted.
- **The age private key.** Whoever has it can read every backup copied off the host; whoever loses it can read
  none. Keeping it is the operator's job.
- **The host.** Anyone with root, `docker` group membership or write access to `.env` or USAS's data controls the
  stack, and with it the Proxmox cluster; those are trusted.
- **Upstream images' internals.** Some images run as root inside the container; that is the image's design and
  is accepted where the image offers nothing else.

## Where secrets live

| Secret | Where | Never in |
| --- | --- | --- |
| The Proxmox VE API token, the servers' admin password (and any mail relay password, webhook URL or disk passphrase set in USAS) | USAS's Vault (`inventory/group_vars/all/vault.yml`) in `CONFIG_ROOT/usas/config` | the repository, `.env`, issues, logs you paste |
| The Vault password | USAS's `.vault-pass`, beside the Vault | same |
| USAS's SSH private key (trusted by the Proxmox nodes and every server it set up) | USAS's `ssh/` | same |
| USAS's password hash (argon2id) and passkeys | USAS's `auth.json` and `passkeys.json` | same |
| The status token | only its HMAC in USAS's `status-token.json`; the token itself in the dashboards that use it | same |
| autoheal's webhook URL | `autoheal.env` (mode `600`, gitignored) | same |
| The backup push monitor's URL | `backup.env` (mode `600`, gitignored) | same |
| The key for the backup server | the backup user's `~/.ssh` on the host | same |
| The age private key for the backups | off this host, with the operator's recovery secrets | this host, the backup server, anywhere public |
| Backups of the data | on the host mode `600`; off the host encrypted with age | anywhere public |
