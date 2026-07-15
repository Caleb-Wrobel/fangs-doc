# The memory moves its thinking to the muscle

**2026-07-15** · ai · resilience

The fleet already had a memory you could talk to. Ask the chat box *"what's been failing on the
gateway this week?"* and a grounded, source-cited answer streams back — retrieval over the fleet's
own logs, running entirely on local hardware. But the answer came *slowly*. Retrieval was instant;
the **writing** of the answer crawled, because the node holding the memory has no GPU — it ground
each answer out on a CPU, tens of seconds of near-silence before the text arrived. Every latency
tweak we'd made to that chat — trimming how long the answers ran, widening then narrowing the
context — had been working around one wall: a small board doing a large-model job.

Meanwhile, in the basement, a machine with a graphics card sleeps most of the day and
[wakes on demand](2026-07-scale-to-zero.md) when someone wants it. It was built to be the fleet's
GPU brain. It had simply never been pointed at *this* job. This change points it there.

## Split the work along its natural seam

An answer is really two jobs: **find the relevant logs**, then **write the reply**. Only the second
one is slow, and only the second one wants a GPU. So the split writes itself:

- **Finding** — turning the question into a vector and pulling the nearest log chunks — stays on the
  always-on AI node, where the memory and its vector store live. It has to: it's the tier that's
  *always* awake, and it's cheap.
- **Writing** — the actual generation — now goes to the basement GPU, reached through the same
  wake-on-demand doorway the chat already used for other models. A request that arrives to a
  sleeping machine wakes it, waits the ~20 seconds it takes to stir, and then streams tokens back
  many times faster than the CPU ever could.

The retrieval never leaves home; only the heavy thinking is summoned.

## The surprise: the bigger model didn't fit

The original plan assumed the win would be *a bigger, smarter model* — the GPU could surely hold
something more capable than the small model the CPU had been running. A benchmark on real questions
killed that assumption cleanly.

The graphics card has **4 GB of memory**. A 7-billion-parameter model *almost* fits — and "almost"
is the trap: it spills nearly half its layers back onto the CPU, and the split machine runs at a
crawl, **no faster than the CPU-only node it was meant to beat**, and — tested head to head on the
fleet's own logs — it actually answered *worse*, once refusing a perfectly answerable question with
a hallucinated excuse. Meanwhile a **3-billion-parameter model fits entirely in the GPU's memory**
and runs seven-to-eight times faster than the CPU, with the best-grounded answers of everything
tried.

So the win turned out to be the opposite of the premise: not *a bigger model*, but *the same class
of small model, fully resident on the GPU instead of crawling on a CPU* — plus a lucky quality bump
from picking the better-grounded of the small models. The binding constraint was never cleverness;
it was four gigabytes. Writing the premise down early and then letting a measurement overrule it is
the whole point of doing the measurement.

## A reflex that never hangs

Handing a live user-facing feature to a machine that is *asleep by default* is a resilience
question, not just a speed one. What happens the night the basement machine won't wake — a failed
magic packet, a wedged resume, a pulled cable?

The answer must never be *"the chat hangs."* So generation is written as **prefer, then fall
back**: try the GPU; if it can't be reached, won't wake, or goes silent past a short deadline,
**re-issue the very same question to the always-on node's CPU model** and stream that instead. The
deadline does double duty — while the basement machine is waking, the connection sits open and
silent, so the same timeout that bounds "waking…" also bounds "never coming." A sleeping GPU makes
the answer *slower*; it can no longer make the answer *fail*. The always-on node stays the reflex
the whole system can fall back to — the same division of labor the fleet uses everywhere: an
autonomic tier that's always there, a summoned muscle for the heavy lift.

One more nicety fell out of the same wiring. The command-line version of this tool — the one an
operator runs over SSH — should *not* wake the basement just to answer a terminal query. So the GPU
routing is attached only to the **chat surface's** service, not to the shared configuration the CLI
reads. Same tool, same code; the chat talks to the muscle, the terminal quietly stays home. It cost
one line of placement to get right and would have been a subtle annoyance to get wrong.

## What this leaves owed

The feature is live and proven both ways — a cold question really does wake the basement and answer
on the GPU, and a deliberately-unreachable GPU really does fall through to the CPU without a stumble.
But making a normally-asleep machine *load-bearing* for something people use has a shadow: the
fallback is so graceful that a GPU tier which quietly died would look perfectly healthy from the
chat box — every answer still arrives, just always from the slow path. That turns an old,
deferred idea into a due one: **monitor the thing by whether its work is actually getting done, not
by whether it answers a ping.** A summoned machine is excused from the usual "is it up?" alarm; the
price of that excuse is now payable. That's the next thread to pull.
