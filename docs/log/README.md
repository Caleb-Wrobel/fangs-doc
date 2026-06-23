# Build log

Dated entries on what got built, what fought back, and what I'd tell past me.
Newest first.

- **2026-06** — [Breaking the fleet on purpose (the access gate)](2026-06-chaos-stack.md): the
  start of a chaos-engineering harness — inject known, self-reverting faults into the two leaf nodes
  *only* (the gateway and AI node are never targets) to prove alerts fire and nodes recover, with
  blind spots ("broke X, nothing paged") as first-class output. This is the fleet's first multi-part
  *epic*; the first piece is the **access gate**: a locked-down robot identity whose key can run
  exactly one program (no shell), which validates every request against a root-owned catalog and arms
  a **victim-local dead-man** so recovery never depends on the controller. It ships **inert** — a
  complete, idempotent capability that does nothing until a later piece calls it.
- **2026-06** — [A database for the fleet](2026-06-postgres-data-layer.md): standing up a
  Postgres + pgvector data layer on the 16 GB node — rootless Podman, a named volume (to dodge
  the rootless permission fight), the official multi-arch pgvector image, a read-only backup
  role, and a nightly `pg_dump` *pulled* by the NAS. Built deliberately empty: the schema waits
  for the first consumer so it's shaped by a real need, not a guess. The microSD risk is owned,
  not avoided — Postgres holds only derived data, and the nightly dump bounds loss to a day.
- **2026-06** — [A daily report that comes to you](2026-06-daily-report.md): a morning
  retrospective digest — 24h uptime, outages, heat peaks, memory stalls, error volume — posted to
  its **own** chat channel (separate from real-time alerting, so a bulky summary never buries a
  page). It earned its keep on day one, flagging the display node peaking ~74 °C under the new
  kiosk. The fight: the chat service's CDN 403'd the script's default HTTP User-Agent — `curl`
  worked, so it was a header, not a credential. This is the baseline a future telemetry-RAG unit
  will learn "normal" from.
- **2026-06** — [Re-onboarding a reflashed node](2026-06-reflash-onboarding.md): wiping the
  display node to the lean OS was routine for the *node* — three pieces of the fleet around it bit
  instead. A package-cache proxy with an empty upstream served error pages the new OS read as
  "signature manipulated"; the WiFi-failover role cut its own connection when run over WiFi (now
  guarded); and the clockless boards needed a "is the clock synced?" onboarding check. Keeper: a
  "new node" failure is usually the fleet around it, and you rule out the dramatic explanation last.
- **2026-06** — [The kiosk, as a real service](2026-06-kiosk.md): rebuilding the little
  touchscreen dashboard as a managed **systemd service** on the now-lite display node —
  restart-on-crash, logs to the central store, start-after-network, and its own up/down alert —
  instead of a hand-opened browser. Chose the service over an autologin shell (more seat/session
  plumbing, but resilient + observable; on-box debug buys nothing on a node that's useless
  offline). The login wall is solved (anonymous read-only access, plus a full-URL fix so kiosk
  mode survives the slug redirect); the small-screen scale lever — which shrank the whole window
  instead of densifying content — is still parked.
- **2026-06** — [Moving the watchtower](2026-06-observability-relocation.md): relocating the
  observability stack (metrics DB + dashboards) off the strained 1 GB node onto the always-on
  gateway, built portable (assigned by inventory group, endpoints via stable proxy names) so it can
  move again with a one-line change. The detours carried the lessons: I blamed the kiosk browser but
  a baseline showed the *dashboard server* was the real RAM hog; "roomiest host" lost to "most
  reliable host" because the alerter inherits its host's uptime; the perishable before-state had to
  be captured before the move erased it; and a dry-run "failure" was just check-mode's install-then-
  start blind spot.
- **2026-06** — [Building features in stages](2026-06-feature-workflow.md): formalizing a
  repeatable feature pipeline — why → what → how → proof → build → validate → land, with a
  small written digest handed between stages — and proving it by shipping a dashboard refresh
  (nodes shown by name, not address). The pipeline's worth showed up in what it caught early: a
  confident plan that was wrong about the present, a community dashboard that wasn't what its
  number promised, two cosmetic go-back-one-step loops, and a fresh-context helper that returned
  confident wrong answers — caught only because its verdict got re-checked.
- **2026-06** — [Durable storage: enclosure-or-drive debug (parked)](2026-06-storage-enclosure-debug.md):
  a new NVMe SSD won't enumerate through its USB enclosure — bridge appears, drive reads as
  zero bytes. Carrying the *same* enclosure to a second host gave the identical result, which
  eliminated the entire host as a variable in one replug. Drive-type mismatch ruled out too;
  what's left (bad cable / dead drive / dead enclosure) needs a spare part that isn't on hand,
  so it's shelved. The keeper is the method: host before part, one variable at a time, don't
  buy a theory you can't test.
- **2026-06** — [Alerts that come find you](2026-06-alerting-discord.md): real fleet
  alerting — node heat (before it throttles) and a node going dark — pushed to a phone via
  a chat-channel webhook, no mail server and nothing new on the WAN. Lessons: keep alerts
  at the data-source layer so they survive a change in collection, don't page on *absence*
  the way you page on *badness*, and treat a webhook URL as the bearer secret it is.
- **2026-06** — [A web search bolt-on, and the local-agentic question answered](2026-06-local-web-search.md):
  giving the local chat a web-search capability — a self-hosted metasearch that CAPTCHA-blocked
  under any load (and *not* because of the VPN — checked), then a keyed API whose free tier had
  quietly gone metered since I last knew it. Search fires, but grounding hits the same CPU-prefill
  wall as the coding agent. Two failures from two directions settle it: the local node isn't an
  agent runtime on this hardware — and that's fine, it was never the job.
- **2026-06** — [Can the local node drive the coding agent too?](2026-06-local-coding-agent.md):
  pointing a cloud agentic coding CLI at the node's local models. The wiring is native (no
  shim) and the integration is tidy — but CPU prefill of a large agent prompt is a hard wall
  (an ~8k-token prompt didn't finish in five minutes). Three surprises, and a clean lesson on
  matching the workload to the hardware.
- **2026-06** — [Reaching in from outside](2026-06-remote-access.md): how to use
  internal services (the local AI especially) from a machine off the home LAN.
  The clever shortcut — the VPN's built-in mesh overlay — turned out to be welded to
  a vendor firewall that silently eats LAN DHCP, and a read-back assertion caught it
  before it shipped. The mesh stays off for two reasons now, not one.
- **2026-06** — [The free agent gets a job: local LLM inference](2026-06-local-ai.md):
  small models served on-device with a chat UI, so lighter AI tasks stay off the cloud.
  Three lessons on the way — memory (not disk) is the model ceiling, a magic variable that
  vanished in a privilege-escalation context, and a browser that won't trust what the system
  trusts.
- **2026-06** — [Onboarding the free agent](2026-06-auxin-onboarding.md): bringing
  the fourth node in was trivial (membership is one inherited baseline) — but a fresh
  node exercising old infrastructure flushed out three latent bugs: a package cache
  bound to loopback after a cold boot, cache dirs unwritable from a pre-reflash owner,
  and first-boot provisioning silently rewriting the hosts file on every boot.
- **2026-06** — [Pressure-stall metrics, fleet-wide](2026-06-psi-fleetwide.md):
  PSI on every node so one dashboard shows which box is actually straining. A
  one-flag feature that touched the bootloader — including a whitespace edge case
  that appended a second line to `cmdline.txt` and nearly cost a node its boot.
- **2026-06** — [WiFi failover](2026-06-wifi-failover.md): wired-primary /
  WiFi-standby with IP held across the flip. A short job that became a tour of
  netplan/NetworkManager idempotency, single-radio AP constraints, and a
  failback address-conflict bug.
- **2026-06** — [Centralized logging](2026-06-centralized-logging.md): every
  node's journal shipped to Loki on the gateway, queryable beside the metrics,
  backed up nightly to the NAS. Two reboots' worth of lessons: a "retention"
  window that lived on a tmpfs, and why journal labels have to be set at the
  source.
- **2026-06** — [Internal CA & reverse proxy](2026-06-tls-reverse-proxy.md): a
  clean `https://name.fangs.internal` for every service via one mkcert CA and one
  nginx proxy, with services declared a line at a time. Where it bit:
  proxy-and-DNS as an inseparable pair, reload-vs-restart on first install, and a
  trust step that looks like a broken deploy.
