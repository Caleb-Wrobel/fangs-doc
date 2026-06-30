# 2026-06 — A bus for the fleet

**Goal:** stand up a single publish/subscribe message bus the whole fleet can use, ahead of any
specific consumer needing it. The trigger was an upcoming garden-sensor project, but the bus itself
is general-purpose infrastructure, not a garden-shaped one-off.

## Build-then-dormant, on purpose

This is infrastructure built **before** its first real consumer exists. That's a deliberate pattern
here: stand up the generic capability, prove it works, and let the first producer/consumer pair
bolt onto a working bus rather than co-designing both at once. The broker ships live and listening;
nothing is publishing to it yet, and that's fine — an idle bus with zero traffic is still a fully
proven piece of infrastructure.

## Decisions, resolved up front

A short batch of open questions got settled before any code was written, so the build itself was
mechanical:

- **Packaging:** native, not containerized. The gateway node runs everything system-level
  (routing, firewall, DNS, VPN, the reverse proxy) as native daemons — no container runtime lives
  there at all. A message broker is exactly that kind of host-integrated service, so it follows
  the same packaging convention rather than becoming the one container on an otherwise all-native
  box.
- **Security posture — open first, harden later.** v1 ships **anonymous** auth and **plain**
  (unencrypted) connections, restricted to the trusted LAN only — never reachable from outside.
  That's a conscious, explicit trade: the same "stand it up open, add auth/TLS as a deliberate
  follow-on pass" pattern this fleet has used before for other internal services. Per-client
  credentials and transport encryption are scoped as a named future hardening pass, not an
  afterthought.
- **Persistence — durable, but not load-bearing.** Retained messages live on durable storage (so a
  fresh subscriber gets the last-known state immediately on connect), but the broker is
  deliberately **not gated** on that storage being present. Availability wins over persistence
  here: if the durable disk is ever missing, the bus still comes up and carries live traffic — it
  just starts without retained history, rather than refusing to start at all.
- **Topic namespace.** A simple, extensible scheme (`fangs/<domain>/<source>/<measurement>`) was
  agreed on for any future producer to slot into, without prescribing what the first real topics
  will look like — that's left to whoever builds the first consumer.

## What fought back: a config file already in the box

The first live deployment attempt failed immediately — the broker crash-looped on startup with a
cryptic "duplicate configuration value" error.

The cause: the package's own stock configuration file *already* declared where persisted data
should live, **before** the fleet's own config snippet got included. This particular broker
refuses to accept the same setting declared twice, even across separate files — so dropping a
second declaration into the fleet's usual "one clean snippet, don't touch the stock file" pattern
broke on contact.

The fix was small once diagnosed: instead of redeclaring the setting, **edit the stock file's
existing line in place** to point at the fleet's preferred storage path. One line, found by running
the broker by hand with verbose logging until it said exactly what it didn't like.

It's a reminder that "drop a snippet in `conf.d` and don't touch the vendor file" is a convention,
not a guarantee — some daemons' default configs claim settings ahead of the include point, and the
only way to know is to actually start the thing and read what it says.

## What it proved

Once fixed, the broker came up clean and stayed up: listening only on the trusted LAN (never the
internet-facing side), persisting retained state to durable storage, and surviving a repeat
no-op apply with zero unexpected changes. A purpose-built validation pass confirmed each piece —
the listener binding, the storage ownership, the firewall rule, the anonymous-access posture — one
by one, live, rather than trusting the playbook's "changed" output at face value.

The bus is up, idle, and waiting for its first producer.
