# The alarm that rides the tunnel

**2026-11-15** · networking · security

When the edge moved from a Pi to a dedicated router, the commercial VPN stayed
behind: for a few weeks everything the house sent to the internet left in the
clear. This entry puts it back, this time on the router itself. The whole LAN
leaves through a WireGuard tunnel, the tunnel **fails closed**, and one variable
switches the house back to the plain upstream when the subscription lapses or
the provider goes away.

## The shape of the solution

The router carries a second WireGuard interface, pointed at one pinned server.
A policy rule sends anything sourced from the LAN to a separate routing table
whose only default route is the tunnel. A few rules ahead of it send local
destinations (the LAN, the remote-access tunnel, the upstream router's own
subnet) back to the main table. The router's own traffic and the remote-access
tunnel never enter the VPN, so the house can be managed from outside while the
VPN is dead.

The kill switch is a firewall rule, not a routing trick: anything forwarded
from the LAN and leaving through the upstream port is dropped. If the tunnel's
route goes away, the packet has nowhere to go. If someone breaks the routing
rule by hand, the filter catches it. Both layers were tested by breaking them
on purpose: TCP, UDP and ICMP all stopped, and the drop counter moved.

Everything is declared state applied over the router's API. The same role tears
all of it down when the switch is off, and puts back the router's factory fast
path. Switching off cost the LAN under twenty seconds of internet. Switching on
showed no gap at all.

## Surprise 1: the key that never matched

Every dry run reported the tunnel interface as changed. The private key in the
vault and the key on the router were the same key, yet they never compared
equal. The provider's API hands out the key *unclamped*. WireGuard's curve
clears and sets a few bits before using any key, and the router stores that
clamped form. Cryptographically identical, byte-for-byte different. The fix was
to store the clamped form, and the runbook's fetch command now clamps it on the
way in. I proved the match without ever printing either key: compare the two as
booleans.

## Surprise 2: the fast path was the expensive part

The router's factory config includes a "fasttrack" rule: established flows skip
most of the firewall and the routing decision. With policy routing in play, a
fasttracked flow might never see the rule that sends it into the tunnel, so it
had to go. I measured three ways before deciding: plain upstream with the fast
path, plain upstream without it, then through the tunnel. Losing the fast path
cost about a quarter of single-flow download speed. The tunnel took that down
to about a third of the fast-path figure. Upload didn't move at all, because the
upstream plan's own cap sits below every one of them.

That looked bad until I asked the metrics what the house actually uses. Over a
week, the busiest minute was about one percent of the tunnel's single-flow
rate, and the router's CPU averaged under two percent. The ceiling is real, and
nothing here comes near it.

## Surprise 3: the alarm that rides the tunnel

The tunnel got its own alert: no handshake, or no bytes received, for a few
minutes. In the outage test it fired right on time. And then it never told
anyone.

The alert's delivery path is a webhook that goes out over the internet, and
with the kill switch doing its job, the observability node has no internet. It
couldn't even resolve the webhook's hostname. Once the tunnel came back, the
alert cleared before the next send, and an alert manager doesn't announce a
recovery for a failure it never delivered. So it can *only* fire when it can't
be delivered, and it is gone by the time it could be. It records history and
pages nobody.

The page that did arrive came from the off-site heartbeat service: the
observability node stopped checking in, and fifteen to twenty minutes later a
"this node is dark" alert went out from somewhere that has its own internet.
That is the real outage pager here, and the runbook says so. "That node is
dark, and nothing else is talking" now means: check the tunnel first.

Worse, my first write-up claimed the alert *had* arrived, late, after the
restore. I'd read "no failure logged at the next retry" as "the retry
succeeded". There was no retry. The validation pass, run in a fresh context on
purpose, asked the alert manager directly when it had last tried, and the
answer was: during the outage, and never since. The fix that would let the
alert actually page is to send it out over the remote-access tunnel instead.
That's filed for later.

## Surprise 4: DNS remembers the outage

After a deliberate outage, the tunnel was back within seconds, and the LAN's
resolver stayed dead for **nine more minutes**. It forwards over DNS-over-TLS
(the provider intercepts plain DNS, so recursion was never an option), and when
both upstreams stopped answering it marked them dead and kept that verdict for
its default memory window. The upstreams were reachable long before the
resolver tried them again. A one-line cache flush clears it by hand. The proper
fix, re-probing dead upstreams sooner or serving stale answers while waiting,
is filed for later too.

## Smaller sharp edges

- The kill-switch rule took over the slot of the factory rule it replaced, and
  inherited its packet counter: millions of "drops" that never happened. Read
  firewall counters as deltas, never as totals.
- A third-party UDP DNS query fails even on a healthy tunnel, because the
  provider intercepts it. A time-server query makes a better UDP probe.
- One router API field is a flag that reads back as an empty string. Sending
  `true` made every run try to create the table again.
- `pkill -f <pattern>` over SSH matched its own session's command line and
  killed it, twice. Kill by process ID.
- The kill switch is IPv4 only. That's fine while the upstream gives no IPv6,
  and it's written down where the next IPv6 change will trip over it.
- The router resolves through the LAN resolver, which resolves through the
  tunnel. A running router keeps its remote-access tunnel up through a VPN
  outage (tested for eighty minutes). A router that *reboots* during one might
  not be able to find its remote-access hub by name. That case is filed, not
  fixed.

## What I'd tell past me

- Measure the real load before arguing about the ceiling.
- An alert that travels over the path it watches is a log entry, not a pager.
  Test delivery, not just firing.
- The absence of an error is not a success. Ask the system what it actually
  did.
- When a secret won't compare equal, check what the far end does to it before
  storing it.
- Recovery has its own latency. Time it from the user's point of view: from
  "the tunnel is back" to "the house can resolve a name", not "the interface
  is up".
- Build the off switch as carefully as the on switch, and run both in the test.
