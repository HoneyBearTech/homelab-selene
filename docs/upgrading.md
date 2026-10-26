# Upgrading

A homelab-selene release changes which image versions run, and sometimes the services or settings. USAS may
rewrite its inventory or Vault when it starts a new version, and an older version may not read them afterwards,
so **every upgrade starts with a backup**. The same steps apply to updating a checkout of `main` by hand; the
maintainer's server follows `main` automatically instead, where the merge is the upgrade
([Following `main`](#following-main)).

## Before you upgrade

1. Read the release notes (the `CHANGELOG.md` section) for every release between yours and the new one, and
   USAS's own changelog for any USAS version it brings. Anything under **Upgrading** needs action.
2. Verify the new release ([verifying-releases.md](verifying-releases.md)), and USAS's image if it changes
   ([Upgrading USAS](#upgrading-usas)).
3. Don't upgrade while USAS is running a playbook: the restart cuts the run off. Its **History** page shows what's
   running.

## Backing up

The state worth keeping is USAS's data: the folder it mounts from `CONFIG_ROOT` (its inventory, Vault and Vault
password, SSH key and pinned host keys, the cluster's CA, sign-in data and run history). `scripts/backup.sh` stops
USAS, copies its folder while it is stopped so nothing changes under the copy, and starts it again if it was
running before compressing the copy; autoheal and socket-proxy have nothing to archive and keep running. It also
copies `.env` and any `<service>.env` (such as `autoheal.env`):

```sh
scripts/backup.sh                       # into backups/<date>-<time>/ in the checkout (gitignored)
scripts/backup.sh /path/to/backup-dir   # or a directory of your choice (new or empty)
```

If stopping a service fails while its container is still on its way down (a process stuck writing to a network
share can outlast Docker's stop), the backup waits up to `BACKUP_STOP_WAIT` seconds (default 120) for it to exit,
then carries on. If it still runs then, the backup fails, but starts the services again only after waiting once
more, so Compose doesn't skip a container that is about to exit. A backup that leaves any service down that was
running when it began fails and names it.

The directory holds one `<service>--<path>.tar.gz` per mount (here `usas--data.tar.gz`), the settings under
`env/`, a `MANIFEST` naming each archive's service, container path, volume or host path and image, `NETWORKS`
(empty here: the stack creates every network it uses), `VERSION` (the checkout's `git describe`) and `SHA256SUMS`.
Everything in it is readable only by the user who ran the backup. **Copy it off the host only encrypted**: it
contains the Proxmox API token, the SSH key the nodes and servers trust, and the Vault with its password. Every
service needs a container for the backup to read from, so run it on an installed stack. The Docker socket and
anonymous volumes are never archived. [Scheduled backups](installing.md#scheduled-backups) do this nightly and copy
each backup off the host, encrypted with age.

## Upgrading

```sh
git fetch --tags
git checkout vX.Y.Z
docker compose pull
docker compose up -d --wait
docker compose ps
```

Then check USAS's log (`docker compose logs usas`) for errors, sign in at `USAS_PUBLIC_URL`, and run its connection
test against the Proxmox cluster.

### Upgrading USAS

A new USAS can change how it creates VMs and what its baseline does to them, so it is never merged automatically,
not even a rebuild of the same version: Dependabot opens the pull request, and the maintainer checks it and merges
it by hand (or bumps the image in a pull request of their own).

1. **Read USAS's release notes** for every version between the pinned one and the new one: its `CHANGELOG.md`, and
   its upgrading notes ([upgrading.md](https://github.com/HoneyBearTech/ubuntu-server-auto-setup/blob/main/docs/upgrading.md)).
   Look for renamed settings, changed defaults and anything the baseline now changes on existing servers.
2. **Check the image's signature, by the digest the pull request pins**, as USAS's
   [verifying-releases.md](https://github.com/HoneyBearTech/ubuntu-server-auto-setup/blob/main/docs/verifying-releases.md)
   describes. With [cosign](https://docs.sigstore.dev/cosign/system_config/installation/) 3.0 or later:

   ```sh
   cosign verify docker.io/honeybeartech/ubuntu-server-auto-setup@sha256:<digest> \
     --certificate-identity-regexp '^https://github\.com/HoneyBearTech/ubuntu-server-auto-setup/\.github/workflows/release\.yml@refs/tags/v' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```

   It proves that USAS's release workflow pushed exactly that image, from a version tag. The digest must also be
   the one in that release's `images.txt` (which the release's signed `SHA256SUMS` covers): a tag can move, a
   digest can't.
3. **Bump the tag and the digest together** in `compose.yaml`
   (`honeybeartech/ubuntu-server-auto-setup:X.Y.Z@sha256:<digest>`), in a pull request that links the release notes and says whether the new version rewrites USAS's data. CI runs
   the policy check and the smoke test on it.
4. **Take a backup** on the server (`scripts/backup.sh`), then merge. On a server that follows `main`, the merge
   deploys it within about two minutes.
5. **Check it**: sign in, run the connection test, open the **VMs** page and the run history. Before running the
   new baseline against a server that matters, preview it on one server first, as USAS's upgrading notes describe.

## Following `main`

The maintainer's server doesn't check out releases: it runs `main`, and a small pull agent (kept in the
maintainer's private orchestration repository, not here) deploys every merge. A systemd user timer starts it about
every 90 seconds; when `main` has moved, it fast-forwards the checkout, runs `docker compose config --quiet`,
`docker compose pull` and `docker compose up -d --remove-orphans --wait`, and logs the old and the new commit. So
**a merge to `main` reaches the server within about two minutes**, including the updates Dependabot merges by
itself ([dependencies.md](dependencies.md#tracking-dependencies)).

- The agent only fast-forwards: it refuses a checkout with local changes or a `main` whose history was rewritten.
  If the configuration doesn't resolve or an image can't be pulled, it moves the checkout back, so the server keeps
  running what it ran.
- **Backups and deploys take turns.** `scripts/backup.sh` and `scripts/restore.sh` hold the agent's lock while
  they run, and wait for a deploy in progress to finish before they stop anything, so the nightly backup never
  races a merge; the agent deploys on its first run after they finish
  ([Deploy lock](installing.md#deploy-lock)).
- **The merge is the upgrade.** autoheal's and socket-proxy's updates, majors included, merge by themselves;
  USAS's never do ([Upgrading USAS](#upgrading-usas)). Before merging an update by hand, read the release notes
  and take a backup on the server (`scripts/backup.sh`).
- **Rolling back** is a revert pull request, deployed the same way. If USAS already rewrote its data, restore that
  too ([Rolling back](#rolling-back)).
- **Holding the server on a version**: check out that commit or release on the server (`git checkout vX.Y.Z`).
  The agent pauses while the checkout isn't on `main`, and carries on once it's switched back (`git switch main`).

## Rolling back

If USAS fails after the upgrade, go back to the previous version **and** restore its data; data a newer USAS
rewrote may not load in the older one.

```sh
git checkout vPREVIOUS
scripts/restore.sh backups/YYYYMMDD-HHMMSS usas   # checks SHA256SUMS, lists what it replaces, asks first
docker compose up -d usas
```

On a server that follows `main`, revert the change with a pull request instead of checking out the old release
(the merge deploys the old version), then restore USAS's data the same way. Runs made between the backup and the
restore drop out of USAS's history, and VMs it created meanwhile stay in Proxmox: check the cluster against the
restored inventory.

`scripts/restore.sh` replaces everything in each of the service's mounts listed in the backup's `MANIFEST`,
keeping the files' owners and modes. Without service names it restores every service in the backup. It stops
those services while it works and starts again the ones that were running; `--yes` skips the question.

A backup copied off the host is encrypted to the age key in `BACKUP_AGE_RECIPIENT`: restoring from it needs **the
age private key**, which is kept off this host. Decrypt it first
([rebuilding.md](rebuilding.md#3-the-backup)); the backups in `BACKUP_DIR` on the host aren't encrypted.

## Restoring on a new host

See [rebuilding.md](rebuilding.md): install the host, decrypt the backup with the age private key, restore `.env`,
then `scripts/restore.sh` creates the containers and fills USAS's folder under `CONFIG_ROOT` from the backup.
