# Dependencies and vulnerability management

How homelab-selene chooses, obtains, tracks and updates what it's built from, and what happens when one of
those dependencies has a vulnerability.

homelab-selene's dependencies are almost entirely the **container images** it runs: USAS, autoheal and the socket
proxy. The rest are the tools its checks and tests use and the GitHub Actions in its workflows. Its own code, the
policy checker, uses only the Python standard library.

## Choosing a dependency

A new image or tool must:

- be open source under an OSI-approved license (the services' own licenses apply to them: homelab-selene pins and
  runs them, it doesn't redistribute or link them);
- be actively maintained: releases in the last year, security issues answered, and **published for
  `linux/amd64`**, the host's architecture;
- come from the project itself, from its official registry; and
- be worth it: a new service needs a reason in the pull request that adds it. This host runs USAS and what keeps
  it running, nothing else: anything more gets access to the host that holds USAS's secrets.

## Obtaining dependencies

| Dependency | Declared in | Pinned by | Fetched by |
| --- | --- | --- | --- |
| The stack's images | [`compose.yaml`](../compose.yaml) | version tag and digest | `docker compose pull` |
| Check and test tools (pytest, coverage, ruff, yamllint, shellcheck) | [`requirements-dev.in`](../requirements-dev.in) → [`requirements-dev.txt`](../requirements-dev.txt) | exact version and SHA-256 hashes (`pip-compile --generate-hashes`) | `pip install --require-hashes --no-deps` |
| Helper image for backups and the smoke test (busybox) | [`scripts/lib.sh`](../scripts/lib.sh) | version tag and digest | Docker |
| Linters and scanners used only by CI (actionlint, gitleaks, Trivy) | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), [`scan.yml`](../.github/workflows/scan.yml) | version tag and digest | Docker |
| age, for the smoke test's encrypted backup copy | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | the runner's Ubuntu package | `apt-get` |
| GitHub Actions | [`.github/workflows/`](../.github/workflows/) | full commit SHA (version in a comment) | GitHub Actions |
| Images of the GitLab copy's pipeline (Python, Docker CLI, git, gitleaks, actionlint) | [`.gitlab-ci.yml`](../.gitlab-ci.yml) | version tag and digest | GitLab Runner (Docker executor) |

On the host, the scheduled backup uses rsync, curl, age and pigz from Ubuntu's archive, kept current by unattended
upgrades.

Each release carries a CycloneDX SBOM listing every service's image and digest
([verifying-releases.md](verifying-releases.md)). To update the pinned Python tools, edit
`requirements-dev.in` if needed and run `pip-compile --generate-hashes --strip-extras requirements-dev.in`.

## Tracking dependencies

- **Renovate** ([`renovate.json`](../renovate.json)) proposes updates before 6am on Monday in
  `America/Chicago`. Its managers cover Compose at the root, both `requirements-dev.in` and
  `requirements-dev.txt` at the root, GitHub Actions, GitLab CI images and the busybox assignment in
  `scripts/lib.sh`. This retains the former Dependabot docker-compose `/`, pip `/` and github-actions `/`
  coverage, including the recommended grouping for the CodeQL action family.
- **Minor and patch updates are grouped** into one proposal. Major updates remain separate and add the `major`
  label to the global `dependencies` label. Digest updates remain enabled outside the minor/patch group;
  existing image pins are preserved. Vulnerability alerts carry `security`, and OSV alerts are enabled.
- **Every update requires manual review and merge**, including major updates and digest-only image rebuilds.
  Required checks still apply: CI with the Compose policy check and smoke test, CodeQL and dependency review.
  Renovate has `automerge: false`; the retained Dependabot auto-merge workflow does not enable it for Renovate.
- **USAS signature checks still apply**: the maintainer reads the release notes, verifies the image's cosign
  signature by pinned digest and takes a backup ([upgrading.md](upgrading.md#upgrading-usas)).
- **A merge deploys.** The maintainer's server follows `main` with a pull agent, so each reviewed merge reaches
  it within about two minutes ([upgrading.md](upgrading.md#following-main)). Read release notes and take a backup
  before merging; retain the nightly [scheduled backup](installing.md#scheduled-backups).
- **Dependency review** ([`.github/workflows/dependency-review.yml`](../.github/workflows/dependency-review.yml))
  blocks a pull request that adds or changes a Python or Actions dependency with a known vulnerability of
  moderate severity or higher, or a license outside the allowlist.
- CI-only images embedded in workflow `run:` steps still need manual checks at least quarterly; GitLab CI and
  the scripts' busybox image are now covered by Renovate.
- **Nothing on the host updates from a registry.** Auto-updaters such as Watchtower are not used: the pull agent
  only applies commits reviewed and merged into `main`.

After merge, the owner must install or enable Renovate for this repository. Repository security settings have
not been changed by this migration. Disable *Dependabot security updates* (keep *Dependabot alerts*) in Settings → Code security.

## Policy for vulnerabilities in dependencies

Known vulnerabilities are found through Dependabot alerts, the services' and images' own advisories, and a
weekly scan of the pinned digests ([`scan.yml`](../.github/workflows/scan.yml): Trivy, HIGH and CRITICAL
findings that have a fix, for `linux/amd64`, reported to code scanning with one category per image). Each
finding is triaged within 14 days:

1. **If a fixed version exists**, bump to it (a Renovate pull request may already propose it; a reviewed manual merge
   deploys it to the maintainer's server) and release it for those who run releases. A fix for an
   exploitable critical or high-severity vulnerability goes out in a patch release within 30 days; others go out
   with the next release.
2. **If upstream hasn't released a fix**, assess whether it's reachable in this stack (USAS is reachable only
   from the reverse proxy, behind its sign-in; autoheal and the socket proxy publish nothing). If it is, mitigate
   it where possible and say so in the release notes; otherwise record the reason in the triage below. Either way,
   it's fixed by a bump when upstream ships one. A finding in USAS is also reported to its project.
3. **If an image is abandoned** and keeps accumulating vulnerabilities, replace it.

### Current findings

None. The first weekly image scan (2026-10-26) found no HIGH or CRITICAL finding with a fix in any of the three
images, so there is nothing to triage. Findings are left open in code scanning rather than dismissed, so they close
by themselves when an update ships the fix.

**autoheal** (`willfarrell/autoheal`): the complete [public tag listing](https://hub.docker.com/v2/repositories/willfarrell/autoheal/tags?page_size=100)
inspected on 2026-11-13 contained six tags and no next page. `latest` was updated that day; the newest numbered
tag, `1.2.0`, was last updated in July 2021. No maintained numbered alternative was available. The existing
`latest@sha256:…` reference and policy exception remain frozen; choosing `1.2.0` would downgrade to an old release.
The current upstream `latest` digest differs from the repository's pin and is not adopted here. The listing
omits index digests for old numbered tags, so exact index aliasing is not established; no running version was
inspected. Renovate can propose digest updates for manual review. A future maintained numbered tag can be
considered separately.

## Licenses

homelab-selene's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff or shellcheck finding fails
CI; a deliberate exception is a per-line `noqa` or `shellcheck disable` with the reason next to it.
