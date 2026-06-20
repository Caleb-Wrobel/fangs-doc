# 2026-06 — Can the local node drive the coding agent too?

**Goal:** point a cloud-hosted *agentic* coding CLI — the kind that normally talks to
a remote model API — at the free-agent node's **local** models instead, and keep even
the coding assistant in-house. The chat UI and retrieval already run locally; this was
the ambitious next step.

Short answer: the wiring works perfectly and the node still can't do it. The reason is
worth the entry, because it's a clean lesson about matching a workload to its hardware.

## The shape (everything that went right)

- **No translation layer needed.** The assumption going in was that this would require
  a shim to convert between the coding tool's API dialect and the local engine's. It
  didn't: the local inference engine already speaks the cloud API's wire format
  natively — messages, streaming, and structured tool-calls all map straight through.
  One base-URL change and a dummy auth token, no proxy.
- **A per-session toggle, not a global switch.** The launcher points the tool at the
  local endpoint for that invocation only; the normal cloud-backed command is
  untouched. Local and cloud sessions run side by side in different terminals.

So the integration was an afternoon's work and came out tidy. Then three surprises, the
last of which is the wall.

## Surprise 1 — the "coding" model is the wrong model for *driving* the agent

An agent loop lives or dies on **structured tool-calls**: the model must emit a machine
-readable "call this tool with these arguments," not prose describing the call. The
coding-specialized model returned its tool calls as **plain text** — useless to the
agent. The general *instruct* model emitted **structured** calls that mapped cleanly to
the agent's tool format. Counterintuitive but firm: "coding" labels the training, not
the agent-driving behavior. Tool-calling is a per-model property; test it directly.

## Surprise 2 — the stock context window silently truncates

The local engine's default context window is small. An agent's system prompt plus its
tool definitions is large — and it **overflowed the window silently**, so the model
never saw its own instructions. The fix was to raise the served context to the model's
full trained window (a one-line service setting). Worth knowing the default is a trap:
nothing errors, the model just quietly works from a truncated prompt.

## Surprise 3 — the wall: CPU prefill of a large prompt

Wired correctly, right model, full context window — and a trivial "create one file"
task **timed out at ten minutes**, with the client process sitting at 0% CPU the whole
time. All ten minutes were spent waiting on the node.

The cause isn't tool-calling competence (we never got far enough to judge it) and isn't
the integration. It's **prefill**: before a CPU model generates a single token, it has
to process the entire input prompt, and an agent's prompt is huge. Measured directly:
an **~8,000-token prompt did not finish processing in five minutes**. An agent's
per-turn context is several times that, and a task takes several turns. The math
doesn't close on CPU-class hardware.

## What I'd tell past me

- **Check the wire format before building a translation layer.** The local engine
  already spoke the dialect. The shim I was about to build didn't need to exist.
- **The "coding" model isn't automatically the agent model.** Structured tool-calling
  is the property that matters, and it varies model to model. Verify it, don't assume
  it from the name.
- **"Patience is fine" has a hard edge.** For this node the standing rule was that CPU
  inference is slow but *time isn't the real constraint, RAM is*. That holds for
  generating a few hundred tokens. It **breaks** for large-context interactive work:
  prefill of a big prompt is a different cost, and on CPU it's prohibitive, not merely
  slow. Throughput and latency are not the same problem.
- **Know what the node is for.** Local inference here earns its keep on **chat,
  retrieval, and light single-shot tasks** — bounded prompts where a few seconds of lag
  is fine. Large-context agent loops belong on hardware with a real accelerator, or on
  the cloud API. The experiment paid for itself by failing fast and cheap: the
  integration is sound and reusable if the hardware ever changes.
