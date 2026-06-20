# 2026-06 — Alerts that come find you

**Goal:** stop relying on *looking* at the dashboards. Add real alerting to the fleet
— for a node overheating and for a node going dark — and have it **push to a phone**,
so a problem announces itself instead of waiting to be noticed.

The trigger was a small indignity: earlier in the week a node dropped off the network,
and the monitoring stack — whose entire job is to notice things — said nothing, because
nobody happened to be looking at it. A wall of green dashboards is worthless if it can't
tap you on the shoulder.

## Keep the alert at the query layer

The first real decision was *where* alerts should live. The metrics system has its own
alerting engine, with a separate component to fan notifications out. That's the
textbook stack. The fleet went the other way and kept alerting **inside the dashboard
layer** instead.

The reason is durability against future change. An alert defined in the dashboard layer
points at a **data source**, not at a specific collector. There's an open question on
the roadmap about whether two telemetry agents per node could one day collapse into one
— and if that ever happens, the *way* metrics are gathered changes underneath
everything. Alerts written against the metrics engine directly would have to be
reworked; alerts written against a data source just need the data source repointed. So
the alerts were put where they'd survive that churn. Bonus: the graph and the alert
built on it live in the same place.

## Two rules, and a lesson about silence

**Heat.** Each node exposes its SoC temperature; the rule watches for a *sustained*
climb past a threshold set well below where the hardware throttles. The point is lead
time — catch a dying fan or a dust-blocked vent while it's still a warning, not after
the box has already started slowing itself down.

**A node going dark.** If a host stops being scraped for long enough, page. Simple in
spirit, with one trap that's worth spelling out:

> **Don't alert on *absence* the way you alert on *badness*.**

A node that's actually down still produces a clear, readable "I'm down" signal — that's
*data*, and the rule fires on it cleanly. But "no data at all" is a genuinely different
situation: the collector itself is gone, or the target never existed. If you treat
*missing* data as an automatic page, a node on a marginal link — one that blinks out
for thirty seconds and comes back — will spam you all day. So the down-rule is told to
treat missing data as **fine**, and it's also made **slow to fire**: it wants a
*sustained* outage, not a flap. One node here genuinely rides a flaky wireless link, so
this wasn't hypothetical — it was the difference between a useful alert and a muted one.

## Delivery without standing up a mail server

For notifications, the instinct is email — and then the dread of running a mail server.
Skip all of it. Delivery is a **chat-channel webhook**: a private channel that pings a
phone, fed by a single outbound HTTPS request to a URL. No SMTP, no deliverability
tuning, nothing to host. It also fits the fleet's network posture exactly — the POST
leaves a node, rides the gateway's VPN egress, and reaches the chat service outbound
over HTTPS, so **nothing new is exposed on the WAN**.

The webhook URL, though, is a **bearer secret**: anyone who has it can post to the
channel. So it's stored encrypted in the vault, rendered to disk with tight permissions,
and kept out of logs. That last part earned itself a footnote during setup — a webhook
got exposed where it shouldn't have been, which made the rotation drill very concrete:
destroy the old one at the source, generate a new one out of band, swap it in the vault,
redeploy. A bearer credential that has leaked is a *dead* credential; the only fix is to
replace it, not to hope.

## Provisioning has two speeds (and only one needs a restart)

A small operational gotcha, captured so future-me doesn't re-learn it: the dashboard
layer reloads **dashboards** from disk on a timer — drop in a new dashboard and it just
appears, no restart. But **alert rules, contact points, and data sources** are read at
**startup**. So a dashboard change is seamless, while an alerting change bounces the
service once. Knowing which kind of change you're making tells you whether to expect a
blip — and meant trimming a needless restart-on-every-dashboard-edit that had been there
out of habit.

## What I'd tell past me

- **A dashboard you have to watch isn't monitoring; it's decoration.** The value
  arrived the moment the system could interrupt me. Build the "tap on the shoulder"
  early, not as a someday-nice-to-have.
- **Put alerts where they'll outlive your architecture.** Pinning them to the data
  source instead of the collector is cheap now and saves a rewrite later.
- **Down and silent are not the same event.** Decide on purpose what "no data" means,
  or a flaky link will train you to ignore the alerts that matter.
- **Treat a leaked webhook as already burned.** Rotate at the source; don't rationalize
  that "it's probably fine." The drill is quick once you've done it once.
- **Delivery can be boring.** A chat webhook gave push-to-phone with zero new
  infrastructure and zero new exposure — often the unglamorous option is the right one.
