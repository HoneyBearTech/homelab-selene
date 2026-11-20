# Decisions log

Why things are the way they are: each entry gives the decision, the reason and
what was turned down. Newest first. What shipped is in the [pass
map](pass-map.md).

## 2026-11-20: Renovate merges its own pull requests

Job `renovate-automerge` (#28).

**Decision.** Renovate merges its pull requests itself once every check passes,
majors included; new versions wait 3 days, security fixes and image rebuilds
don't, on the model homelab-atlas already uses. Kept manual: the server-setup
image stays manual (its own pull request). `platformAutomerge` is true.

**Why.** The owner asked for every repo with Renovate to merge its updates
automatically (2026-11-20) and chose this model, majors included, over keeping
majors manual.

**Not done.** Repository settings and branch rules (owner only) and workflows
are unchanged. A group merges automatically only when every update in it may, so
each manual exception gets its own pull request.

**Review findings.** Fixed: stale docs that still promised a manual review or
named Dependabot, and (where it applied) exceptions that sat inside the update
group. None declined.
