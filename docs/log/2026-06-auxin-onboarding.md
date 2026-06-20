# 2026-06 — Onboarding the free agent

**Goal:** bring the fourth node — the largest Pi, earmarked as the "free agent" — into
the fleet as a fully managed, observable member, even though its eventual job is still
undecided. Pin it an address, give it the baseline every node carries, and prove its
metrics and logs land where the rest of the fleet's do.

On paper a morning's work: add the node to inventory, run the playbook, done. In
practice the new node was a fresh pair of eyes on infrastructure that older nodes had
last exercised months earlier — and it found three things that had been quietly broken
for weeks.

## The shape of it

The onboarding itself collapsed to almost nothing, on purpose. The membership basics —
package cache, base packages, internal-CA trust, the fleet name map, journal access,
passwordless sudo, pressure metrics, the metrics exporter, the log shipper — got hoisted
into a single baseline that targets the whole fleet, so a new node inherits all of it
just by appearing in inventory. No per-node wiring. The work, then, wasn't the node — it
was everything the node's first real package install and first reboot dragged into the
light.

## Surprise 1 — the cache that wasn't listening

The new node's very first action — a package update through the fleet's package cache —
hung and failed. The cache service on the NAS was *running*, but listening only on
loopback, not on the LAN, so nothing else could reach it. The cause was a boot-order
race: the cache binds a specific LAN address, but its service didn't wait for the
network, so on a cold boot the address didn't exist yet, the bind failed, and only the
loopback listener survived. It had been that way since the NAS last rebooted; nobody
noticed because nothing had asked the cache for anything across a reboot since. Fix:
order the service after the network-online target, so the address exists before it
binds.

## Surprise 2 — the cache that couldn't write

With the cache reachable, the update got *further* and then failed differently: the
Debian mirrors came back fine, but the Raspberry Pi mirror returned a cache error. The
cache could read its existing files but couldn't create new ones for that mirror. The
reason was archaeological: the NAS's storage drive predates a 32-to-64-bit reflash of
that node, and the cache directories from the *old* install were still owned by a user
ID that no longer maps to anything. The daemon could read them but not write into them,
so any *uncached* package — the first request for the Pi mirror — failed the instant it
tried to create a file. Fix: heal ownership across the cache tree (ownership only,
leaving file modes alone), and let the role keep it converged.

## Surprise 3 — the file that wouldn't stay written

The deepest one. Every node is supposed to carry a static name-to-address map for the
fleet, as a fallback for when the resolver isn't available. The new node had it right
after the playbook ran — and lost it on the next reboot. So had two of the three older
nodes, it turned out; the resolver had been quietly covering for a fallback that wasn't
actually there.

The culprit was the image's first-boot provisioning system, which had been told to
manage the hosts file and was faithfully regenerating it from a template *on every
boot*, wiping the fleet's own block. The infuriating part was how many "fixes" didn't
work: a system-level override lost to the higher-priority provisioning seed; editing the
seed itself lost to a *cached copy* of it. What actually held — verified by rebooting and
watching the block survive — was to stop the provisioning system entirely after first
boot. Its only job on this fleet is that first boot (create the user, seed the key, set
the hostname), all of which happens before the fleet's own automation ever connects;
after that it has no role and was only doing harm. A reflash starts clean and provisions
again; the next automation run stands it down again.

This one got written down as a deliberate, documented trade-off — because a disabled
provisioning system is exactly the kind of invisible decision a future debugging session
would waste an hour rediscovering.

## What I'd tell past me

- **A new node is the best test of old infrastructure.** Three bugs latent for weeks all
  surfaced the moment a node exercised the cache and rebooted for the first time. The
  older nodes had simply never re-run the broken paths.
- **"Running" is not "reachable," and "reachable" is not "usable."** The cache was up,
  then reachable, then still couldn't write. Each layer hid the next; only following the
  *actual* error past the generic "it failed" reached the cause.
- **Persistent storage outlives the OS that wrote it.** A drive that survives a reflash
  keeps the old install's ownership and assumptions. State that crosses a rebuild is
  state you have to reconcile on purpose.
- **When something keeps overwriting your file, find who *owns* it — don't try to
  out-edit them.** Three escalating attempts lost to provisioning precedence and a config
  cache before the answer turned out to be taking the other writer out of the loop.
- **Verify the fix the way the bug showed up.** The hosts-file fix only counted once a
  reboot proved the block survived; the earlier attempts had all "succeeded" and then
  failed at the next boot.
- **Make the baseline inheritable.** Onboarding was trivial precisely because membership
  is one fleet-wide baseline, not a per-node checklist. New nodes get it for free; the
  only bespoke work left is a node's actual job.
