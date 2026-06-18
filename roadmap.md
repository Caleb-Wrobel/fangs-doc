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

The fourth node (a 16 GB Pi 5) is deliberately uncommitted. Current leaning is
**local AI/ML**:

- a local LLM runtime + a simple chat UI,
- an embedding server,
- **RAG over the fleet's own telemetry** — point a local model at the metrics and
  logs the cluster already collects and ask it questions in plain language.

The appeal is that the homelab generates exactly the kind of private, messy,
domain-specific data that a local RAG setup is good at, and nothing leaves the
network.

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

## Done recently

- ✅ WiFi failover, fleet-wide and physically verified
  ([log](log/2026-06-wifi-failover.md)).
- ✅ Centralized logs (Alloy → Loki) with nightly backup to the NAS, and a fix for
  silently-non-persistent storage.
- ✅ Reverse proxy + internal CA: clean `https://*.fangs.internal` names.
- ✅ Pressure-stall metrics live across the whole fleet.
