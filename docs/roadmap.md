# Roadmap & open questions

The noodling half of the project — where things are headed, what's undecided, and
the ideas worth chewing on while away from the keyboard.

## Near-term, fairly decided

- **Auth gate in front of the reverse proxy.** Today services rely on their own
  auth behind the proxy. A single sign-on / forward-auth layer at the proxy would
  let new services be protected by default instead of each rolling their own.
- **Registry authentication.** The internal image registry currently runs open on
  the trusted LAN. Add credentials before it carries anything that matters.
- **Document the dry-run convention.** Two of this thread's three parts have landed:
  **`ansible-lint`** is enforced (a pinned `production` profile plus a pre-commit gate),
  and the fleet has passed a **zero-changes idempotency baseline** (bar two documented
  exceptions). What's left is *writing the convention down* — a short doc stating every
  role must be safe in check mode and re-run to zero changes (see the
  [WiFi failover log](log/2026-06-wifi-failover.md) for why that isn't a given), as the
  bar new roles are held to.
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

- ✅ **Reach it from the open internet** — shipped as a **self-hosted WireGuard road-warrior** on
  the gateway (2026-07-08). The zero-inbound-port ideal (an overlay/mesh) was **ruled out** — the
  egress VPN's built-in mesh force-enables a vendor firewall that breaks LAN DHCP (see the
  [remote-access log](log/2026-06-remote-access.md)) — so the road-warrior won, accepting one inbound
  UDP port as the price. Split-tunnel, DNS over the gateway's resolver; it replaces the interim SSH tunnel.
- **Authentication on the raw inference API** — the chat UI has its own login; the API itself
  is currently open on the trusted LAN.

## Things to actually noodle on

- **Small-screen kiosk legibility.** On the 7″ 800×480 wall panel the dashboards fall
  back to a cramped single-column layout with oversized stat text. The first lever
  tried — a browser device-scale flag — *ran cleanly but did the wrong thing*: under
  this Wayland compositor it shrank the whole window (letterboxing the screen) instead
  of densifying the content. Open question: the right lever for **denser content that
  fills the panel** — a larger logical resolution, an output-level scale, or page zoom —
  and which of those survives reboots. A textbook *sound execution of an unsound premise*
  (see the [workflow log](log/2026-06-feature-workflow.md) on telling "wrong" from
  "incomplete"): what the flag actually does is now recorded, and the fix is a separate
  future piece of work — deliberately decoupled from the kiosk service itself, which is
  done.
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

- ✅ RAG over the fleet's own telemetry: a local command-line tool that embeds the **notable**
  log lines the cluster already collects into the pgvector store, then answers plain-English
  questions — *"what's been failing on the NAS?"* — grounded in the retrieved logs, with
  citations, entirely on local hardware. The data layer's second retrieval consumer. A
  deliberately **local** interface (not a chat bot) keeps the fleet strictly outbound-only; a
  word-boundary filter that silently matched nothing — a bug a dry-run couldn't see, only a live
  run could — was the lesson ([log](log/2026-06-telemetry-rag.md)).
- ✅ Durable NVMe storage for the stateful nodes: the AI/data node and the gateway now
  keep their state (database, metrics, logs) on real SSD instead of the SD card —
  reboot-verified, with the gateway's data plane **gated** so a missing disk fails safe
  rather than silently starting an empty store. The earlier "enclosure-or-drive fault"
  that parked this turned out to be **user error, not hardware** — the same drive runs
  fine on the board's native PCIe (the USB-bridge path was the red herring; corrected
  in the [storage debug log](log/2026-06-storage-enclosure-debug.md)). Remaining: the
  stateless kiosk node was hardened with a read-only root — then **retired** (2026-07-05): the
  toggle-and-reboot friction outweighed the benefit for a node that reflashes in ~20 minutes, so
  reflash-on-death is the strategy instead ([retiring read-only root](log/2026-07-readonly-root-retired.md)).
- ✅ A structured-data layer: Postgres + pgvector on the 16 GB node (rootless container, a
  named volume, and a nightly `pg_dump` pulled to the NAS), built infrastructure-first with the
  schema deferred to its first consumer ([log](log/2026-06-postgres-data-layer.md),
  [architecture](architecture/data-layer.md)).
- ✅ A daily fleet report that comes to you: a morning digest of 24h uptime, outages, heat
  peaks, memory pressure, and error volume, posted to its **own** chat channel — separate from
  real-time alerting so a bulky summary never competes with a page
  ([log](log/2026-06-daily-report.md)).
- ✅ The fleet dashboard as a managed kiosk: the display node, reflashed to the lean OS, now
  drives the 7″ wall display as a resilient, observable **systemd service** that reaches the
  dashboards over the proxy with **anonymous read-only** access — no hand-opened browser, no
  login wall ([log](log/2026-06-kiosk.md)).
- ✅ Re-onboarded the reflashed display node as a managed member — and shook out three latent
  fleet bugs on the way (a package-cache proxy serving error pages the new OS read as "tampered"
  indexes, a failover role that cut its own link, and the clockless-boot landmine)
  ([log](log/2026-06-reflash-onboarding.md)).
- ✅ Fleet alerting that comes to you: Grafana-managed alerts for node heat (before it
  throttles) and a node going dark, delivered as push to a phone via a chat-channel
  webhook — no mail server, outbound-only, nothing new on the WAN
  ([log](log/2026-06-alerting-discord.md)).
- ✅ Tested (and ruled out) running the coding *agent* itself on the node's local models:
  the integration works natively with no translation layer, but CPU **prefill** of a large
  agent prompt is the wall — minutes per turn, not viable interactively. Confirmed what the
  node is for (chat / retrieval / light tasks) and raised the served context window along the
  way ([log](log/2026-06-local-coding-agent.md)).
- ✅ Decided **and built** the off-LAN access story: ruled out the egress VPN's built-in mesh (it
  force-enables a DHCP-breaking vendor firewall), and landed a self-hosted WireGuard road-warrior
  (split-tunnel, one inbound UDP port) on 2026-07-08, replacing the interim SSH tunnel
  ([log](log/2026-06-remote-access.md)).
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
