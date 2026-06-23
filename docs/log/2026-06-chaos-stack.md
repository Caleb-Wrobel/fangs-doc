# 2026-06 — Breaking the fleet on purpose

**Goal:** deliberately inject known, self-reverting failures into the fleet — on a schedule and
on demand — to prove the alerting actually fires and the nodes actually recover, and to turn each
incident into stored, narrated, and searchable history. With almost no redundancy in this fleet,
the honest framing isn't "resilience testing" — it's an **end-to-end exercise harness for the
alert/recovery stack**, where *"we broke X and nothing paged"* (a blind spot) is a **first-class
result**, not a failure.

This is the fleet's **first "epic"** — too big for one change, so it's split into named pieces
(access → schema → agent → narrate/embed → dashboard) that each ship on their own. This entry is
the **first piece: the access gate.** Nothing can fire until it exists, and it's the part where
getting the security wrong matters most — so it went first and slowly.

## The hard constraints (these came before any code)

- **Two targets, ever: the NAS and the display node.** The **gateway is never touched** — it's a
  single, un-redundant backbone (routing, VPN egress, DNS, the reverse proxy); there's no failover,
  so "break it to test" has no safety net. The **AI node is never touched** either: it *hosts the
  controller, the database, and the models*, so breaking it would blind the very thing watching.
- **No firewall-level injection.** Dropping traffic at the gateway would mutate the backbone. Faults
  are **node-local and self-reverting**, applied on the victim itself.
- **Every fault has a tested, idempotent undo** before it's allowed into the catalog.

## The access gate, by layers

The controller lives on the AI node. It must be able to tell a target "break yourself / fix
yourself / what's your status" — and be able to do *nothing else*, even if its key is stolen.

- **A dedicated, locked-down identity** end-to-end — not the human admin account. The admin stays
  the human operator; the robot gets its own face.
- **Forced-command SSH.** The identity's key is pinned to run exactly **one program** and is
  stripped of everything else — no shell, no port-forwarding, no second command. Whatever the caller
  *asks* for, the server runs that one program instead.
- **That program never trusts the wire.** It reads the requested action, accepts only a verb from a
  fixed set (`inject` / `recover` / `status`) and an action **name that must exist in a root-owned
  catalog**, and then runs only the *stored* command for that name. The text coming over SSH is
  matched against a whitelist, never executed.
- **One source of truth, split two ways.** The catalog of "what may break" is rendered from a
  single definition, so the dangerous half that lives on the victim (the actual fault/undo commands)
  and the half the controller reasons about (weights, expected alerts, descriptions) **cannot drift
  apart**. The controller never even sees the raw fault commands.
- **Recovery is a victim-local dead-man.** *Before* applying a fault, the program arms a local timer
  that will run the undo on its own — so recovery **never depends on the controller still being
  alive or reachable**. Alert-backed faults recover the moment the alert confirms; the rest ride a
  bounded window; the one physically-risky thermal fault recovers the instant its alert trips.
- **Scoped privilege.** The identity may run that one program as root and nothing else.

### A design call worth recording

The first sketch split faults by privilege — some as the robot, some as root. I collapsed that:
**every fault runs root-side through the single gated program.** It's simpler to audit, it lets the
dead-man be a robust *system* timer, and — this is the point — it **doesn't widen the blast radius
at all.** The program is root-owned (the robot can't alter it) and re-validates every call, so the
worst case if the key leaks is unchanged: *start/stop a handful of whitelisted services and a
bounded CPU load on two leaf nodes, all of it auto-reverting within the hour — no shell, no
escalation, backbone untouched.* The one user-owned service that's a target is reached by crossing
into its owner's session deliberately, as root, for that one unit.

## What fought back (and the small lessons)

> **The gate is the product, so prove it on the real thing.** A local script test can show the
> parser rejects junk; it can't show the *SSH server* really refuses a shell. So the proof ran live:
> ask the identity to run an arbitrary command, watch it come back **"unknown verb"** instead of
> executing — the forced command holds on the actual server, which is the only test that counts.

> **Ship it inert.** The access gate has no caller yet — the controller is a later piece — so it
> landed as a complete, idempotent, *testable* capability that **does nothing until something calls
> it.** Infrastructure-first, again: build the locked door before the thing that walks through it.

> **A dry-run can't see a key it hasn't minted.** The gate generates a key on the controller and
> *then* authorizes it on the targets — so a pre-apply dry-run has no key to resolve and trips on the
> ordering. The fix wasn't code; it was recording that idempotency is checked **after** the first
> real apply, not before it. (A sister pattern in the fleet has the same shape.)

> **Observe a fault without earning new access.** To confirm inject/recover actually worked, I didn't
> add a login anywhere — I watched the victim's **metrics port go dark and come back** across the
> cycle, and read the dead-man timer's countdown through the gate's own `status`. The capability
> proved itself using only what was already exposed.

## Giving the door a key: the rest of the harness

With the gate built, the rest of the epic followed as small, independently-shipped pieces — each one
inert until the next gave it a purpose.

**The incident store.** A dedicated schema with two tables — one row per incident, and a companion
table with a **vector column** — plus two least-privilege roles: a writer the controller uses, and a
**read-only reader** scoped to *only* this schema (it structurally cannot see the rest of the
database). This is the data layer's long-promised first **retrieval** consumer; it shipped empty, on
purpose, waiting for a writer.

**The controller.** The piece that ties gate and store together: it weights a random pick from the
catalog, dispatches it over the forced-command path, **measures whether the expected alert actually
fires by reading the dashboard server's API** (the alerts are evaluated at the dashboard layer, so
the raw "did it fire" series doesn't exist in the metrics store — you have to ask the right oracle),
recovers on confirmation or at the time cap, and writes the incident down. First live run: it took a
node's metrics agent down, watched the "node down" alert climb to *firing* over its ten-minute
window, recovered, and logged a complete incident. The loop closed.

**Knowing when *not* to act.** A late but important addition: before injecting, the controller now
**stands down** if the fleet is already unhealthy — a node already down, an alert already firing, or a
previous experiment still in flight — and it **fails safe** (if it can't *verify* health, it declines
rather than pile chaos onto an unknown state). It also announces every decision to a dedicated chat
channel: *injecting*, *standing down (and why)*, *recovered*. That surfaced a second, subtler
requirement:

> **Chaos is deliberate noise, so it must be distinguishable from real failure.** A chaos-induced
> outage must never be mistaken for a genuine one — by the morning report, by future analytics, by a
> human glancing at a graph. So every run also records its outcome to **two places**: a structured log
> line shipped to the log store (survives even a database outage), and a dedicated harness-health table
> (`recovered` / `stood-down` / `errored`). Now "is the experiment itself working?" is its own
> answerable question, separate from "did the fleet break?", and an expected break can be filtered out.

**Memory.** When a run ends cleanly it hands off to a separate pass that finally makes the vector
column earn its keep: it embeds a summary of the incident, **retrieves the nearest prior incidents**,
asks a small **on-device model** to write a two-sentence retrospective with that history as context,
stores it, and posts it to the channel. The "has this happened before?" query works *semantically* —
asked for incidents like a registry outage, it returned the *other* registry outage ahead of an
unrelated one. Retrieval-augmented memory over the fleet's own self-inflicted history, running entirely
on-device.

**The view.** Finally, one board ties it together — reading the store through that read-only reader:
the incidents (what broke, whether it paged, the written narrative), and the harness-health table
(stand-downs, errors, last good run). The whole game, legible at a glance.

## How it ships, and what's parked

It ships **manual-first**: the daily schedule is installed but **disabled**, and the one physically-risky
action (CPU/thermal load on a passively-cooled board) is excluded from automatic selection — both flip on
with a one-liner once the early runs have been watched by hand. Parked for later: marking chaos windows
directly on the *fleet-wide* dashboards (so any graph shows "this dip was us"), a real-time "chaos is
active" signal the alerting layer can read, and a meta-alert for "the experiment hasn't run in a while."

> **The throughline:** build the dangerous capability **inert and behind a gate first**, prove each
> piece in isolation, and treat *observability of the experiment itself* as a first-class feature — because
> a tool that breaks things on purpose is only safe if you can always tell its noise from the real thing.
