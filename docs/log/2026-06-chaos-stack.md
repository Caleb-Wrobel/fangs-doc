# 2026-06 — Breaking the fleet on purpose (the access gate)

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

## What comes next

The gate opens onto the rest of the epic: a small **incident store** (with a vector column, so the
data layer finally gets its first *retrieval* consumer), then the **controller** itself — weighted
selection, a jittered schedule plus on-demand runs, and reading alert state from the **dashboard
server's API** rather than the metrics store (because the alerts are evaluated at the dashboard
layer, where the raw "did it fire" series doesn't exist) — then a per-incident **narrative +
embedding**, and finally a **dashboard** for the whole game. The door is built and bolted; next we
give something the key.
