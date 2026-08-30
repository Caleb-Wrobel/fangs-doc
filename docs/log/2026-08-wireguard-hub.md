# The road that never left the house

**2026-08-20** · infrastructure · networking

The off-fleet watcher box — the one that lives outside every failure domain the house shares,
whose whole job is to notice when home goes dark — had been torn down on purpose, its job done,
its lesson banked. It came back this week for a different reason entirely: not to watch the
fleet, but to be *found* by it. What followed was a redesign, three real bugs, one honest
misdiagnosis owned in public, and finally a phone on a cellular network proving the whole thing
actually works.

## Standing the outpost back up

The free-tier cloud shape I'd used before had gone from "hard to get" to "impossible to get" —
capacity exhausted everywhere I checked, not just on that one provider. So the second incarnation
landed on a small paid box instead, on different hardware, running the same self-written
dead-man's-switch service (now in its second implementation, a rewrite in a different language
against the same behavioral contract the first one satisfied — the two are interchangeable by
design).

Two real bugs showed up standing it back up, and neither would have happened on the fleet's usual
hardware family:

- A container runtime needs several small helper binaries to run a multi-container pod —
  something the fleet's other machines had always had for free, bundled by their OS images. This
  one's minimal cloud image didn't ship any of them, so the deploy failed three times in a row on
  three different missing tools before the full list was actually complete.
- The very first time the pod's containers touched the network, they lost a race against the
  container runtime's own internal DNS resolver — it hadn't finished starting yet. The fix was a
  retry, already built into the front door's own certificate-issuance logic, so it healed itself
  within a couple of minutes without anyone noticing. Worth writing down anyway, because it's the
  kind of thing that looks like a flake the second time and a mystery the third.

Both landed, verified end to end: a real publicly-trusted certificate, the dead-man's-switch
answering correctly, and the managed check-in service it reports to receiving its first real
ping.

## The wrong lock

The actual reason the box came back wasn't the watcher — it was a much older, unglamorous
problem. The gateway's own address on the wider internet changes, because it sits behind an
ordinary home connection, and nothing had ever tracked that change automatically. Every remote
client's configuration pointed at whatever address happened to be current the day it was written.
That address had already gone stale once this year, quietly, when the home connection's provider
changed itself overnight.

I went looking for a shortcut first, because I'd already paid for what looked like one: a static
address add-on from a VPN service the fleet already uses for outbound traffic. It turned out that
specific product doesn't do what I needed at all — the feature I wanted lives on a different,
pricier product entirely, confirmed only after actually reading the provider's own documentation
instead of assuming. Recording the dead end here because chasing it cost real time, and the
lesson generalizes better than the fix would have: read the fine print on a feature before
building a design around owning it.

## Flipping who has to be found

The dead end pointed at the actual fix, which had been sitting in plain sight the whole time: the
gateway didn't need a way to be found. It needed to stop needing to be found at all.

The off-fleet box has something the gateway doesn't — an address that doesn't move. So the whole
shape inverted. Instead of the gateway listening for connections and every remote device dialing
in to it directly, the off-fleet box became the one fixed point, and *everything else* — the
gateway included — now dials **out** to it. The gateway looks, from the outside, exactly like any
other roaming device: no port open, nothing to find, nothing to track. The off-fleet box relays
between whoever connects to it and the gateway, and the gateway forwards the relayed traffic on
into the house the same way it always did.

The payoff is a genuine subtraction, not a trade: the gateway's public-facing firewall lost a
rule instead of gaining one. The attack surface went down.

## Three bugs in the plumbing

Getting there took three real, distinct failures — the kind that only show up building the thing
for real, not designing it on paper.

**The network manager was never running.** The off-fleet box's base image handles its own network
interface a different way than the fleet's usual machines do; the tunnel's own configuration files
were being written into a service that had never been started, so nothing ever read them. An
explicit "make sure this is actually running" fixed it — and crucially, only for the *new* tunnel
interface; the box's real network connection was never touched, verified by re-checking it hadn't
moved before declaring victory.

**A borrowed name stole an identity.** Every device in this scheme needs its own private key, kept
secret, and a public key that identifies it to its peers. One of those private keys got stored
under a name that happened to collide with a more generic variable the automation itself used
internally — and the more specific configuration silently lost to the more generic one wherever
both were loaded together. The practical effect: the gateway came up wearing a different device's
identity, and — because a device refusing to peer with itself is correct, secure behavior, not a
bug — it silently dropped the one connection that mattered. Nothing crashed. Nothing errored. It
just quietly didn't work, and the fix was a rename plus a large comment explaining exactly why
that specific name was radioactive.

**A route nobody wrote existed nowhere.** Telling a tunnel endpoint which addresses reach which
peer is supposed to be enough, on this platform, for the underlying network stack to also know
*how* to route traffic there. It wasn't, for a peer whose reachable range lived on a different
subnet than the tunnel's own. The fix was writing the route explicitly rather than trusting it to
appear — redundant on peers where it would've worked anyway, load-bearing on the one where it
didn't.

Every one of those three would have been invisible in a smoke test that only checked "does the
tunnel come up." All three only showed up because the actual proof bar was "can a real request
travel all the way from outside, through the relay, into the house, and back."

## The proof that wasn't

That proof bar mattered more than I gave it credit for in the moment. My own laptop, at home,
dialing the new relay and back, hit a real symptom — a long-lived connection dying silently every
so often, recovering on its own within a minute. I recognized the shape of it immediately, because
I'd diagnosed something that looked identical once before, months earlier, and filed it away as a
known quirk of the home connection's provider. I said so, in writing, with more confidence than I
had actually earned.

It was wrong, and it took someone else in the house to catch it, because they knew something I'd
stopped thinking about: my laptop and the fleet it's dialing out to are in the same building, on
the same router. A connection that leaves that router's public address and comes straight back in
through it never actually touches the wider internet at all — it loops. The provider was never
part of that path, that day or, probably, the first time either. What I'd been calling "the
provider's flaky handling of long connections" was never established as that in the first place;
it was, at best, a guess about a different failure mode entirely — how well the one router handles
traffic that leaves and immediately re-enters through itself — and I'd never isolated the two
possibilities from each other, then or now.

I corrected the written record rather than quietly moving on, and marked the replacement
explanation as exactly what it is — a plausible guess, not a finding, with the real open question
stated honestly: nobody has actually tested this symptom from somewhere that isn't the same
building.

## The proof that was

So I did the test properly. Not the laptop at home — a phone, on cellular data, nowhere near the
house's own network, dialing all the way out to the relay and back in. It loaded a dashboard on
the first try.

That's the actual proof the whole redesign was for — not a technical curiosity about tunnels, but
the plain, mundane thing of checking on the house from somewhere that is genuinely somewhere else.
It's also, satisfyingly, a cleaner test than the one I got wrong: cellular data never comes near
the home router at all, so there's no loop to mistake for a wire.

## Addendum — 2026-08-22: back on the free tier

The paid box didn't stay in the job long. Two days after this went live, the relay moved a third
time — off the paid provider entirely and back onto the free tier, into the second of two
free-forever slots of the relay's original shape that the account has always been entitled to
(only one had ever been claimed). Same self-written service, same behavioral contract, nothing
lost in the move. The paid box was decommissioned outright, not kept running as a spare. As of
this writing, the relay runs on free-tier capacity, full stop — that is the current, authoritative
state, not the paid-box arrangement described above.

Also worth flagging here, since it's the same account: a second, separate free-tier claim — a
different, more capable hardware shape, chased opportunistically in the background this whole
time by a small patient script that made one attempt every few minutes — eventually succeeded.
That box sits fully provisioned and idle, ready and waiting for a job. Worth its own entry once it
gets one.

## Addendum: the paid provider isn't off the table for good

Retiring the paid box from this particular job doesn't rule paid capacity out for the fleet more
broadly — there's still credit sitting unused with that provider, and it remains a live option for
whatever needs paid compute or bandwidth next. It's simply not backing anything right now, and
the free tier's generous headroom means there's no pressing reason to reach for it.
