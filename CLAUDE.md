# homelab-selene Guidelines

Docker Compose stack for Selene running USAS (`ubuntu-server-auto-setup` web UI) on an amd64 Ubuntu Server 26.04 VM. Deployed via `homelab-ops` pull agent (`homelab-pull@selene`). Default branch: `main`.

> **STRICT**: AI anonymity required. No mention of Claude, Anthropic, or AI assistance in committed files, PRs, git history, or docs.

## Public Safety & Architectural Hard Rules
- **Public Repo Invariants**: Zero internal hostnames, IPs, LAN paths, secrets, or personal emails in code, docs, tests, or commits. Host details belong in Chronos notes.
- **Image Pinning**: Every image must be pinned as `name:tag@sha256:<digest>`. Dependabot auto-merges patch/minor/major/rebuilds for `socket-proxy` and `autoheal` only. **USAS updates ALWAYS wait for the owner.**
- **Hardening & Topology**: No privileged containers, added capabilities, or host network/PID without explicit owner approval. USAS is reached strictly through the reverse proxy (`USAS_BIND_ADDRESS:8080`).
- **Data Layout**: Services must use `${CONFIG_ROOT}/<service>/config` (e.g. `${CONFIG_ROOT}/usas/config` -> `/data`, 10001:10001). Zero named volumes.

## Notes & State Tracking
- Read `~/Chronos/Projects/homelab-selene/` before structural changes: `roadmap.md`, `Pass-Map.md`, `Architecture.md`, `Security-Considerations.md`, `Decisions-Log.md`.
- Update Chronos files as work lands. Notes **never** enter this code repo.

## Deploys & Merging
- **Auto-Deploy on Merge**: Merges to `main` auto-deploy via pull agent within ~2 minutes (`docker compose pull && docker compose up -d --wait`). Rollback via revert PR.
- **Locking**: `deploy_lock` in `scripts/lib.sh` ensures backups and deploys do not run concurrently.
- **Commits & PRs**: DCO signed-off (`git commit -s`), email `31805425+HoneyBearTech@users.noreply.github.com`.
- Required CI check names: `CI / Checks + tests`, `CI / Stack smoke test`.

## Core Commands

```sh
# Linting & Security Verification
make lint     # ruff check, ruff format --check, yamllint --strict, shellcheck -x
make test     # Python checker unit tests + coverage floor check (offline)
make check    # Policy validation check on compose.yaml (requires .env)

# Deployment Verification
make config   # Print resolved docker compose config
make smoke    # Run stack smoke test (throwaway stack, health check, backup/restore test)
