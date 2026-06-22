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
collected and writes one message a day.

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

## What comes next

This is deliberately the *known*-patterns phase — uptime, heat, pressure, error counts:
things you can write an explicit query for. Now that it produces a real daily artifact, the
open-ended "is something *off* in a way we didn't predict?" question gets concrete — this
report becomes the baseline a future retrieval-over-telemetry experiment can learn "normal"
from.
