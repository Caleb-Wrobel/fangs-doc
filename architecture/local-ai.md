# Local AI inference

The free-agent node (the 16 GB Pi 5) runs the fleet's **local LLM inference** — small
language models served on the node itself, so lighter AI tasks run in-house instead of
going to a cloud API. Nothing leaves the network, which is the whole appeal.

## The shape

Two layers on one node:

- An **inference engine** (Ollama) serves a local API — both its native API and an
  OpenAI-compatible one, so existing tools repoint with just a base-URL change.
- A **chat front-end** (Open WebUI) puts a browser UI on top — multiple models, chat
  history, its own login, document upload for retrieval.

Both sit behind the gateway's reverse proxy at internal `*.fangs.internal` names (the
inference API and the chat UI each get one), with TLS from the fleet's own CA — the same
pattern as every other service.

## Why CPU, and what that means for model size

The node has no discrete GPU, so inference is CPU-only. That makes **memory the real
ceiling, not disk**: a model has to fit in RAM to run at a usable speed. Small models (a
few billion parameters) are comfortable and reasonably quick; mid-size models run but
slowly; anything that spills out of memory crawls. For ordinary generation, patience is
fine — but a model that doesn't fit in RAM is the wall. Disk is *not* the scarce
resource; the node's card has plenty of room for a generous library.

There's a **second wall** that only shows up with large prompts: **prefill**. Before a
CPU model emits a token it has to process the entire input, and that cost scales with
prompt size. For bounded prompts it's invisible; for a very large context it becomes
minutes of latency before the first word. So "slow but fine" holds for short tasks and
quietly stops holding for large-context *interactive* ones. (The build log entry
[Can the local node drive the coding agent too?](../log/2026-06-local-coding-agent.md)
is where this wall got measured.) The practical scope follows from it: local inference
here earns its keep on **chat, retrieval, and light single-shot tasks** — bounded
prompts — while large-context agent loops stay on hardware with a real accelerator.

This is now a settled conclusion rather than a hunch: two independent attempts — driving a
coding agent, and grounding a web search — hit the **same** prefill wall from different
directions ([the web-search entry](../log/2026-06-local-web-search.md) tells that second
story). So the division of labor is deliberate: **the heavy, agentic work lives on the cloud
model API; the local node is the in-house, private, bounded-task layer.** The chat UI does
carry an optional **web-search bolt-on** (a keyed search API, spend-capped at its free
credit) — handy for a current-events question, but a convenience rather than load-bearing,
and grounding it *well* waits on hardware that can afford the larger prompt.

So the model set leans small and spread by purpose rather than "one big model": a general
chat model, a coding model, a fast lightweight one for quick tasks, and an embedding model
for retrieval — each pulled once and kept locally. The served **context window** is raised
above the engine's small default so longer chats and retrieval prompts aren't silently
truncated, with RAM as the limit (a larger window grows the per-model memory cost).

## Running the front-end

The chat UI runs as a **rootless container** (Podman Quadlet — the same mechanism the NAS
uses for its image registry), with host networking so it reaches the local inference engine
without any port-mapping fuss. Its data — accounts, chat history, uploads — persists on the
node's own storage. The container brings its own authentication, so the UI is gated even
though the raw inference API, on the trusted LAN behind the gateway, is not.

## Reaching it

- **On the LAN:** browse the chat UI's internal name, or point a tool at the inference
  API's internal name — both resolve via the gateway and terminate TLS at its proxy.
- **Off-LAN (the usual case for the laptop):** there is no inbound port at the WAN edge by
  design, so access is an **outbound SSH tunnel through the gateway** — the inference API
  (and, if wanted, the UI) appears on a local port on the laptop, encrypted end to end, with
  nothing forwarded anywhere. A small persistent service keeps that tunnel up. Reaching it
  from the *open internet* — not just the same upstream network — without exposing a WAN
  port is a planned overlay-network step (see the [roadmap](../roadmap.md)).

## Storage, later

Models live on the node's own card today. If the library ever outgrows it, the design has
an escape hatch: keep the working set local and archive the rest on the NAS, repointed with
a single setting — rather than running inference live off network storage, which would be
slow to cold-load and would make the AI node depend on the NAS being up.
