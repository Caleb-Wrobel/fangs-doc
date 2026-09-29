# Data layer

The fleet's structured-data home: **Postgres with the pgvector extension**, on the 16 GB
node. It started as the query layer for *derived* data — telemetry summaries, and vector
embeddings for retrieval — kept distinct from the raw metrics and logs, which live in their
own stores. It has since become the default home for **application state** too: services
that would otherwise bring their own embedded database keep it here instead.

## How it runs

- **Rootless Podman**, as a systemd-managed container (the same posture as the image registry
  on the NAS). The Postgres data dir lives on a **named volume** — Podman-owned, which keeps
  rootless permissions sane (a host bind would fight the in-container user over ownership).
- **LAN-only.** The database listens on the trusted LAN; the node sits behind the gateway and
  is never WAN-facing.
- **pgvector** is enabled in the application database at first init, so vector columns and
  indexes are available the moment a consumer wants them.

## Durability

The database lives on **durable NVMe**, not the node's SD card — the container's storage is
bind-mounted onto the SSD, so the card carries the OS and nothing that matters. Two more
things bound the blast radius:

- Much of what Postgres holds is **derived** — the raw metrics and logs are elsewhere, so
  losing those tables costs recomputable data, not history. That is no longer true of
  *everything*: the chat UI's accounts and history and the forge's issues and pull requests
  are primary data, which is exactly why the backup below matters more than it used to.
- The NAS pulls a **nightly `pg_dump`** to its HDD (custom-format, timestamped, rolling
  retention), bounding loss to a single day. The pull authenticates as a **read-only role**
  that can read everything and own nothing — a backup credential with no write power. The
  dumps are **encrypted to a key the NAS does not hold**, so the machine storing the backups
  cannot read them; a restore decrypts on a workstation and streams into the database, so the
  plaintext never lands on either node's disk
  ([the locked door beside the open one](../log/2026-07-secrets-at-rest.md)).

One honest gap: the forge's database joined after the backup's database list was written,
and isn't in the nightly dump yet (its git history is safe — it's mirrored offsite
separately). The one-line fix is queued alongside the off-site backup work on the
[roadmap](../roadmap.md).

## Placement policy

A new service that would ship its own embedded database (usually SQLite) gets asked one
question before it's built: *is this a data-layer tenant?* The default answer is yes — one
database to back up, observe, and restore, instead of a scatter of files on different
nodes. Both the chat UI and the forge moved their state here under this rule.

**The exception is the dashboard server**, and it's deliberate. Grafana is the pager: it
evaluates the alerts that would tell you the data layer is down. A pager that depends on
the thing it pages about can't page, so Grafana keeps its own embedded database on the
gateway and stays sovereign.

## Tenants

The **first consumer has landed**: the [daily report](../log/2026-06-daily-report.md) now lives on
this node and persists one structured row per fleet node on every run, so the first table was shaped
by a real requirement rather than a guess — and through a deliberately **insert-only** writer role,
distinct from the read-only backup role and the superuser.

The **vector store now has its consumer too**: [RAG over the fleet's telemetry](../log/2026-06-telemetry-rag.md)
embeds notable log lines into a vector table and answers plain-English questions about them — grounded
in retrieval, running on the node's own embedding model and LLM. It's the second retrieval consumer,
after the [chaos stack](../log/2026-06-chaos-stack.md)'s incident memory.

Since then:

- **A network connection map** — which fleet node talks to which outside service, folded
  from the gateway's flow transcripts by a least-privilege writer role.
- **Package-staleness history** — one row per node per weekly run.
- **The chat UI's own state** — accounts, chat history, settings — moved off its embedded
  database.
- **The git forge** — issues, pull requests, users, and CI state, in a dedicated database it
  fully owns (unlike the telemetry writers, which get insert-only roles in a shared one).
