# Roadmap

Where homelab-selene is going over roughly the next twelve months (from October 2026). Plans change; this
file changes with them, in the same pull request.

## Now: the stack in git

- Done: the checks, backup and restore scripts, smoke test, release signing and documentation around the stack,
  from the homelab's stack template.
- Done: `compose.yaml` with USAS, every image pinned by tag and digest for `linux/amd64`, a health check for each
  service, autoheal behind a filtering socket proxy, and the smoke test proving health, backup and restore, and
  autoheal's restarts on amd64 in CI.
- Done: the scheduled backup's copy off the host encrypted with age (`BACKUP_AGE_RECIPIENT`), tested in the smoke
  test.
- Done: USAS excluded from Dependabot's auto-merge; it is bumped by hand after checking its signature.
- **Planned**: the repository on GitHub, with branch protection, Dependabot and the CI secrets.
- **Planned**: first release (0.1.0) before Selene is first deployed, so the server starts from a signed, verified
  version.
- **Planned**: Selene runs the stack from a checkout of this repository, behind the reverse proxy and the firewall
  rule, with the existing USAS data moved over ([installing.md](installing.md#moving-an-existing-usas-here)).
- **Planned**: Selene follows `main` with a pull agent, so a merge deploys within minutes
  ([upgrading.md](upgrading.md#following-main)).

## Next: safe upgrades and rebuilds

- **Planned**: scheduled backups copied off the host, encrypted, reported to a push monitor.
- **Planned**: the documented rebuild ([rebuilding.md](rebuilding.md)) rehearsed on a scratch machine from a real,
  encrypted backup.
- **Planned**: the first USAS upgrade through this repository, following [upgrading.md](upgrading.md#upgrading-usas).

## Later

- A check in CI that the pinned USAS image's cosign signature verifies, so a bump can't merge without it.
- The Vault password outside USAS's data folder (a Docker secret), if it can be kept and backed up separately.

## Security and project health

- Keep CI, CodeQL, Scorecard, dependency review and the DCO check green on every change.
- **Planned**: branch protection on `main` with required checks; private vulnerability reporting; secret scanning
  with push protection.
- **Planned**: the OpenSSF Best Practices **Passing** and **Silver** badges and **OSPS Baseline** Levels 1 and 2
  ([project 15944](https://www.bestpractices.dev/projects/15944); the template meets them).
- **Planned**: signed releases with checksums, SBOM and SLSA provenance, from 0.1.0 on.

## What homelab-selene will not do

- **Build or patch images.** It runs the published images unchanged; bugs in USAS go to its project.
- **Configure USAS's internals** (the inventory, the cluster connection, the servers). Those are set in USAS and
  live in its data, which the backups cover.
- **Store secrets.** No tokens, keys, passwords or Vault files in the repository, encrypted or not.
- **Auto-update from registries.** Every version change is a commit in `main` that passed CI; the server applies
  only those, and a new USAS only after the maintainer checked it.
- **Run other services on this host.** USAS's data is the key to the Proxmox cluster; anything else goes on
  another host.
- **Run the reverse proxy.** It lives on another host, with its own project.
- **Be a general-purpose homelab distribution.** It describes one server; others are welcome to fork or borrow
  from it, but options that only another setup needs are out of scope.
