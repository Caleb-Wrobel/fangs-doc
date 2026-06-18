# 2026-06 — WiFi failover

**Goal:** give the two storage/observability nodes a *standby* wireless link, so
that if their wired connection drops they fail over to WiFi — and, critically,
**keep the same IP address** across the flip — then fail back to wired when it
returns. Active/standby, never both at once.

This one looked like a half-day job and turned into a tour of every sharp edge in
the modern Linux networking stack. Worth writing down.

## The shape of the solution

- **A NetworkManager dispatcher script** does the switching. WiFi is set to *not*
  autoconnect. When the wired interface loses carrier, the script brings WiFi up;
  when wired carrier returns, it takes WiFi back down. One active link at a time.
- **A dual-MAC DHCP reservation** holds the IP. The gateway reserves the *same*
  address against both the node's wired MAC and its wireless MAC, so whichever
  link is up, the node answers on its usual address. Dashboards and scrape targets
  never notice.
- **Not bonding.** A WiFi NIC can't be reliably enslaved into an active-backup
  bond — associating changes the MAC and breaks the WPA association. A dispatcher
  script sidesteps that entirely.

## Surprise 1 — only one node could even use WiFi

The two nodes have different radios. The newer one is dual-band; the older one is
**2.4 GHz only**. The gateway's access point was running **5 GHz only** — so the
older node physically could not associate, while the newer one quietly *had* been
joining the AP and accidentally dual-homing (wired *and* wireless at once).

The gateway is a Pi 5, which has a **single radio** — it can't run 2.4 and 5 GHz
APs simultaneously. So the choice was: stay 5 GHz and leave the older node wired
forever, or move the AP to **2.4 GHz** and let both nodes fail over (at the cost
of the newer node's standby link dropping to 2.4 GHz — fine, its real traffic is
wired anyway). Moved it to 2.4 GHz.

> Lesson: "why did this node connect and that one didn't?" was a *hardware radio*
> question, not a timing or range question. Check the silicon before theorizing.

## Surprise 2 — idempotency vs. the imager seed

The Pi Imager seeds a WiFi profile so a fresh node can phone home. On this fleet,
NetworkManager uses the **keyfile** backend, and the first naïve approach —
templating a netplan file and running `netplan apply` — was *not idempotent*:
`netplan apply` **consumes** the netplan source into a NetworkManager keyfile and
**deletes the original**. So every re-run saw a missing file and "changed" again,
forever.

Fix: stop going through netplan. **Template the NetworkManager keyfile directly**,
with a stable per-host UUID, and load it with a *non-activating* reload. Re-runs
now report zero changes. The role also hunts down and removes the imager's seed
profile so the managed keyfile is the single owner of the wireless interface.

## Surprise 3 — `netplan apply` restarts NetworkManager mid-play

Even where netplan lingered, calling `netplan apply` **restarts NetworkManager** —
which then raced the very next task that tried to talk to it ("NetworkManager is
not running"). The cure was to stop applying netplan at all: delete the stale file
and delete the live connection directly, so NetworkManager is never bounced
mid-run.

## Surprise 4 — the failback address-conflict bug

The subtlest one. On *failback* (wired returns), the wireless interface still
briefly held the shared IP on the gateway's bridge for a moment. When the wired
interface then probed that same IP via address-conflict detection, it saw its
*own* wireless side still using it, declared a conflict, and declined the address.
The DHCP server reacted by penalizing the reservation for ten minutes — and the
node fell off to a random pool address, breaking its scrape target and its proxy
backend.

Fix: **disable IPv4 duplicate-address detection** for these connections via a
small drop-in. The wired side now reclaims the pinned IP cleanly on failback
instead of fighting its own other foot.

## Verifying it for real

The payoff was a **physical cable-pull test**: confirm the node at its expected
address on wired, *physically yank the cable*, confirm it's now on the same
address over WiFi, plug back in, confirm it reclaimed wired. It passed — the
dispatcher fired on true carrier loss (logged), the IP held across both
transitions, and there was no flapping. Both nodes now carry the complete fix and
re-applying the role changes nothing.

## What I'd tell past me

- A "connectivity" mystery is often a **hardware capability** mystery. Look down
  the stack first.
- Idempotency is a property you have to *engineer*, especially when a tool
  (netplan) rewrites your own inputs out from under you. "It worked once" is not
  "it converges."
- Test the failure path **physically**. The address-conflict bug only showed up on
  a real failback, never in a simulated one.
