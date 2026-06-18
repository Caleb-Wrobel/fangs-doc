# 2026-06 — Centralized logging (Alloy → Loki)

**Goal:** every node's systemd journal, shipped to one place, queryable from the
same Grafana that already shows the metrics — so a dashboard panel and the log
lines behind it sit side by side. Roughly a week of retention, and the history
should survive a gateway reflash.

The steady state is in [Observability](../architecture/observability.md); this is
the log of building it, and two lessons that each cost a reboot to learn.

## The shape of the solution

- **Grafana Alloy on every node** reads the systemd journal and ships it to
  **Loki** on the gateway.
- **Loki** keeps ~a week and is queryable from Grafana next to the metrics.
- **Nightly backup:** the NAS pulls Loki's data once a night, so a gateway reflash
  doesn't take the log history with it.

## Lesson 1 — "a week of retention" was really "until the next reboot"

Logs were flowing, the dashboards worked, retention was configured for a week. Then
a reboot wiped *everything*. The Debian Loki package defaults its storage to a
**temp directory under `/tmp`** — backed by a tmpfs that the kernel clears on every
boot. So the retention setting was technically honored and completely beside the
point: the data never lived long enough for retention to matter.

Two fixes, together:

1. **Point storage at persistent disk**, not the default tmpfs path.
2. **Configure the deletion store that retention actually depends on.** Time-based
   retention needs a place to record delete requests; without it, "delete old
   chunks" has nowhere to write its intent and silently doesn't enforce.

The meta-lesson: **verify persistence empirically.** A configured retention window
tells you nothing about whether the bytes survive a power cycle. I only trusted it
after rebooting and watching old lines still be there.

## Lesson 2 — label at the source, or not at all

The useful query handle for journal logs is a `{unit=...}` label — "show me just
this service." Getting it required relabeling on the **journal source stage**
itself, not a later downstream relabel. The journal's internal fields (the
`__journal_*` metadata the unit name comes from) are only visible at the moment of
ingestion; by the time a downstream relabel runs, they've already been dropped, so
it has nothing to work from. **Order matters in a pipeline:** enrich while the
metadata still exists, because you can't recover what an earlier stage discarded.

## Backups — the den copies the den

A week of logs on the gateway is a week of logs you lose if the gateway's card
dies or gets reflashed. So the NAS **rsyncs Loki's store nightly**. It's the same
principle as the addressing: the fleet shouldn't lose memory just because one node
gets rebuilt. Cheap insurance — one scheduled pull, onto the disk that's already
the fleet's storage role.

## What I'd tell past me

- **A configured default is not a durable default.** "Retention: 1 week" and
  "stored on a tmpfs" coexisted happily and meant nothing. Reboot, then believe.
- **Enrich data at the earliest stage that still has the context.** Downstream
  can't relabel on fields an upstream stage already threw away.
- **If it's worth collecting, it's worth backing up.** Centralizing logs makes the
  gateway a single point of memory; the nightly pull to the NAS is what keeps that
  from also being a single point of loss.
