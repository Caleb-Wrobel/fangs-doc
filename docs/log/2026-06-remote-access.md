# 2026-06 — Reaching in from outside (and why the mesh stayed off)

**Goal:** use the homelab's services — the local AI inference node especially —
from a control machine that *isn't* on the home LAN, without standing up a new
inbound hole in the edge and without juggling a separate tunnel per service.

The steady state is in [Networking](../architecture/networking.md#remote-access-from-off-lan);
this is the log of deciding how, and of one tempting shortcut that turned out to
be a trap.

## The shape of the solution

- **The gateway stays the only WAN-facing surface.** Internal services are never
  published; you reach them by *tunnelling through the gateway*, not by exposing
  them. The reverse proxy still listens on the LAN side only.
- **Today:** an SSH tunnel through the gateway — the same mechanism already used to
  reach the local AI from the laptop. One authenticated path, no new inbound port,
  and the internal `*.fangs.internal` names keep working because DNS rides the
  tunnel to the gateway's resolver.
- **The durable idea on the table:** a self-hosted **WireGuard road-warrior** on the
  gateway — dial in once and be *logically on the LAN*, so every service (and every
  new one) is reachable with zero per-service setup.

## The tempting shortcut: the VPN's built-in mesh

The commercial VPN the fleet already uses for egress ships a **mesh overlay** — peer
devices reach each other directly, no inbound port to forward, and (the seductive
part) it's a vendor the project has *already* committed to trusting. It looked like
the no-WAN-port overlay, for free, with nothing new to self-host. I turned it on.

It fought back, and the reasons it lost are worth writing down — there are **two**.

### Reason one: footprint

The mesh was deliberately **off** to begin with, and for a good reason: switching it
on opens an inbound mesh surface on the gateway and enrols the edge in the vendor's
coordination plane. The entire job of the edge is to be the *smallest* WAN-facing
thing it can be. "Reuse the vendor I already trust" is a real argument, but it
doesn't make the extra surface disappear — it just makes it easy to wave away.

### Reason two: it drags a second firewall back, and that firewall eats DHCP

This is the one that actually killed it. Enabling the mesh **force-enables the
vendor client's own "firewall"** — a setting distinct from its kill switch — and
won't let you turn that firewall back off while the mesh is active. The two are
welded together.

That vendor firewall is the *exact* thing already known, from earlier work, to
**silently drop LAN DHCP**: its packet filter swallows the broadcast that hands out
leases, so the whole fleet slowly loses its addressing while unicast traffic keeps
working and everything *looks* fine. (That gotcha is written up in
[Networking](../architecture/networking.md#vpn-egress-and-the-kill-switch).) So the
mesh can't coexist with a healthy LAN unless DHCP-safety is handed off to a vendor
toggle I don't fully control — re-importing a whole second firewall whose policy
lives outside my own rules. That's the opposite of the design principle the gateway
is built on: **own the filtering policy in one place.**

### What saved the LAN: a read-back that refuses to lie

The automation that flipped the mesh on also re-asserted "vendor firewall off" and
then **read the settings back and asserted the firewall was actually off** before
doing anything else. It wasn't — the mesh had quietly re-armed it — so the run
**failed loudly and stopped**, instead of shipping a fleet-wide DHCP outage that
would've surfaced hours later as "why is nothing getting an address?"

That guard is the hero of this entry. The fix for a *silent* failure mode is to make
the dangerous state **loud**: don't assume a setting took — read it back and fail the
run if it didn't.

## Where it landed

The mesh stays off — now for two reasons, not one. Off-LAN access is an SSH tunnel
through the gateway for the moment, which needs no new inbound port. If "logically
on the LAN from anywhere" becomes worth a real build, it'll be a **self-hosted**
WireGuard listener, where the vendor firewall stays off and the kill-switch-lives-
in-the-firewall model stays intact — at the cost of the one inbound port the mesh
would have avoided. That trade is the open question, not the mesh.

## What I'd tell past me

- **A vendor "firewall" toggle can be welded to a feature you want.** The mesh and
  the firewall weren't independent settings; turning one on dragged the other with
  it. Read the vendor's coupling, not just its switches.
- **"I already trust this vendor" is not the same as "this costs nothing."** Reusing
  committed infrastructure is a fair instinct, but it can smuggle a footprint and a
  policy you didn't choose back in through the side door.
- **Make silent failure modes loud.** The DHCP break is invisible at the moment it
  happens. A read-back assertion that refuses to proceed turned a delayed, baffling
  outage into an immediate, legible "no."
- **The cheapest option that's actually safe beats the clever one that isn't.** A
  plain SSH tunnel is unglamorous and solved the real goal today without touching
  the edge.
