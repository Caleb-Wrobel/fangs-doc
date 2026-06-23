# 2026-06 — A daily report that comes to you

**Goal:** every morning, a short written summary of how the fleet did over the last
24 hours — uptime, outages, and the kinds of misbehavior we can name — pushed to the
same phone-visible chat channel the alerts use. Not real-time alerting (that already
exists); this is the "what happened yesterday" artifact.

## Shape

A timer on the gateway (where the metrics and logs already land) runs a small
standard-library script that:

- asks the **metrics store** for 24h availability, up/down transitions, peak SoC
  temperature, and memory-stall seconds per node;
- asks the **log store** for error-level log volume and service-restart churn per node;
- formats a terse digest and posts it to a **chat-channel webhook**.

No new dependencies, no new database, no new delivery channel — it reads what's already
collected and writes one message a day. *(That was the first cut. It has since moved house and
grown a memory — see "A memory, and a new home" below.)*

## A separate webhook, on purpose

It would have been trivial to reuse the existing alerting webhook. It got its own instead.
Alerting is *real-time and urgent*; the daily report is *retrospective and bulky*. Sharing
one channel would let a chatty report bury a page, and a verbose digest flirts with the
channel's rate limits. Separate webhook, separate channel — the morning summary and the
3 a.m. page never compete.

## What fought back: a 403 from the chat service

The script built a perfect report and then failed to deliver it — **HTTP 403 Forbidden**
on the POST. The webhook was valid (a hand-rolled `curl` to the same URL worked), and the
report was fine (a dry-run printed it cleanly). The difference was the **User-Agent**: the
chat service sits behind a CDN that **blocks the default User-Agent of the language's HTTP
library**. `curl` sends its own UA and sailed through; the dashboard server's alerts send
one too, which is why they'd never hit this. The fix was a single header.

> Lesson: when a request works from `curl` but not from your script against the *same* URL,
> suspect the **headers** before the credentials. A bare HTTP library is a fingerprint some
> edges reject outright.

## It earned its keep on day one

The very first run flagged the **display node peaking at ~74 °C** over 24 hours — the new
kiosk browser spiking a passively-cooled board past the heat line, which the instantaneous
reading didn't show. Exactly the job: surface the slow, the intermittent, and the
already-happened that a glance at a live dashboard misses.

## A memory, and a new home

The first cut was fire-and-forget: it posted to chat and the numbers evaporated. So you could
never ask "is the display node's heat creeping up *week over week*?" — there was no yesterday to
compare to. Right after the **database for the fleet** came online (with its schema deliberately
left for a first consumer), the report became that consumer: every run now writes **one structured
row per node** — availability, transitions, peak temperature, stall seconds, error and churn counts,
the breach list — before it posts. It has a memory.

And it moved house. The job had been running on the **gateway**, which is already the busiest, most
critical node (routing, VPN, DNS, intrusion detection, the proxy). A once-a-day summary has no
business adding load to the edge. It now runs on the **16 GB node** — the same machine that hosts
the database and the future retrieval work — so the write is **local**, and a non-critical batch job
is off the gateway. The trade is that the report's *sources* (the metrics and log stores) now live on
a different machine, so it queries them across the LAN — which meant opening exactly **one port on
the gateway's firewall, LAN-side only, never on the WAN edge**.

### What's stored: data, never the rendered text

The database holds the **structured numbers only** — never the formatted message. The text is
re-rendered from the rows on every run, and its format *will* change as the report grows; a stored
blob would just rot out of sync with both the live format and the (still-rough-draft) schema. Keep
the data; regenerate the prose.

### Two doors into the database

A small architecture knot worth recording. The report's scheduled job runs as **root** (it's a
system service). The database is a **rootless container owned by the login user**. Root can't reach
into another user's rootless container — so there isn't *one* path to the database, there are **two**,
split by privilege:

- **At deploy time**, the schema and a deliberately **insert-only** writer role are created *as the
  container's owner*, reaching in the way only that user can.
- **Each night**, the report writes its rows over a **local network connection** as that insert-only
  role — it can add rows to its one table and read nothing else. A reporting script should never hold
  the keys to the whole database.

### Persist first, and never let the database silence the morning

The write happens **before** the chat post, and it's **non-fatal**: if the database is down, the
failure is logged and the report still goes out. Two failure shapes, both handled — the durable
record survives a chat outage (it's written first), and a database outage can't cost you the morning
summary (the post doesn't depend on it). The acceptance test literally pulled the plug: with the
database stopped, the report still posted, logged the refused connection, and wrote no half-row.

> Lesson from the rollout: a **dry-run of the deploy** failed where the real deploy wouldn't —
> a "start this service" step referenced a unit that a *simulated* run never actually writes to disk,
> so it errored looking for something that only exists after a real apply. The fix was to skip that
> one step in dry-run mode. When a check-run fails on a resource an earlier check-only step didn't
> truly create, suspect the simulation, not the change.

## What comes next

The known-patterns phase is now also a *recorded* one — uptime, heat, pressure, error counts, written
down every day. That turns the open-ended "is something *off* in a way we didn't predict?" question
concrete: there's finally a growing baseline of "normal" sitting in a query layer, right next to the
embedding model, for a retrieval-over-telemetry experiment to learn from.
