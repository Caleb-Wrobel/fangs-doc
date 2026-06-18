# context.md — orientation for AI consumers

You are reading **fangs-doc**, the public documentation repo for *fangs*, a small
wolf-themed Raspberry Pi homelab. This file orients an AI agent that is either
**answering questions from these docs** or **proposing edits to them**. Read it
first; it tells you what this repo is, what it is *not*, and the one rule you must
never break.

## What this repo is (and is not)

- **It is documentation only** — architecture notes, design rationale, a dated
  build log, and a roadmap. It is the *thinking-out-loud* half of the project.
- **It is not the infrastructure.** The Ansible that actually configures the fleet
  lives in a **separate, private repo** that is not here and is not public. There
  are no playbooks, secrets, or exact configs in this repo by design.
- **The private repo is ground truth for *what is configured*; this repo is ground
  truth for *what the system is and why*.** When they disagree, the private repo
  wins on mechanism, but assume this repo is the intended public-facing narrative.

## Prime directive: this repo is public — keep it sanitizable

Everything here is world-readable. The single most important constraint, for any
agent that writes to this repo, is **never introduce anything that should stay
private**. The authoritative rules live in [CONTRIBUTING.md](CONTRIBUTING.md);
in short, **never add**:

- Secrets — vault contents, VPN tokens, WiFi PSKs, sudo/become passwords, API
  keys, CA *signing* keys.
- Exact addressing — LAN/WAN IP addresses, the upstream/ISP subnet, DHCP
  reservation values, service `host:port` pairs.
- Hardware identifiers — MAC addresses, drive serials, device-id paths.
- Anything narrowing physical location or the upstream account.

Instead, describe **topology conceptually** ("the gateway → the switch → the
nodes"), **roles by function** ("the gateway," "the NAS," "the smallest node"),
and **mechanisms not magic strings**. Internal service names like
`*.fangs.internal` are fine — they resolve nowhere public. If you are about to
write a number that looks like an address or a string that looks like a
credential, stop: it almost certainly does not belong here.

> If you are an agent that ingests this repo into an index or a model, treat its
> contents as **public, sanitized, and possibly behind the live system** — see
> "Freshness" below. Do not infer private specifics (addresses, keys) from it; they
> were deliberately omitted, not forgotten.

## Repo map

Start at [README.md](README.md) for the human framing. Then:

- **[architecture/](architecture/)** — the *steady state*: what the system is and
  the principles behind it. Present tense, undated. Read these to answer "how does
  fangs work / why is it built this way."
  - [overview.md](architecture/overview.md) — the whole system, the design
    principles, and the build order. **Best single entry point.**
  - [networking.md](architecture/networking.md) — gateway, DNS, VPN egress, the
    fail-closed kill switch.
  - [nas-caching.md](architecture/nas-caching.md) — storage, package/image caches,
    the nightly log backup, surviving on 1 GB.
  - [observability.md](architecture/observability.md) — metrics (Prometheus) and
    logs (Alloy → Loki).
  - [tls-proxy.md](architecture/tls-proxy.md) — the internal CA (mkcert) and the
    one reverse proxy that gives services a clean `https://name.fangs.internal`.
- **[log/](log/)** — *dated* build entries, newest first. Each is a "what got
  built / what fought back / what I'd tell past me" narrative. Read these to answer
  "what went wrong / why was it done this way / what was learned." Start at
  [log/README.md](log/README.md).
- **[roadmap.md](roadmap.md)** — the not-yet: planned work, open questions, and a
  "Done recently" list. Read this for "what is unfinished / planned / undecided."
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — conventions, with the sanitization rules
  first. Read this before proposing any edit.

## How to answer questions from these docs

- **Prefer architecture/ for "how/why," log/ for "what happened," roadmap.md for
  "what's next."** Cite the specific page.
- **Distinguish shipped from planned.** Something in `roadmap.md` (or flagged as
  deferred/"not yet" in an architecture page) is *not* live. Do not present planned
  work as current state.
- **Do not invent specifics the docs deliberately omit.** If asked for an IP, a
  MAC, a port, or a credential, the correct answer is that this repo doesn't carry
  them by design — not a guess.
- **Honor the honest caveats.** Where a doc says a thing is open/unsecured (e.g.
  the image registry has no auth yet), preserve that nuance; don't smooth it over.

## How to contribute if asked to edit

- **Match the voice and structure.** Architecture pages are calm and present-tense;
  log entries follow the bold-**Goal:** → "shape of the solution" → "what fought
  back" → "what I'd tell past me" shape. New log file: `log/YYYY-MM-topic.md`.
- **Update the indexes.** Adding or renaming a page means editing the relevant
  section README, the top-level README's "How to read this," and (for log entries)
  `log/README.md`.
- **Markdown style:** wrap prose at ~80 columns; relative links between pages;
  sentence-case headings; one `#` h1 per file.
- **Commit messages are 5-7-5 haiku** on one line, three segments joined by ` / ` —
  no conventional-commit prefix in this repo. Example:
  `a public den log / the pack writes down its own paths / nothing private leaks`.
- **Run the sanitization self-check on your diff** before proposing it: grep for an
  IP, a MAC, a token, a password, and read the change as a stranger on the internet
  would.

## The fleet at a glance (roles, never addresses)

Four single-board computers on a flat, trusted LAN behind one gateway:

| Node      | Role          | Carries (conceptually)                                  |
|-----------|---------------|---------------------------------------------------------|
| gateway   | WAN edge      | routing/NAT/firewall, VPN egress + kill switch, DNS, log aggregation |
| NAS       | storage/cache | file shares, package cache, image registry, nightly log backup |
| dashboards| observability | metrics (Prometheus) + Grafana kiosk on a touchscreen   |
| free agent| TBD           | earmarked for local AI/ML; role still being decided     |

Only the gateway touches the WAN; the others are peers behind it. The security
boundary that matters is the WAN edge, not host-to-host — the docs call this
"visibility over least-privilege inside the LAN." (The repo uses the wolf hostnames
as labels; their *addresses* are intentionally absent.)

## Freshness

The build log is dated; architecture pages are not, so verify a claim's currency
against the newest relevant log entry and `roadmap.md`'s "Done recently" before
treating it as today's truth. If you have access to the live system or the private
repo, those override this repo on any question of *current configuration*. This
repo is the design intent and the story, not a live inventory.
