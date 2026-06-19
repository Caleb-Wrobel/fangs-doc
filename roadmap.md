# Roadmap & open questions

The noodling half of the project — where things are headed, what's undecided, and
the ideas worth chewing on while away from the keyboard.

## Near-term, fairly decided

- **Auth gate in front of the reverse proxy.** Today services rely on their own
  auth behind the proxy. A single sign-on / forward-auth layer at the proxy would
  let new services be protected by default instead of each rolling their own.
- **Registry authentication.** The internal image registry currently runs open on
  the trusted LAN. Add credentials before it carries anything that matters.
- **Fleet-wide quality pass.** Three threads from recent work:
  - a documented **dry-run convention** (every role safe to run in check mode),
  - a fleet-wide **idempotency audit** (every role reports zero changes on
    re-run — see the [WiFi failover log](log/2026-06-wifi-failover.md) for why
    this isn't a given),
  - adopt **`ansible-lint`** as a rung between syntax-check and dry-run.
- **Canonical per-node imager config.** One reproducible image definition per node
  type, so any node can be reflashed to an identical starting point without
  hand-tuning.

## The free-agent node

The fourth node (a 16 GB Pi 5) has its role now: **local AI inference** (see
[Local AI](architecture/local-ai.md) and the [build log](log/2026-06-local-ai.md)). It
serves small language models on-device — a general chat model, a coding model, a fast
lightweight one, and an embedding model — behind the gateway's proxy, with a browser chat
front-end, reachable from the laptop over an SSH tunnel. Lighter AI tasks now run in-house
instead of on a cloud API.

Still on its list:

- **RAG over the fleet's own telemetry** — point a local model at the metrics and logs the
  cluster already collects and ask it questions in plain language. The embedding model is in
  place; this is the next build, and the reason the homelab is a good fit: it generates
  exactly the kind of private, messy, domain-specific data a local model is good at.
- **Reach it from the open internet without a WAN port** — an outbound overlay network so the
  laptop can use it from anywhere, not just the upstream LAN (see *things to noodle on*).
- **Authentication on the raw inference API** — the chat UI has its own login; the API itself
  is currently open on the trusted LAN.

## Things to actually noodle on

- **A relocatable observability "satellite."** The dashboards node is now WiFi-
  capable with failover. Could it become a *wireless-first*, relocatable node —
  carry the touchscreen to another room and have it just work — rather than being
  tethered to the switch? The AP and the failover plumbing already point this way.
- **Where does the doc-site live?** This repo is plain Markdown today. A
  **MkDocs (Material) site on GitHub Pages** would add a nav sidebar, full-text
  search, and nicer phone reading once there are enough pages to warrant it. The
  Markdown doesn't change — it's purely additive when the pile gets big enough.
- **TLS trust ergonomics.** Importing the fleet CA per workstation works but is a
  manual step that's easy to forget (and looks like a broken deploy when skipped).
  Is there a smoother trust-distribution story for a home network?
- **Split-tunnel egress policy.** Right now everything goes through the VPN tunnel.
  A future milestone is policy routing so *selected* traffic can take the direct
  path — useful for things that misbehave behind a VPN — without weakening the
  fail-closed default.
- **Profile the two-agent overhead.** Every node runs both node_exporter and Alloy;
  Alloy could in principle do both jobs, and collapsing to one agent would shed
  moving parts on the smallest hardware. The fleet keeps them separate for
  compatibility and isolation (see
  [Observability](architecture/observability.md#why-node_exporter-and-alloy-stay-separate)),
  on the *assumption* that carrying both is cheap — but that assumption is
  unmeasured. Worth profiling the real CPU/memory cost on a 1 GB node before
  treating it as settled.

## Done recently

- ✅ Local AI inference on the free-agent node: small LLMs (general / coding / fast /
  embeddings) with a browser chat front-end, fronted by the proxy and reachable from the
  laptop over an SSH tunnel ([log](log/2026-06-local-ai.md)).
- ✅ Onboarded the free-agent node as a managed, observable fleet member — and shook
  out three latent infra bugs on the way ([log](log/2026-06-auxin-onboarding.md)).
- ✅ WiFi failover, fleet-wide and physically verified
  ([log](log/2026-06-wifi-failover.md)).
- ✅ Centralized logs (Alloy → Loki) with nightly backup to the NAS, and a fix for
  silently-non-persistent storage.
- ✅ Reverse proxy + internal CA: clean `https://*.fangs.internal` names.
- ✅ Pressure-stall metrics live across the whole fleet.
