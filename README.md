# fangs — homelab build log

A public build log and architecture notebook for **fangs**, a small wolf-themed
Raspberry Pi homelab. This repo is the *thinking-out-loud* half of the project:
architecture, design rationale, a running build log, and where things are headed.
The Ansible that actually configures the fleet lives in a separate private repo.

> **Scope note.** This is documentation only — no secrets, no exact addressing,
> no host MACs. Topology is described conceptually (gateway → switch → nodes).
> If you're looking for the playbooks, they aren't here by design.

## Why this exists

fangs is a homelab built to *learn the whole stack by owning it* — to replace the
black boxes of a home network with parts I configured myself and understand all
the way down. It's a handful of cheap single-board computers that together do the
job of a commercial router, a NAS, and a monitoring appliance: its own gateway and
firewall, its own DNS, its own VPN egress, its own internal certificate authority,
and its own metrics-and-logs stack. Nothing depends on a cloud account; the only
thing it asks of the outside world is an internet handoff.

The constraint is half the fun. Everything runs on modest ARM hardware, every node
is described in code and reproducible from a wiped SD card, and the rule of thumb
is *understand it before you automate it*. This notebook is where I write down how
the pieces fit, what broke on the way, and what I'm thinking about building next.

## The fleet

| Host    | Hardware       | Role          | Carries |
|---------|----------------|---------------|---------|
| `limen` | Pi 5 (4 GB)    | Gateway       | Routing / NAT / firewall, VPN egress, recursive DNS, IDS/IPS, log aggregation |
| `cream` | Pi 3B+         | NAS / caching | Network storage, package cache, image registry, nightly log backups |
| `skoll` | Pi 3B          | Observability | Metrics (Prometheus), dashboards (Grafana kiosk on a 7″ touchscreen) |
| `auxin` | Pi 5 (16 GB)   | Free agent    | TBD — earmarked for local AI/ML |

`limen` is the only node on the WAN edge; everything else sits behind it on a
flat, trusted LAN.

## How to read this

- **[Architecture](architecture/overview.md)** — what the system is and the
  principles behind it.
  - [Networking](architecture/networking.md) — gateway, DNS, VPN egress, the
    kill switch.
  - [NAS & caching](architecture/nas-caching.md) — storage, the package and image
    caches, and the nightly log backup.
  - [Observability](architecture/observability.md) — metrics and logs.
  - [TLS & reverse proxy](architecture/tls-proxy.md) — the internal PKI and how
    services get a clean `https://` name.
- **[Build log](log/)** — dated entries on what got built and what fought back.
  - [2026-06 — Pressure-stall metrics, fleet-wide](log/2026-06-psi-fleetwide.md)
  - [2026-06 — WiFi failover](log/2026-06-wifi-failover.md)
  - [2026-06 — Centralized logging](log/2026-06-centralized-logging.md)
  - [2026-06 — Internal CA & reverse proxy](log/2026-06-tls-reverse-proxy.md)
- **[Roadmap](roadmap.md)** — future state, open questions, things to noodle on.

## Conventions

- **Config management:** Ansible — one role per concern, hosts grouped by function.
- **OS:** Raspberry Pi OS Lite (Trixie), headless, across the fleet (one node runs
  the full desktop image to drive a kiosk touchscreen).
- **Name resolution:** every node carries the full fleet by name; the gateway
  resolves for clients. Internal services answer on `*.fangs.internal`.
- **Commit messages:** subject lines are 5-7-5 haiku. Yes, really.

The full set — layout, the sanitization rules that keep this repo safe to be
public, and how a build-log entry is structured — is in
[CONTRIBUTING](CONTRIBUTING.md).
