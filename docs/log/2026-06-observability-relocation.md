# 2026-06 — Moving the watchtower

**Goal:** the node whose whole job is *watching* the fleet had started to struggle — it was
swapping hard, sometimes too busy to even answer an SSH prompt. Move the observability stack
(the metrics database and the dashboard server) **off** that small node onto a roomier one — and
do it so the stack is **portable**, able to move again later with a one-line change rather than a
rewrite.

## The shape of it

The small node is a 1 GB box; it hosted both the metrics DB *and* the dashboard server *and* drove
a kiosk screen — three jobs fused onto the weakest hardware. The fix: lift the metrics DB and
dashboard server onto the **always-on gateway** (which already runs the log store and the reverse
proxy), leaving the small node as a thin kiosk plus its own per-node agents.

Two design choices made it portable rather than a one-off shuffle:

- **Assign the stack by an inventory *group*, not a hostname.** The play that stands it up targets
  "whoever is in the observability group." Relocating it is then just changing which host is in
  that group — no task edits.
- **Wire every endpoint through the internal proxy names.** The dashboard server reaches the metrics
  DB and the log store by their stable `*.fangs.internal` names, not by `host:port`. So nothing
  downstream knows or cares which machine a daemon actually runs on. Move the daemon; the names
  don't change.

It worked, and the gateway absorbed the whole stack while still sitting at ~80% memory free. But the
lessons were in the detours.

## Surprise 1 — I blamed the wrong thing

The obvious culprit for the small node's memory pain was the **kiosk browser** — browsers are
notorious memory pigs, and this one renders a dashboard all day. I was ready to attack it.

Then I took a baseline before changing anything, and the numbers said otherwise: the **dashboard
server** was eating roughly *three times* what the browser was. The browser was a rounding error by
comparison. Had I "optimized" the kiosk I'd have moved a small number and declared partial victory
while the real hog kept swapping.

> Measure before you blame. The intuitive suspect and the actual one are often different sizes.

## Surprise 2 — roomy isn't the same as right

The intuitive home for the relocated stack was the node with the most RAM — the spare/experiment
box. Plenty of headroom, obvious choice.

But the dashboard server is also where the **alerting** lives, and an alerter is only as reliable as
the host it runs on. The experiment box is, by definition, the one I poke at, reboot, and push to
its limits. Putting the thing that's supposed to tell me when the fleet breaks on the *least stable*
node is exactly backwards. The **always-on gateway** — the box that's up whenever anything works at
all — is the right home, even though it has less spare RAM. (It had plenty for a lightweight stack
anyway.)

> Put the alarm where it will stay powered. Reliability of the host beats raw capacity.

## Surprise 3 — capture the "before" before you can't

The move deliberately accepted **losing the metrics history** (a fresh database on the new host —
not worth the ceremony of migrating it). Which meant the "before" picture was *perishable*: once the
stack moved, I could never query the old node's history again to prove the change helped.

So the baseline got captured up front and saved as plain numbers in the project notes — RAM free,
swap, pressure — with the exact queries to re-run afterward. The payoff was a clean before/after:
the small node went from teens-of-percent memory free (with real, measurable stall pressure) to
comfortably past half free, pressure flat at zero.

> If a measurement is about to become unrepeatable, take it now and write it down as data.

## Surprise 4 — losing the local shortcut

Once the dashboard server left the small node, that node could no longer reach it at "localhost" —
it now has to resolve the service **by name**, through the proxy, like every other client on the
network already did. That's not new fragility; the node simply joined the normal path. But it does
make name resolution load-bearing for the kiosk, so I added a static name→host fallback on every
node — belt and suspenders, so a hiccup in the resolver can't blind the screen.

> Centralizing a service quietly turns "localhost" conveniences into real network dependencies.
> Name them, and give them a fallback.

## Surprise 5 — the dry-run that cried wolf

The pre-flight dry-run "failed": it errored trying to *start* the freshly-installed dashboard
server. Heart-stopping for a second — until I remembered what a dry-run is. In check mode the
install is only *simulated*, so the very next "start the service" step looks for something that was
never actually installed and reports it missing. A real run installs first, then starts, and is
fine. The tool wasn't wrong; I'd asked it to do something it structurally can't.

> Know which failures your tools invent. "Install X then start X" always trips a dry-run.

## What I'd tell past me

- **Measure before you blame.** The browser was the obvious villain; the dashboard server was the
  actual one. A five-minute baseline saved a wasted afternoon.
- **Put the alerter on the most reliable host, not the roomiest.** Whatever runs your alarms inherits
  that host's uptime. The always-on box wins over the spare-capacity box.
- **Make it portable and the next move is free.** Assign by group, address services by stable name;
  relocation becomes an inventory edit instead of surgery.
- **Grab perishable "before" state immediately** — the moment you accept losing history, your
  baseline is on a timer.
- **Learn your tools' built-in lies.** A dry-run can't install-then-use; don't let its fake failure
  scare you off the real run.
