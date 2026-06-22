# 2026-06 — A database for the fleet (before it has anything to store)

**Goal:** give the fleet a real **query layer** — a durable, extensible home for structured
data: telemetry summaries today, vector embeddings for retrieval later, whatever needs SQL.
Deliberately *infrastructure only* — the **what-we-store** question is left for the first
consumer. Build the database before designing the schema.

## Shape

**Postgres + the pgvector extension**, running as a **rootless Podman container** on the
16 GB node (consistent with the fleet's container posture), managed as a systemd unit. Data
on a **named volume**; the durability story is a **nightly `pg_dump` pulled by the NAS**, on
the same pattern as the existing log backup — the backup host owns the job, the database host
just exposes a read-only role.

## A few decisions that kept it clean

- **The official pgvector image, not a hand-layered one.** pgvector publishes a multi-arch
  Postgres image with the extension already built in — the cleanest path on ARM, and one
  fewer thing to maintain. (Checked the manifest had an arm64 variant *before* writing the
  unit — the five-second check that saves a confusing failure.)
- **A named volume, not a host bind.** Rootless Podman plus a host directory is the classic
  permissions fight: the database's in-container user can't own a host-owned path. A named
  volume lets Podman own and initialise it correctly — the dance just doesn't happen.
- **A read-only backup role, not the superuser.** The NAS authenticates as a dedicated role
  that can *read everything and own nothing* (Postgres ships a predefined role for exactly
  this). A backup credential should never be able to write.
- **The backup is a pull.** The NAS reaches out and dumps; the database node holds no
  outbound keys or backup logic — the same shape as the rest of the fleet's backups.

## The known risk, stated plainly

The node runs on a **microSD card** — a known failure point. That's accepted on purpose:
Postgres here holds **derived** data (summaries, embeddings), not the source of truth — the
raw metrics and logs live elsewhere. So a card death loses *recomputable* data, and the
nightly dump bounds even that to a single day. The card is **recoverable, not reliable**;
backup discipline is the mitigation, not avoidance.

## Building the empty room

There's something deliberate about standing up a database with **no tables in it**. The
schema waits for the first real consumer — the daily report writing its output here instead
of only to chat, or a retrieval pipeline needing a vector store. Designing the schema now,
against imagined needs, is how you get a schema you fight later. The infrastructure is this
unit; the data model is the *next* one, and it gets to be shaped by a real requirement.

## What comes next

The first schema appears the moment a consumer does. The vector store now sits alongside the
embedding model — which makes "retrieval over the fleet's own telemetry" concrete rather than
aspirational: there's finally somewhere to put the vectors.
