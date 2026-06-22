# Data layer

The fleet's structured-data home: **Postgres with the pgvector extension**, on the 16 GB
node. It's the query layer for *derived* data — telemetry summaries, and vector embeddings
for retrieval — kept distinct from the raw metrics and logs, which live in their own stores.

## How it runs

- **Rootless Podman**, as a systemd-managed container (the same posture as the image registry
  on the NAS). The Postgres data dir lives on a **named volume** — Podman-owned, which keeps
  rootless permissions sane (a host bind would fight the in-container user over ownership).
- **LAN-only.** The database listens on the trusted LAN; the node sits behind the gateway and
  is never WAN-facing.
- **pgvector** is enabled in the application database at first init, so vector columns and
  indexes are available the moment a consumer wants them.

## Durability

The node runs on a **microSD card**, treated as *recoverable, not reliable*. Two things make
that acceptable:

- Postgres holds **derived** data, not the source of truth — the raw metrics and logs are
  elsewhere, so a card failure loses only recomputable data.
- The NAS pulls a **nightly `pg_dump`** to its HDD (custom-format, timestamped, rolling
  retention), bounding loss to a single day. The pull authenticates as a **read-only role**
  that can read everything and own nothing — a backup credential with no write power.

## Status

Infrastructure only — there is no schema yet. The data model is deferred to the first
consumer (the [daily report](../log/2026-06-daily-report.md) persisting its output, or a
retrieval pipeline needing a vector store), so it gets shaped by a real requirement rather
than a guess.
