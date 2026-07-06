# 2026-07 — Watching the cache (before the upgrade needs it)

**Goal:** before a cluster-wide rolling upgrade, be able to *see* the package cache working —
hit vs miss ratio, bandwidth served from cache vs pulled over the internet, request volume as the
upgrade sweeps the fleet. If you're going to lean on a cache to make an upgrade fast and
deterministic, you should be able to watch it do its job, not hope.

## Two caches, opposite ends of the effort

The dashboard is the easy 20%; the *data* is the 80% — and the two caches on the storage node sit
at opposite ends of it.

- **The image registry** exposes **native Prometheus metrics** — it was a config flag away.
  Turn on the metrics extension, add a scrape target, done.
- **The apt package cache** exposes **nothing** to Prometheus. Its only stats live in an HTML
  status page. So the real build was a small **exporter**: a timer-driven script that fetches that
  status page, parses out the hit/miss counts and the cache-vs-upstream byte split, and writes them
  where the metrics agent already looks (its "textfile" drop-box). No new scrape target needed — the
  numbers ride the node's existing metrics feed.

A nice consequence of that design: the package-cache metrics piggyback on infrastructure that was
already there, so only the registry needed a new scrape job.

## What the board shows

A single "Cache Overview" board: request hit ratio, byte hit ratio (i.e. **bandwidth saved**),
bytes-from-cache vs bytes-from-internet over time, request volume, and an exporter-health tile. On
the day it went up the cache was cold — **~19% of requests and ~1% of bytes** were coming from
cache — which is exactly the baseline you want to watch climb.

One honest caveat baked into the panels: the apt cache's numbers are scoped to its *current log
window* and reset when it rotates its log, so they're **gauges, not ever-growing counters** —
perfect for watching a live upgrade window, not for long-run rate math.

## Three things the pipeline caught that a dry-run couldn't

This feature was a clinic in *effect vs. artifact* — three times the plan looked done and wasn't,
and each was invisible to a dry-run because a dry-run checks intent, not outcome:

1. **The metrics targets were tagged by a different name than I assumed**, so my first dry-run
   silently skipped half the work. The prediction check is what surfaced it — before any apply.
2. **The exporter wrote its file readable only by its owner.** The file was *perfect* on disk — but
   the metrics agent runs as a different, unprivileged user and couldn't open it. On disk: correct.
   In practice: an empty graph. One `chmod` fixed it, but only *observing the actual scrape* found
   it — the file's existence proved nothing.
3. **The dashboard was authored but never deployed.** The provisioning role copies dashboards from
   an *explicit list*, and I'd added the file without adding it to the list. The board silently
   didn't exist until I queried the dashboard API and got "not found."

None of these are exotic. All three share a shape: a thing that *looks* installed (right tags, a
file on disk, a JSON in the repo) but doesn't *do* what it should. The only defense is to check the
effect at the far end — the query returns data, the scrape succeeds, the API sees the board — not
the artifact at the near end.

## The fortunate part

The whole point was to have this live *before* the rolling upgrade, and it is. The upgrade plan is
to warm the cache with one canary node, then roll the rest of the fleet against that same cached
set — and the thing that makes a *long, relaxed* upgrade window safe instead of a tight anxious one
is being able to watch the hit-ratio hold near 100% as each node pulls the canary's exact packages.
A dip to misses would mean drift, visible immediately. The board isn't just a nicety next to the
upgrade; it's the instrument that lets the upgrade take its time.

## What I'd tell past me

- **The dashboard is the garnish; the pipeline that feeds it is the meal.** Budget accordingly —
  most of the work is getting a number *into* the system, not drawing it.
- **"Installed" is a claim about an artifact; "working" is a claim about an effect.** Right tags, a
  file on disk, a committed JSON — each can be true while the feature does nothing. Verify at the
  consuming end.
- **Check the file permissions of anything one service writes for another to read.** The most
  time-consuming bug here was a default-private temp file — correct content, wrong audience.
- **Build the instrument before the thing it measures.** A cache you can't watch is a cache you're
  trusting on faith; watching it is what converts a cautious plan into a confident one.
