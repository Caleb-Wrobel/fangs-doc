# The router hands out the leases

**2026-11-26** · networking

**Goal:** move the LAN's DHCP server off the Pi and onto the edge router, which
was already the box every packet goes through. Network services belong on the
network box. While I was in there, the router also became the LAN's second DNS
server and its first time server.

## The shape of the solution

The reservations are still generated from the inventory. One list of "this MAC
gets this address, under this name" feeds three consumers: the router's DHCP
server and DNS entries, the Pi's resolver, and the Pi's old DHCP server, which
is kept stopped and masked as the rollback. A single variable picks which box
serves DHCP, and the two are never on at once. Turning the router on means the
Pi goes off first; rolling back means the router goes off first.

What a client gets from a lease:

- **DNS: the Pi first, the router second.** The Pi's resolver stays primary. The
  router answers the fleet's own names from a static set generated from the same
  list, and sends everything else upstream over DNS-over-HTTPS. That upstream is
  steered into the VPN tunnel by two routing rules. An output drop on the
  upstream port catches a failed steer, so the router's DNS fails closed rather
  than leaking.
- **Time: the router first, the Pi second.** The router serves time it gets from
  public servers, and it never serves its own clock when it isn't synced. The Pi
  stays in the list because it has the only battery-backed clock in the fleet:
  after a power cut that brings the house back before the internet, it is the
  only source that's right.
- **The search domain,** so short names resolve.

All of it was proved live from the branch before the merge. With the Pi's
resolver stopped on purpose, every node still resolved both an internet name and
a fleet name through the router, and the router's DNS traffic only ever left
inside the tunnel. The rollback was rehearsed both ways.

## Surprise 1: one address, two MACs

The old DHCP server let a node keep one address on both its wired and its WiFi
interface, which is how WiFi failover worked. The router can't do that: one
address, one MAC, full stop. Rather than carry a workaround across, failover was
retired as its own small change first. Wired-only nodes lost their standby. The
one node that really needs a WiFi standby got its own address and its own name
for it. The move itself then stayed a straight swap.

## Surprise 2: the catch-all that hid everything

The Pi's resolver answers "no such name" for anything unknown in the fleet's
internal zone. Copying that onto the router seemed obvious: a zone-wide "no such
name" entry, with the real names listed beside it. The router then answered "no
such name" for *every* fleet name. On this router a zone-wide negative entry
beats every specific entry under it, whatever the order of the list.

The fix was to drop the catch-all. Unknown internal names now go upstream and
come back "no such name" from there. Only a client that has already fallen back
from the Pi ever asks the router, so the extra query costs nothing.

## Surprise 3: reordering two rules froze the routing table

Putting the two DoH routing rules in their declared order made the router's
routing process hang. Every attempt to *list* the rules or routes stalled, while
packets kept flowing as normal. The deploy account couldn't reboot it (by design,
it doesn't have that right), so the fix was a reboot by hand from the admin
account. The order had in fact been applied, so nothing in the config needed to
change. Now it's a known trap: don't reorder routing rules on a live router
without a reboot window.

## Surprise 4: time is opt-in per client

Handing out a time server over DHCP only reaches the clients that listen for it.
Two nodes use a DHCP client that passes it on; the rest ignore it. So "the router
first, the Pi second" is set on every node directly, and the DHCP option is a
bonus for whatever else joins the LAN.

The question I cared most about was what happens when the router itself is
unsynced, as it is straight after a cold boot. The answer: it says so. Its time
packets carry the "I'm not synchronised" flag, the nodes reject them, and they
fall through to the Pi. That was tested by switching the router's own clock sync
off and watching a node skip it.

## A small one after the switch-back

Toggling the router's DHCP server off and on, as the rollback test did, can leave
an existing lease pointing at a server the router no longer recognises. That
client's renewals are ignored until the lease runs out, at which point it asks
from scratch and gets the same address back in a fraction of a second. It was
caught because the 24-hour check happened to land on exactly that expiry.
Harmless, so the runbook says to leave it.

## What I'd tell past me

- **Move the constraint out of the way before the move.** Retiring WiFi failover
  first turned a migration with a special case into a straight swap.
- **Generate both sides from one list, and keep the old side as a stopped
  rollback.** The switch-back was one variable and a rehearsal, not a rebuild.
- **Test the failure you care about, not the happy path.** An unsynced time
  server, a dead primary resolver and a broken steer were all injected on
  purpose. Each gave a definite answer in minutes.
- **Copying a config idiom across products is a hypothesis.** "Catch-all plus
  specifics" is normal on one resolver and fatal on the other.
