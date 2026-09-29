# fangs — homelab build log

A public build log and architecture notebook for **fangs**, a small wolf-themed
Raspberry Pi homelab. This repo is the *thinking-out-loud* half of the project:
architecture, design rationale, a running build log, and where things are headed.
The Ansible that actually configures the fleet lives in a separate private repo.

> **Scope note.** This is documentation only — no secrets, no exact addressing,
> no host MACs. Topology is described conceptually (gateway → switch → nodes).
> If you're looking for the playbooks, they aren't here by design.

> **Reading this as an AI agent?** Start with [context.md](context.md) — it orients
> you to the repo, the prime sanitization rule, and how to answer from or edit
> these docs.

## Why this exists

fangs is a homelab built to *learn the whole stack by owning it* — to replace the
black boxes of a home network with parts I configured myself and understand all
the way down. It's a handful of small, cheap machines that together do the job of
a commercial router, a NAS, and a monitoring appliance: its own gateway and
firewall, its own DNS, its own VPN egress, its own internal certificate authority,
and its own metrics-and-logs stack — and, lately, its own git forge. The home LAN
core is entirely self-hosted; the one deliberate exception is a small off-fleet
cloud box (below) that notices when the house itself goes dark — a witness has to
stand outside what it's watching — and gives remote devices somewhere fixed to
dial.

The constraint is half the fun. Most of it runs on modest ARM boards — with one amd64 workhorse
for the heavy lifting — every node is described in code and rebuildable from a blank disk, and
the rule of thumb
is *understand it before you automate it*. This notebook is where I write down how
the pieces fit, what broke on the way, and what I'm thinking about building next.

## The fleet

| Host    | Hardware       | Role          | Carries |
|---------|----------------|---------------|---------|
| `limen` | Pi 5 (4 GB)    | Gateway + observability | Routing / NAT / firewall, VPN egress, recursive DNS, passive flow transcription (Zeek), observability stack (Prometheus + Grafana + Loki) |
| `cream` | Pi 3B+         | NAS / caching / forge | Network storage, package cache, image registry, nightly log + database backups, self-hosted git forge (Forgejo) |
| `skoll` | Pi 3B          | Kiosk         | Grafana kiosk on a 7″ touchscreen in the living room — weather now and over the next few hours, severe-weather alerts, and whether the internet is up |
| `auxin` | Pi 5 (16 GB)   | Local AI / data | LLM inference (Ollama) + chat front-end (Open WebUI), embeddings, Postgres + pgvector data layer |
| `morel` | amd64 (24 GB, GTX 970) | Batch / GPU | GPU inference (Ollama), the forge's CI runner, Wake-on-LAN wake-work-sleep — asleep in S3 until summoned |

`limen` is the only node on the WAN edge; everything else sits behind it on a
flat, trusted LAN.

## Outside the house

One more piece sits *outside* the LAN entirely: a small box on the free tier of a
public cloud provider, with two jobs.

- **The witness.** It notices if the whole house goes dark. It's a dead-man's
  switch, not a poller: the gateway pushes it a periodic heartbeat over its normal
  outbound-only egress, and the watcher pages out on its own path if that
  heartbeat ever stops. A watcher that reports through the thing it watches isn't
  a watcher, so this one lives outside every failure domain the fleet has.
- **The fixed point.** The house's own address on the internet drifts, so remote
  devices — and the gateway itself — dial *out* to this box's fixed address, which
  relays a split-tunnel WireGuard overlay between them. Nobody dials in to the
  house; the gateway accepts no inbound connection for remote access at all.

It's the fleet's one deliberate cloud dependency, and it exists specifically so the
*rest* of the system doesn't need one. A second free-tier box sits idle beside it,
held in reserve for a future outward-facing job.

## How to read this

- **[Architecture](architecture/overview.md)** — what the system is and the
  principles behind it.
  - [Networking](architecture/networking.md) — gateway, DNS, VPN egress, the
    kill switch.
  - [NAS & caching](architecture/nas-caching.md) — storage, the package and image
    caches, the nightly backups, and the git forge.
  - [Observability](architecture/observability.md) — metrics, logs, network flows,
    alerting, and the digests that come to you.
  - [TLS & reverse proxy](architecture/tls-proxy.md) — the internal PKI and how
    services get a clean `https://` name.
  - [Onboarding a node](architecture/onboarding.md) — how a freshly-flashed Pi
    becomes a managed, observable member of the fleet.
  - [Local AI inference](architecture/local-ai.md) — small LLMs served on-device,
    with a chat UI, so lighter AI tasks stay off the cloud.
  - [Data layer](architecture/data-layer.md) — Postgres + pgvector, the home for
    derived data, embeddings, and the services that would otherwise bring their
    own database.
- **[Build log](log/README.md)** — dated entries on what got built and what fought
  back, newest first. The most recent few:
  - [2026-08 — A spry little forge](log/2026-08-forgejo-spike.md)
  - [2026-08 — The couch learns to read](log/2026-08-couch-room-redesign.md)
  - [2026-08 — What counts as drifted](log/2026-08-drift-check.md)
  - [2026-08 — The road that never left the house](log/2026-08-wireguard-hub.md)
  - [2026-07 — The rotation that rotated nothing](log/2026-07-credential-rotation.md)
- **[Roadmap](roadmap.md)** — future state, open questions, things to noodle on.

## Conventions

- **Config management:** Ansible — one role per concern, hosts grouped by function.
- **OS:** lean and headless everywhere — but *not* the same OS everywhere. Raspberry Pi OS
  Lite (Trixie) on **every Pi**, including the kiosk node, which drives its touchscreen with a
  minimal Wayland compositor and one browser rather than a full desktop. The amd64 node runs a
  minimal Debian instead, and the off-fleet box runs its provider's minimal image. *Headless
  and minimal* is the fleet-wide rule; Raspberry Pi OS is not.
- **Name resolution:** every node carries the full fleet by name; the gateway
  resolves for clients. Internal services answer on `*.fangs.internal`.
- **Commit messages:** subject lines are 5-7-5 haiku. Yes, really.

The full set — layout, the sanitization rules that keep this repo safe to be
public, and how a build-log entry is structured — is in
[CONTRIBUTING](CONTRIBUTING.md).
