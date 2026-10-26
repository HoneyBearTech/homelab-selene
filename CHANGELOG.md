# Changelog

All notable changes to homelab-selene are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- The stack for Selene, a dedicated Ubuntu Server 26.04 (amd64) host: USAS 0.6.0, the web UI of
  ubuntu-server-auto-setup, with autoheal behind a filtering socket proxy. Every image is pinned by tag and digest,
  every service drops every capability and can't gain privileges, and has a health check. USAS runs as uid 10001
  with a read-only root filesystem, keeps everything in `CONFIG_ROOT/usas/config`, and is published only on
  `USAS_BIND_ADDRESS:8080`, for the reverse proxy that serves it over HTTPS at `USAS_PUBLIC_URL`
  (`USAS_TRUSTED_PROXIES`).
- The settings `TZ`, `CONFIG_ROOT`, `USAS_BIND_ADDRESS`, `USAS_PUBLIC_URL` and `USAS_TRUSTED_PROXIES`
  (`.env.example`).
- The tooling shared by the homelab's stacks: the policy check, backup and restore scripts, the pull agent's deploy
  lock, the scheduled backup with its systemd units, the smoke test, CI, the image scan and signed releases.
- An encrypted copy off the host for the scheduled backup: with `BACKUP_AGE_RECIPIENT` (an age public key) in
  `backup.env`, only `backup.tar.age` and its `SHA256SUMS` leave the host, and only the private key's holder can
  read them (`age -d -i <key> backup.tar.age | tar -x`). Needs `age` on the host. The smoke test checks that only the
  archive leaves, that the key opens it into the backup `scripts/restore.sh` reads, and that another key doesn't.
- Documentation for the host: the `DOCKER-USER` firewall rule that lets only the reverse proxy reach USAS (Docker's
  published ports bypass UFW), passkeys and **Require a passkey** behind the proxy, and moving an existing USAS's
  data here ([installing.md](docs/installing.md)).

### Security

- USAS is excluded from Dependabot's auto-merge, rebuilds included: a new USAS can change how it creates VMs and
  what its baseline does to them, so it is bumped by hand after checking its cosign signature by digest
  ([upgrading.md](docs/upgrading.md#upgrading-usas)). autoheal's and the socket proxy's updates still merge
  automatically once every required check passes.
