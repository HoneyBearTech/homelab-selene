# Assurance case

Why homelab-selene meets its [security requirements](security.md): the threat model, the trust boundaries,
the secure design principles it follows, and how common weaknesses are countered.

## Threat model

| Asset | Threat | Countered by |
| --- | --- | --- |
| The host | A compromised or malicious image | Digest pins; versions change only by reviewed pull request; no privileged, capability, host-namespace or socket access without a reasoned label |
| The Proxmox cluster and every server USAS set up | A tampered or malicious USAS image | USAS is never auto-merged; the maintainer checks its cosign signature by digest against USAS's release workflow before bumping it ([upgrading.md](upgrading.md#upgrading-usas)) |
| The Proxmox cluster and every server USAS set up | Someone reaching USAS's sign-in from the network | Port published only on `USAS_BIND_ADDRESS`; a `DOCKER-USER` rule lets only the reverse proxy reach it; the proxy's access list limits it to the LAN and VPN; USAS answers only to its public host name; passkeys required ([installing.md](installing.md#the-firewall)) |
| USAS's sessions | Traffic intercepted, or forwarded headers forged | HTTPS at the proxy; Secure session cookie; USAS believes `X-Forwarded-*` only from `USAS_TRUSTED_PROXIES` |
| The API token, SSH key, Vault and its password | Committed to the public repository | Kept in USAS's data, never in the repo; `.gitignore`; gitleaks over the history in CI; GitHub push protection |
| The API token, SSH key, Vault and its password | Leaked through a backup | `scripts/backup.sh` writes backups readable only by the user who ran it; the copy off the host is encrypted with age to a key that isn't on the host |
| USAS's data | An upgrade that rewrites and breaks it | `scripts/backup.sh` nightly, and before every USAS update; rollback = a revert (or the old tag) + `scripts/restore.sh`, both exercised by the CI smoke test |
| The host | A bad change merged to `main` deploying by itself | The required checks (policy check, smoke test on amd64) pass before any merge; USAS updates and updates Dependabot can't classify are merged by hand; the pull agent only fast-forwards and backs out a change that doesn't resolve or pull; rollback is a revert pull request |
| The host | A container breaking out through the Docker socket | The `docker-socket` rule; only socket-proxy mounts it, read-only, as a labelled exception; autoheal reaches Docker only through socket-proxy, which allows listing, inspecting, restarting and stopping containers, on an internal network |
| Availability | USAS hangs without exiting | A health check on every service; autoheal restarts an unhealthy one (and can notify a webhook); a long start period keeps it from interrupting a start-up |
| USAS's data | A crafted backup writing outside the services' data | `restore.sh` verifies `SHA256SUMS` (which covers the `MANIFEST`), accepts only plain archive names and absolute container paths without `..`, refuses the Docker socket, and writes only a mount the service has read-write |
| The release | Tampered release files | Keyless-signed `SHA256SUMS`, SLSA provenance, signed tags |
| The CI pipeline | Untrusted pull request input running with credentials | `pull_request` only, read-only token by default, untrusted values only via `env:`, actions pinned by SHA |
| Operator privacy | Hostnames, addresses, domains or paths in the public repo | Placeholders only; reviewed in every pull request |

Attackers considered: a compromised upstream image or registry tag; someone on the LAN reaching USAS's port or
sign-in; someone on the internet reaching the proxy; someone who obtains a backup copy; a malicious pull request; a
tampered backup. Out of scope: an attacker who already has root or `docker` group access on the host, or write
access to `.env` or USAS's data, and an attacker who controls the reverse proxy.

## Trust boundaries

1. **Registries → host.** Images are trusted only at the digest a reviewed commit names; USAS's also only after its
   signature was checked.
2. **Repository → host.** The maintainer's host runs `main`: a pull agent fetches it and only fast-forwards,
   refusing rewritten history and local changes, so the host never runs code that wasn't merged.
   Nothing connects in to the host to deploy. (Others can run a tagged, signed release instead.)
3. **Network → USAS.** Only the reverse proxy reaches port 8080 (the `DOCKER-USER` rule); the proxy serves HTTPS
   and admits only the LAN and VPN. USAS then requires its own sign-in, with passkeys.
4. **Containers → host.** Only USAS's folder under `CONFIG_ROOT` is mounted; no host namespaces. The one socket
   mount (socket-proxy, which autoheal reaches only on an internal network) is a reviewed, labelled exception.
5. **Selene → Proxmox cluster and servers.** USAS holds the API token and the SSH key they trust, and checks them in
   turn: the API against the cluster's CA, each node and VM against its pinned host key.
6. **Host → backup server.** Only an encrypted archive leaves; the host can write and delete copies there but not
   read them back.
7. **Pull requests → CI.** Fork pull requests get a read-only token and no secrets. The project's one
   secret, a Docker Hub token that can only read public images, is logged out before the smoke test starts
   any container.

## Secure design principles

- **Least privilege**: every capability dropped and none added back, no new privileges, read-only root
  filesystems, no host namespaces, one documented read-only socket mount, read-only CI tokens raised per job.
- **Fail-safe defaults**: the policy check fails on anything it doesn't recognise as allowed; an exception
  needs a reason, in the file, in review. `restore.sh` refuses anything in a backup it can't account for. USAS's
  port is dropped for everyone but the proxy.
- **Complete mediation**: every change to what runs passes through a pull request and the same checks;
  the host only fast-forwards to merged commits.
- **Economy of mechanism**: one Compose file, one standard-library checker, upstream images unchanged.
- **Separation of privilege**: secrets live with USAS, settings in `.env`, configuration in git; the key that opens
  the backups lives elsewhere.
- **Open design**: the whole configuration, policy and release process are public.

## Common weaknesses

| Weakness | Where it could arise | How it's countered |
| --- | --- | --- |
| CWE-494 (code downloaded without integrity check) | Image pulls | Digest pins; USAS's cosign signature checked by digest; signed release checksums |
| CWE-798 / CWE-312 (hard-coded or cleartext credentials) | Compose `environment:`, `.env`, docs, backups | No secrets in the repo; gitleaks; push protection; backups encrypted off the host |
| CWE-250 (unnecessary privileges) | Container settings | Policy rules `privileged`, `no-new-privileges`, `cap-drop`, `cap-add`, `host-*`, `docker-socket`; read-only root filesystems; USAS as uid 10001 |
| CWE-1393 (default passwords) | USAS's first start | USAS has no default password: its first sign-in needs a one-time setup code from its log ([quick-start.md](quick-start.md)) |
| CWE-284 (improper access control) | Docker-published ports bypassing UFW | A `DOCKER-USER` rule for port 8080, documented with a test from an allowed and a refused machine ([installing.md](installing.md#the-firewall)) |
| CWE-22 (path traversal) | Restoring a backup | `restore.sh` validates archive names and mount paths from the checksummed `MANIFEST` |
| CWE-1104 (unmaintained third-party components) | Images, tools, Actions | Dependabot weekly; image scan; triage SLAs ([dependencies.md](dependencies.md)) |
| CWE-77/78 (injection) | Workflows, scripts | Untrusted values only via `env:`; actionlint and shellcheck; CodeQL for Actions; `backup.env` read as data, never sourced |
| CWE-20 (improper input validation) | The checker's input | It reads JSON only with the standard library, never evaluates it, and exits 2 on anything that isn't a JSON object |

## Evidence

- CI on every change: ruff (with the bandit rules), yamllint, actionlint, gitleaks over the history,
  shellcheck, pytest with a 90 % branch-coverage floor, `docker compose config`, the policy check, and a smoke
  test on amd64 that starts every pinned image, waits for its health check, round-trips a backup and restore,
  checks the encrypted copy off the host (only the archive leaves, the right key opens it, another doesn't) and
  proves that autoheal restarts an unhealthy container (a dynamic test of the stack and the scripts).
- A weekly Trivy scan of every pinned image, and on every change to `compose.yaml`, into code scanning.
- CodeQL (Python and Actions) on every pull request and weekly; OpenSSF Scorecard weekly; dependency
  review on every pull request.
