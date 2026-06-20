# 2026-06 — The free agent gets a job: local LLM inference

**Goal:** stand up local LLM inference on the fleet's spare node so lighter AI tasks run
in-house instead of going to a cloud API — usable from the laptop, with a proper chat UI,
and with nothing leaving the network.

End state: a small-model inference engine plus a browser chat front-end on the AI node,
both fronted by the gateway's proxy at internal names, reachable from the laptop over an SSH
tunnel. An "install and go" that, as usual, taught a few things on the way.

## The shape

The inference engine (Ollama) installs as a service and serves a local API; a handful of
small models are pulled once and kept on the node's card. The chat front-end (Open WebUI)
runs as a rootless container at its own internal name. The laptop reaches the API as a local
port via an SSH tunnel through the gateway, and OpenAI-compatible tools repoint with a
base-URL change.

## Surprise 1 — disk wasn't the limit; memory was

The instinct was that the node's card would be the constraint, so the early plan fussed over
storing big models on the NAS. The card turned out to have plenty of room. The real ceiling
is RAM: on CPU-only hardware a model has to fit in memory to run at a usable speed, and the
node has a fixed pool. So the model set leaned small and spread by purpose (general, coding,
fast/light, embeddings) instead of "one big model," and the NAS-archive idea got demoted from
a launch requirement to a future escape hatch.

## Surprise 2 — the container user vanished at the worst moment

Standing up the chat UI as a rootless container reused the NAS's container pattern, which runs
the engine as a specific login user. Borrowing that pattern but defaulting the user to
"whoever the automation connected as" blew up — that connection identity is available when
templating a file's *owner*, but **not** when the automation resolves which user to *become*
to run the rootless commands, a context where only plainly-declared variables exist. The fix
was to declare that user as a real, fleet-wide variable rather than lean on the magic
connection value. The existing registry role had quietly dodged this for ages by always using
an explicitly-named user.

## Surprise 3 — the browser doesn't trust what the system trusts

With everything served over the internal CA, the command line was happy — but the kiosk's
*browser* still flagged the internal names as untrusted. The fleet installs its CA into the
*system* trust store, which command-line tools use; **browsers carry their own trust store**
(one flavor for Chromium, another for Firefox) and ignore the system one. So a node whose
system trusts the CA can still have an untrusting browser. The fix is browser-specific, so it
got bound to the (still-undecided) kiosk-stack milestone rather than chased now.

## Reaching it without opening the edge

The laptop usually sits off the fleet LAN, and the design keeps **no inbound port at the WAN
edge**. So access is an *outbound* SSH tunnel through the gateway: the inference API shows up
on a local port on the laptop, encrypted, with nothing forwarded anywhere, kept alive by a
small auto-reconnecting service. Reaching it from the *open internet* — not just the same
upstream network — without a WAN port is a separate outbound-overlay problem, left for the
roadmap.

## What I'd tell past me

- **Check the real bottleneck before designing around the wrong one.** The whole NAS-storage
  subplot evaporated once "disk is tight" turned out false and "memory is the ceiling" turned
  out true.
- **Magic variables aren't available everywhere.** A value that templates fine in a task body
  can be undefined in a privilege-escalation context. Declare what you depend on; don't lean
  on ambient connection state.
- **"The system trusts it" is not "the browser trusts it."** Two different trust stores; a
  happy command line tells you nothing about what a browser will say.
- **Keep the edge closed and tunnel outward.** A local port over SSH gives remote use with
  zero inbound exposure — the same fail-closed posture the whole fleet is built on.
