# Bringing the origin home

For most of this project the fleet's memory of *itself* has had a strange dependency baked in.
The tools that let the cluster answer questions about its own history — the log-and-digest RAG,
the daily development digest — all read from a **git mirror**, and that mirror only ever reflected
what had been **pushed to GitHub**. So the fleet could reason about its landed past, but only the
*shipped* past, and only for as long as a human kept pushing its own source code to a third party.
The authoritative copy of the infrastructure lived off-site, on someone else's servers, and the
fleet borrowed it back. That's backwards for a system whose whole point is to be self-contained on
a trusted LAN.

This change flips it. **The NAS is now the fleet's authoritative git origin.** A bare repository
lives on its external disk, served over the machine's *existing* SSH — no new daemon, no new port,
no container. A dedicated service account whose login shell is `git-shell` fronts it: every key on
that account is confined to git commands and nothing else, so a push endpoint on a network-facing
box carries the least authority it can. GitHub isn't abandoned — it's **demoted to an offsite
backup**. A hook fires on every push and mirrors the new commits up to GitHub, but deliberately in
the one shape that can only ever *add* refs, never delete them: a botched local branch-delete or a
history-dropping force-push can't reach out and destroy the offsite copy. And the mirror push is
best-effort — if GitHub is unreachable, the push to the NAS still succeeds, because the NAS is now
the source of truth and GitHub is the echo, not the gate.

The access model is two keys with two authorities. The **workstation** holds a read/write key — it's
where the source actually comes from, and it can push. The **AI/data node**, which keeps the local
mirror the RAG reads, gets a key that is **read-only by construction**: it's pinned to a forced
command that services fetches and *only* fetches, so even a misfired push runs the read path and
fails. Both facts were proven at cutover — the node can pull, and it genuinely cannot push. The
whole thing was designed to be reversible at every step, because GitHub stays a complete replica the
entire time: if any of it had gone wrong, rolling back was just re-pointing a remote.

## What fought back

Three things bit during the cutover, none of them on the plan's happy path.

**Becoming a locked-down user needs a tool nobody had installed yet.** This is the first role in the
whole fleet that has Ansible *become* a purpose-built unprivileged user (the `git` service account)
rather than root or the login user. That handoff quietly relies on POSIX ACLs to pass a temp file to
the new user — and the tool that sets them wasn't present, so the automation fell back to an
ACL-setting syntax the standard `chmod` flatly rejects, with an error that reads like gibberish until
you know the shape of it. One package fixed it. Worth remembering the day a second role does the same
thing.

**A shared address that only resolved on the wrong side of the fleet.** The URL of the new origin is
defined once, so the serving box and the consuming box can't drift apart. But the first spelling of
it leaned on values that only exist *while the serving role is running* — and the consuming node reads
that address from a different machine's context, where those values simply aren't defined. It failed
cleanly the moment it was tested from the far side. Rewritten to depend only on facts every node can
see, it resolved everywhere.

**A dry-run that lied about being converged.** A task that *reads* the current state so a later step
can decide whether to act is invisible under a check-mode dry-run — the read is skipped, comes back
empty, and the downstream step looks like it always has work to do. Left alone it would have reported
a phantom "change" on every future dry-run, quietly poisoning the fleet's zero-changes idempotency
bar. The fix is to let that one read run even in check mode. (A couple of smaller cousins came along
for the ride: a host-key scan that mixes comment lines into its output, and a key-fetch that needed
elevation to read a protected file.)

And one self-inflicted one, filed under *what I'd tell past me*: the cutover renames the workstation's
remotes so the new origin becomes the default. When I went to make the very first real push through
the new path, the renames hadn't actually been applied yet — so the push sailed straight to GitHub and
left the new authoritative origin a commit *behind*, exactly the inversion this whole feature exists to
prevent. It surfaced instantly on a two-line `git remote -v`, was corrected, and re-pushed the right
way. The lesson is small and permanent: when you've just moved where "origin" points, look before you
push. (The other footnote: the backup key authenticated only *after* it was registered on GitHub — the
first mirror push, fired seconds before that click, failed loudly and harmlessly, then succeeded on the
next real push. The best-effort hook design meant that failure never touched anything.)

## Where this points

The feature is deliberately small and self-justifying — it needed nothing after it. But it quietly
unlocks a direction. Now that the fleet's true git source is *on the fleet*, a whole family of "git as
the fleet's nervous system" ideas become cheap: pushing in-flight branches so the memory can reason
about work that hasn't shipped yet; a heavier local clone on the GPU node for on-device search; a real
self-hosted web forge; and the far-off north star — the fleet applying *itself* from its own git
instead of a human running the playbook. None of that is built, and none of it is chartered. But the
door is now on the inside of the house.
