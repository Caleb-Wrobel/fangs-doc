# 2026-06 — Re-onboarding a reflashed node (three things that bit)

**Goal:** the display node got wiped and reflashed to the lean OS, shedding the desktop it
no longer needed. Bringing it back as a managed fleet member should have been routine — its
address is pinned to its hardware, so it returns on the same name. It *was* routine, in the
sense that the node itself behaved. Three pieces of the surrounding fleet did not.

## 1 — the package cache had been lying for who-knows-how-long

The very first configuration step — a package-index update — failed on the fresh node with
a signature error: the index's signature "has been manipulated." Alarming phrasing for what
turned out to be plumbing.

Every node routes package fetches through a **caching proxy** on the NAS. That proxy had an
**empty upstream backend** for the main distro archive — a config gap no one had noticed,
because the relevant index files happened to be cached from before. So the proxy answered
fresh index requests with a tiny **error page**, and the new OS's stricter signature checker
read that error page as a *tampered* index. Chased and ruled out, in order: the VPN egress,
the clock, and IPv4-vs-IPv6 — none of them. The fix was to give the proxy a real upstream
and clear the stale index files it had poisoned.

> Lesson: "signature manipulated" wasn't an attack or a bad key — it was a **proxy serving
> an error body as content**. When a verifier complains about bytes, check what actually
> arrived on the wire.

## 2 — the failover role cut off its own branch

The fleet has a wired-primary / WiFi-standby failover role. Run against this node, it **hung
mid-run and the node dropped off the network entirely**. The cause: the node happened to be
reachable *only over WiFi* at that moment, and the role's whole job is to reconfigure the
wireless interface — so it tore down the very connection the run was riding on, then waited
forever for a node that could no longer answer.

The node came back over a wired cable, and the role was taught to **refuse to run when the
active link is the one it would reconfigure** — turning a self-inflicted outage into a clear
"re-run me over the wired link" message.

> Lesson: a role that reconfigures the network must first ask whether it's standing on the
> branch it's about to cut.

## 3 — the clock that wasn't

Small-board computers have **no battery-backed clock**. A freshly flashed node boots
believing it's some default past date until it reaches a time server — and a wrong clock
silently breaks anything that checks a validity window: package signatures (again) and TLS
certificates against the internal CA. It wasn't the culprit this time, but it's a landmine
worth defusing, so "confirm the clock is synced before the first real run" is now a written
onboarding step.

## What I'd tell past me

- A "new node" failure is often the **fleet around it**, not the node. Two of these three
  bugs had been latent for weeks; a fresh, stricter OS just stopped tolerating them.
- **Rule out the exciting explanation last.** "Signature manipulated" and "node vanished"
  both sounded dramatic; both were mundane plumbing.
- Bugs that only surface on a *reflash* are the ones a stable steady state hides — so the
  occasional clean rebuild is itself a test.
