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
  **read-only root** (no writes, no wear, immune to power-loss corruption). That child is design-first
  and still ahead.

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

Two of three nodes are durable: the data layer and the gateway's observability data both live on NVMe,
gated and reboot-proven; the kiosk's read-only-root work is the remaining child. The throughline of
the whole epic: **the failure modes are the design** — what happens when the new disk *isn't there*
mattered more than anything that happens when it is.
