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

The **first consumer has landed**: the [daily report](../log/2026-06-daily-report.md) now lives on
this node and persists one structured row per fleet node on every run, so the first table was shaped
by a real requirement rather than a guess — and through a deliberately **insert-only** writer role,
distinct from the read-only backup role and the superuser.

The **vector store now has its consumer too**: [RAG over the fleet's telemetry](../log/2026-06-telemetry-rag.md)
embeds notable log lines into a vector table and answers plain-English questions about them — grounded
in retrieval, running on the node's own embedding model and LLM. It's the second retrieval consumer,
after the [chaos stack](../log/2026-06-chaos-stack.md)'s incident memory.
