# 2026-06 — A web search bolt-on, and the local-agentic question answered

**Goal:** give the local chat UI the ability to search the web, so the in-house assistant
could answer about current events instead of only what its weights remember. The original
framing was bigger than "a nice feature" — web search felt like *essential infrastructure
for a local agentic workflow*. That framing is what this entry ends up retiring.

## Detour 1 — the self-hosted metasearch that couldn't

The first design put a **self-hosted metasearch** in front of the chat UI: local, no
account, no quota — it queries public search engines on your behalf and aggregates the
results. It fit the in-house ethos perfectly, and every component tested green in
isolation: the metasearch returned results, the chat UI reached it, pages were fetched and
embedded.

Then a proof-of-concept against the **real** path — not the components, the whole pipeline
as the UI actually drives it — told a different story. Under any repeated use, the public
engines it scrapes start returning **CAPTCHA/anomaly pages instead of results**. The
aggregator is only as reliable as engines that actively defend against being scraped, and
they win. The "free, unlimited" path was free and unlimited right up until it returned
nothing.

A tempting explanation was the gateway's VPN exit — shared VPN addresses get challenged
more than residential ones. **It was worth checking before believing.** Same query, same
instant, two egress paths (through the tunnel vs. out the bare uplink): **identical
challenge pages, zero results, both ways.** Not the VPN. The scraping itself is the
problem, and no amount of network plumbing fixes it. (A read-back habit earns its keep
again — the wrong theory would have sent me rebuilding routing for nothing.)

Retired. Worth building only to learn — fast and cheap — that it was the wrong tool.

## Detour 2 — the API that changed under us

The reliable answer was a **keyed search API** — a commercial endpoint that returns
results without scraping or CAPTCHAs. It worked first try and every try. But the lesson is
a little humbling: **the service's terms had changed since my prior knowledge of it.** What
I "knew" as a generous free tier had, months earlier, become **metered billing** — a small
monthly credit, then it charges the card.

The fix was to stop trusting memory and **read the current state from the source**: the API
itself reports the account's real rate and quota in its response headers. That's ground
truth — not the docs, and certainly not training data. The key is now hard-capped at the
free credit, so the worst case is "search quietly stops" rather than "surprise bill," and
the design degrades gracefully when the credit's spent.

Restated as a rule: **for anything that bills or rate-limits, verify the present terms
against the provider, not against what you remember.** Providers move; assumptions don't
update themselves.

## The real finding — search fires, grounding doesn't

With a reliable engine wired in, the search **runs**: query out, pages back, content
embedded. And the model still answered from its training — confidently calling a superseded
release "current," with no sources attached.

The cause is the same wall as the coding-agent experiment, from a new angle. The chat flow
embeds the fetched pages and then **retrieves only the few most-similar chunks** to feed the
model — and the chunk that actually held the answer didn't make that short list (small
embedding model, no reranker). The lever that *would* fix it is to inject the **full**
fetched content instead of a retrieved slice — but that's a large prompt, and on this CPU
node a large prompt means the **prefill wall** again: minutes before the first token.
Reliable grounding and bounded latency pull in opposite directions on this hardware.

## What this answers

Two independent experiments — driving a coding agent
([entry](2026-06-local-coding-agent.md)), and grounding web search — hit the **same
CPU-prefill ceiling** from different directions. That's enough to call it: **pure local
*agentic* workflows are not viable on current hardware.** Not a config gap, not a model
choice, not a missing shim. The node is excellent at what it was always good at — chat,
retrieval, bounded single-shot tasks — and that is its job.

The resolution is a clear division of labor, not a workaround: **the heavy, agentic work
lives on the cloud model API** (now on a sustainable subscription tier), while the local
node stays the in-house, private, bounded-task layer. Web search stays as a **bolt-on** the
chat UI can use — handy, not load-bearing — and the grounding fix waits until there's a
reason to spend the latency: specifically, on-prem agents that genuinely need external
search, which themselves wait on hardware with a real accelerator.

## What I'd tell past me

- **Test the integration, not the parts.** Every component passed alone; the assembled
  pipeline was flaky. The PoC against the real path is what surfaced it — and what kept a
  half-working feature from shipping as "done."
- **Check the provider's current terms.** A free tier I relied on had become metered. The
  API's own response headers are the truth; memory and old docs are not.
- **Say "I haven't verified" out loud, then verify.** "It's probably the VPN" was wrong, and
  a five-minute A/B proved it before it cost an afternoon.
- **Two failures from two directions is a conclusion, not a coincidence.** The local node
  isn't an agent runtime on this hardware. Naming that plainly is worth more than one more
  clever attempt.
