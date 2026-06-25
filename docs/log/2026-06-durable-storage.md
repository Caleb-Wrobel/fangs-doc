# 2026-06 — Durable storage: getting state off the SD card

**Goal:** the whole fleet boots from **microSD** — convenient, reflashable, and *not* something to
trust with data you can't recompute. Once the cluster started holding real, compute-expensive state
(a database, telemetry history, an incident store), "recoverable, not reliable" stopped being good
enough. This is the write-up of an **epic** — several related features — to move the stateful nodes
onto real disks, and the design and testing lessons that came out of it.

## Two patterns, chosen per node

Not every node wants the same fix. The work split cleanly along one axis:

- **Relocate state onto durable media** — for the nodes that *hold* data (the data node, the gateway).
- **Stop writing to the SD at all** — for the kiosk node, which is stateless: its config is
  reproducible from automation and its logs already ship off-box, so the right move there is a
  **read-only root** (no writes, no wear, immune to power-loss corruption). That child has since
  landed — see *The kiosk*, below.

A small shared role does the disk prep (partition, format, label-mount with `nofail`); each node
layers its own migration on top.

## The data node — move the database, keep the model

The data node runs its database as a **rootless container** with the data on a named volume. Moving
that onto an NVMe was *almost* a simple copy — except for one trap worth knowing:

> **Rootless container storage is owned by mapped sub-UIDs.** Under a rootless user namespace, the
> files in the container store belong to high "subordinate" UIDs on the host, not to the user you log
> in as. A normal `rsync` run as that user **cannot reproduce those ownerships** and silently flattens
> them — corrupting the store. The copy has to run **as root with numeric-id preservation**, and we
> gated the irreversible step behind a checkpoint that *proved* the ownership survived before
> committing to it.

The volume location moved; the named-volume model stayed (so the permission dance the database setup
had already dodged stayed dodged). A reboot test confirmed the data layer comes back on the NVMe with
no hand-holding — an SD reflash now loses the OS, not the data.

## The gateway — separate the *data plane* from the *control plane*

The gateway was the interesting one, because the naive framing ("move the write-heavy data off the
SD") is **wrong** there. The gateway also runs the observability stack, and the right axis isn't
"data vs. config" — it's **failure-domain separation**:

- **Data plane → durable disk:** the metrics time-series database and the log store. Write-heavy,
  and — for the metrics history especially — *not backed up anywhere before this*, so the durability
  win is real.
- **Control plane → stays on the SD:** the dashboards-and-alerting engine. It is the thing that
  *pages you*, and **it must outlive a disk failure to report one.** Put it on the same disk as the
  data and a dead disk takes your alerting down silently, exactly when you need it. So it stays on the
  resilient-enough SD, deliberately.

Two mechanisms make that safe:

1. **Gate the data-plane services on the disk.** Each is wired to *require its data mount*; if the
   disk is absent the service **refuses to start** rather than quietly creating a fresh, empty store
   on the SD (a split-brain that would shadow the real data and break the backup story). The gateway
   keeps routing the whole time — observability degrades, the network doesn't.
2. **A dependency-free watchdog.** A tiny shell-plus-timer unit that checks the disk and posts to the
   alert channel over plain HTTP — **no dependency on the observability stack at all**, so it still
   fires when the entire stack is down. It posts a heartbeat on every boot (a gateway reboot is itself
   worth knowing about) and an edge alert the moment the disk goes dark, with a reminder while it stays
   down. Its health check is **timeout-guarded**, because a *pulled* USB disk doesn't fail cleanly —
   it leaves a stale mount where I/O blocks forever, and a watchdog that hangs is a watchdog that never
   pages.

## The kiosk — make the medium irrelevant

The kiosk node never needed a bigger disk; it needed to stop *using* the one it has. It holds nothing
worth keeping — its configuration is reproduced from automation, its logs already ship off-box — so the
fix is a **read-only root**: the OS's overlay filesystem mounts the SD's root partition **read-only**
and catches every write in a **RAM overlay** that's discarded on reboot. The card is never written: no
wear, no write-corruption, and an unplanned power cut can't leave a half-written filesystem, because
nothing was being written.

Three details made it safe and reversible:

- **Schedule the reboot first, while you still can.** A RAM overlay accumulates — mostly the browser's
  cache on this small, memory-tight node — so a **nightly reboot** clears it (and is good hygiene for a
  long-running browser regardless). Crucially, that schedule has to be installed *before* the root goes
  read-only, because afterward the system can't accept new persistent units. Bake the housekeeping in,
  then lock the door.
- **Leave the boot partition writable — it's the escape hatch.** The overlay only protects the root; the
  small boot partition stays writable. That's deliberate: flip the toggle off, reboot, and the node is
  back to a fully writable root **in place** — no card-pull, no second machine. Read-only here is a
  setting you can disarm, not a one-way door.
- **Changing anything afterward is a deliberate dance.** Since writes evaporate on reboot, a *lasting*
  change means disarm → reboot (writable) → change → re-arm → reboot. Friction by design — which is
  exactly why this was the *last* thing done to the node, only once its display work had settled and the
  iterate-often phase was over.

**Proving it: pull the plug.** A graceful reboot isn't the real test; an *ungraceful* power-yank is.
Read-only root makes a clean recovery nearly a foregone conclusion — the card can't corrupt because
it's read-only, the overlay rebuilds because it's RAM — but "nearly" isn't "proven," so we pulled the
power. It came back clean: root read-only, overlay empty, dashboard back on the screen.

**One pull, two proofs (on purpose).** The node had been deliberately left on **wireless only**, no
network cable. So the same cold boot that proved the read-only root *also* exercised the
wired-to-wireless failover from a standing start: with no cable at boot, the node brought its wireless
standby up on its own and rejoined the network — a path previously only confirmed as *configured*, now
shown working for real, and working under a read-only root. A clean two-for-one.

**A small thing read-only broke (worth knowing).** Making the root an overlay changed its *filesystem
type*, and the metrics exporter excludes overlay filesystems by default — so the node's root-disk-usage
reading quietly dropped off the fleet dashboard, leaving one blank cell. No real loss (a "% disk used"
is meaningless when every write goes to RAM), but a tidy reminder that hardening one layer can ripple
into another layer's assumptions. Filed as a known, low-priority follow-up.

## Lessons that only showed up under test

- **Measure before you "optimize" — the assumption was backwards.** The plan assumed the metrics
  database was the dominant SD writer and the alerting engine was negligible. Profiling the actual
  bytes-to-disk showed the opposite: **the alerting engine was the single biggest writer**, by a wide
  margin — small, frequent database commits amplified by the on-disk journaling mode. Most of the
  expected "wear reduction" was hiding in the component we'd written off.
- **…and the obvious fix was a no-op.** The textbook remedy (switch the embedded database to
  write-ahead logging) **did nothing** on the current version — a recent change of the bundled
  database driver made the config knob inert. Two more config levers were A/B-tested live and also
  moved the needle zero. Conclusion, banked as a *negative result*: that writer is config-immovable
  here; accept it as residual rather than ship a fix that does nothing. (Cheap to verify, expensive to
  assume.)
- **To test "the disk died," actually remove the disk.** The first attempts to prove the
  start-up gate just *unmounted* the data bind — and the service started fine, because the mount
  machinery, finding the underlying device still present, simply **re-mounted it and self-healed.**
  That's good behavior, but it doesn't prove the gate. Only **removing the device** (a real pull, or
  the software equivalent) makes the dependency genuinely unsatisfiable — and then the service failed
  to start exactly as intended, with the network untouched. A umount tests the wrong thing.
- **A proxied datasource turns "down" into an *error*, not "no data."** Because the alerting engine
  reaches the metrics store through the reverse proxy, a dead store comes back as a gateway error
  (502), which the alert engine classifies as an *execution error* — not "no data." The liveness rule
  has to fire on **both** states, or the most important outage (the data plane is gone) goes silent.

## On throughput (so you don't chase it)

Worth saying plainly: **disk throughput was never the constraint.** The USB-attached NVMe runs at the
SuperSpeed link's ceiling (a few hundred MB/s) — slower than a native-slot drive, far faster than the
SD it replaced, and **vastly more than a metrics/log workload needs** (that load is small random I/O
and fsync, not streaming). The real upgrade over an SD card is **random IOPS and write endurance**,
not bandwidth. There's a knob to push the bus a generation faster; it stays unpushed, because nothing
here is bandwidth-bound. Spend the effort on the failure modes, not the megabytes-per-second.

## Where it stands

All three nodes are hardened: the data layer and the gateway's observability data live on NVMe (gated
and reboot-proven), and the kiosk's root is read-only (proven by a power-yank). **The epic is
complete.** The throughline: **the failure modes are the design** — what happens when the new disk
*isn't there*, or when the power drops mid-write, mattered more than anything that happens when it is.
