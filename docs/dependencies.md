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

- **Dependabot** ([`.github/dependabot.yml`](../.github/dependabot.yml)) checks weekly for new image
  versions in the Compose file, new tool versions and new Action versions, and opens a pull request for
  each. Dependabot alerts and security updates are on.
- **Patch, minor and major updates merge automatically**
  ([`.github/workflows/dependabot-auto-merge.yml`](../.github/workflows/dependabot-auto-merge.yml)): for
  autoheal's and the socket proxy's images, the Python tools and the GitHub Actions, they're squash-merged once
  every required check has passed (CI with the Compose policy check and the smoke test, CodeQL, dependency
  review). Nothing skips a check, and a failing update stays open for the maintainer.
- **Image rebuilds merge automatically too**: a pull request that only moves an image to a new digest under the
  same tag (a rebuild of the same app version, with newer base packages) and changes nothing else in `compose.yaml`.
- **USAS is never merged automatically**, not even a rebuild: a new USAS can change how it creates VMs and what
  its baseline does to them. The maintainer reads its release notes, checks the image's cosign signature by the
  pinned digest, and merges by hand after a backup ([upgrading.md](upgrading.md#upgrading-usas)).
- **Major updates merge automatically** for the other images (the maintainer's decision, 2026-10-14, the same in
  every homelab stack), so they reach the maintainer's server unattended, with the nightly backup behind them.
- **Merged by hand**: every USAS update, and any update Dependabot can't classify as patch, minor or major.
- **A merge deploys.** The maintainer's server follows `main` with a pull agent, so every merge, the automatic
  ones included, reaches it within about two minutes ([upgrading.md](upgrading.md#following-main)). So every
  automatic merge relies on the nightly [scheduled backup](installing.md#scheduled-backups), and the
  maintainer takes a backup before merging the updates that wait.
- **Dependency review** ([`.github/workflows/dependency-review.yml`](../.github/workflows/dependency-review.yml))
  blocks a pull request that adds or changes a Python or Actions dependency with a known vulnerability of
  moderate severity or higher, or a license outside the allowlist.
- The CI-only images in `run:` steps, the images in `.gitlab-ci.yml` and the scripts' busybox image aren't seen
  by Dependabot; they're bumped by hand at least every quarter.
- **Nothing on the host updates from a registry.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed. The pull agent only applies commits merged into `main`.

## Policy for vulnerabilities in dependencies

Known vulnerabilities are found through Dependabot alerts, the services' and images' own advisories, and a
weekly scan of the pinned digests ([`scan.yml`](../.github/workflows/scan.yml): Trivy, HIGH and CRITICAL
findings that have a fix, for `linux/amd64`, reported to code scanning with one category per image). Each
finding is triaged within 14 days:

1. **If a fixed version exists**, bump to it (a Dependabot pull request usually already does; the merge deploys
   it to the maintainer's server, by hand for USAS) and release it for those who run releases. A fix for an
   exploitable critical or high-severity vulnerability goes out in a patch release within 30 days; others go out
   with the next release.
2. **If upstream hasn't released a fix**, assess whether it's reachable in this stack (USAS is reachable only
   from the reverse proxy, behind its sign-in; autoheal and the socket proxy publish nothing). If it is, mitigate
   it where possible and say so in the release notes; otherwise record the reason in the triage below. Either way,
   it's fixed by a bump when upstream ships one. A finding in USAS is also reported to its project.
3. **If an image is abandoned** and keeps accumulating vulnerabilities, replace it.

### Current findings

**Planned**: the first triage, after the first weekly image scan once the repository is on GitHub. Findings are
left open in code scanning rather than dismissed, so they close by themselves when an update ships the fix.

**autoheal** (`willfarrell/autoheal`): its only maintained tag is `latest` (its versioned tags stop at 1.2.0 from
2021), so it is pinned as `latest@sha256:…` with a policy exception; if Dependabot doesn't propose new digests for
it, it's bumped by hand with the other hand-pinned images.

## Licenses

homelab-selene's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff or shellcheck finding fails
CI; a deliberate exception is a per-line `noqa` or `shellcheck disable` with the reason next to it.
