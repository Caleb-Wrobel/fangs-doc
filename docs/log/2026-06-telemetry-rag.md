# 2026-06 — Asking the fleet what went wrong

**Goal:** be able to ask the fleet a plain-English question about its own logs —
"what's been failing on the NAS this week?" — and get a grounded answer with citations,
running entirely on local hardware. Retrieval-augmented generation over the fleet's own
telemetry, no cloud, no API key.

This is the **data layer's long-anticipated second retrieval consumer**. The first was the
[chaos stack](2026-06-chaos-stack.md), which embedded *self-inflicted incidents*; this one
embeds the *real, everyday logs* the whole fleet already ships to the log store.

## Why this was mostly assembly, not invention

Every moving part already existed. The AI node runs a local LLM and an embedding model. The
[data layer](../architecture/data-layer.md) is Postgres with a vector column waiting for a
consumer. The whole fleet ships its journals to a central **log store**. So "RAG over telemetry"
was less a new system than a small pipe connecting things that were already there — and it
deliberately copied the chaos stack's proven embed-and-retrieve scaffolding rather than inventing
a parallel one.

## Shape

A single small command-line tool with three modes, plus an hourly timer:

- **ingest** (the timer's job): pull the last hour's **notable** log lines from the log store,
  group them into per-source chunks, embed each chunk with the local embedding model, and store
  it in a vector table — skipping anything already stored, and pruning anything older than the
  log store's own retention window. The store is *derived*: fully recomputable from the logs, so
  it needs no backup of its own.
- **ask "…"**: embed the question, pull the nearest chunks by vector similarity, and hand them to
  the local LLM with a strict instruction — *answer only from these excerpts, cite the source, and
  if the logs don't say, say so.* It prints the answer and the sources it drew from.
- **search "…"**: the same retrieval, but no LLM — just show the matching log chunks. Cheap, and
  the honest way to inspect retrieval quality without paying for generation on a CPU-only box.

## Notable lines only, on purpose

Embedding *every* log line would be both infeasible on a small board and useless for retrieval —
the signal would drown in routine chatter. So ingest filters to **notable** lines (errors,
failures, the vocabulary of things going wrong) before embedding. It's a tunable knob, not a fixed
law; the point is that the corpus is the interesting minority, kept small enough that a
passively-cooled node can embed it on a schedule.

## The decision *not* to build a chat bot

The obvious "nice" interface would be a chat-channel bot: ask in the channel, get an answer back.
We deliberately **didn't** — and the reason is the whole security posture.

Today the fleet talks to the outside world in exactly **one direction**: outbound webhooks push
alerts and reports *out*. Nothing the fleet runs accepts an inbound instruction from a third party.
A query bot breaks that: to *receive* a question it needs an inbound path, which means a chat
service can now *cause actions* on the fleet — the first inbound control plane anywhere in the
system. For a read-only question-answerer that's a mild version, but it's a precedent worth not
setting casually. A **local CLI**, reached over the same trusted-LAN administration path everything
else uses, keeps the fleet strictly outbound-only. The chat bot is parked as a *deliberate, separate*
"open an inbound control plane" decision for another day — not something smuggled in under "RAG UI".

## What fought back: a filter that silently matched nothing

The first live run was perfect except for one detail: it found **zero** log lines, every time. No
error, no crash — ingest connected to the log store, ran, and cheerfully reported nothing to do.

The filter that selects notable lines is a regex, and it used **word boundaries** (`\b`) so that,
say, `oom` wouldn't match inside `room`. The bug was in how that `\b` survived the trip from config
file to the log store's query engine. The query language's string literals follow **Go** escaping
rules, and in a **double-quoted** literal `\b` isn't "backslash-b" — it's the **backspace control
byte**. So the engine was dutifully searching logs for backspace characters, found none, and
returned nothing.

The twist: this bug was *introduced by the fix for a different bug*. A review had correctly spotted
that the original config mangled the backslashes, and "fixed" it — but verified the fix against the
**wrong regex engine** (the config language's host language, not the log store's Go-based one). The
two disagree on exactly this point. The corrected regex passed a local test and shipped broken.

The real fix was to stop fighting escaping entirely: use a **raw (backtick) string literal**, where
`\b` is passed through untouched and reaches the matcher as a true word boundary. Verified the only
way that's authoritative — by querying the **live log store** with each variant and counting matches:
the double-quoted form returned 0; the raw form returned hundreds.

> **Two lessons.** (1) Test a query against the system that will actually run it, not a look-alike
> on your laptop. The escape rules of "regex" depend on whose regex. (2) A dry-run can't catch this
> class of bug at all — the playbook applied cleanly, the unit installed cleanly, everything was
> green. Only *running it against real data* and seeing "0 results" exposed it. It's the strongest
> case yet for the workflow's rule of **proving a feature live before declaring it done**, not just
> proving it converges.

## What it proved

Once the filter actually matched, the rest worked end-to-end on the first try: a day's worth of
notable lines embedded into the vector store across the active nodes, and a question — *"what's been
failing on the NAS?"* — pulled the right node's chunks to the top by similarity and got back a short,
**honest** answer. Tellingly, when the only matching lines were benign session-logout noise that
happens to contain the word "error", the model didn't invent an outage — it said there was nothing
real to report, exactly as instructed. Grounded, cited, and not prone to confabulation: the bar for
a telemetry assistant you'd actually trust.

The remaining work is all tuning — narrowing what counts as "notable", sizing how much context each
answer gets — none of it structural. The pipe is connected.
