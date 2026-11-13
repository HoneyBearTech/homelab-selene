# homelab-selene documentation

Start with the [README](../README.md) for the USAS provisioning, fleet-update and k3s stack and how to run it.

| Document | For |
| --- | --- |
| [Quick start](quick-start.md) | Getting the stack running on a fresh Docker host |
| [Installing](installing.md) | Host preparation, directory layout, the firewall, moving an existing USAS, running it securely, uninstalling |
| [Upgrading](upgrading.md) | Moving to a new release or a new USAS, manual backups, restore and rollback |
| [Rebuilding](rebuilding.md) | Bringing the stack back on a new or wiped host from a backup |
| [Architecture](architecture.md) | The services, who talks to whom, and how reviewed Renovate updates reach an external pull agent |
| [Interfaces](interfaces.md) | Every setting, port, volume, label and command |
| [Verifying releases](verifying-releases.md) | Checking that release files came from this repository, unchanged |
| [Security requirements](security.md) | What the stack protects, what it doesn't, and where secrets live |
| [Assurance case](assurance-case.md) | The threat model, trust boundaries and why the security requirements are met |
| [Dependencies](dependencies.md) | How images and tools are chosen, pinned, tracked and patched |
| [Roadmap](roadmap.md) | What's planned for the next year, and what homelab-selene will not do |

For a new installation, read [Quick start](quick-start.md), then [Installing](installing.md) for migration,
firewall and proxy details. For daily operation, use [Interfaces](interfaces.md) and
[Scheduled backups](installing.md#scheduled-backups); read [Upgrading](upgrading.md) before changing versions.
To recover, follow [Rolling back](upgrading.md#rolling-back) or [Rebuilding](rebuilding.md) for a new host.

Project policies live at the top of the repository: [CONTRIBUTING.md](../CONTRIBUTING.md),
[GOVERNANCE.md](../GOVERNANCE.md), [SECURITY.md](../SECURITY.md), [SUPPORT.md](../SUPPORT.md),
[CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) and [CHANGELOG.md](../CHANGELOG.md).

These documents change in the same pull request as the behaviour they describe. Anything not built yet is
marked **Planned**. If you find a document that's wrong, please [open an issue](https://github.com/HoneyBearTech/homelab-selene/issues): it's treated as a bug.
