# Conventions

This is a public **documentation** repo — the thinking-out-loud half of fangs. The
Ansible that configures the fleet lives in a separate private repo and never
appears here. These are the rules that keep this repo coherent and, above all,
*safe to be public*. They're written for future-me first; if you're a reader, they
double as a map of how the place is organized.

## The one rule that matters: sanitization

This repo is public. The private infra repo is not. **Nothing that belongs only in
the private repo may land here** — and when in doubt, it stays out. Documentation
describes the *shape* of the system, not its credentials or its coordinates.

**Never commit:**

- Secrets of any kind — vault contents, VPN tokens, WiFi PSKs, become/sudo
  passwords, API keys, CA *signing* keys. (The CA *root certificate* is public-safe;
  its private key is not, and neither lives here regardless.)
- Exact addressing — LAN/WAN IP addresses, the upstream/ISP subnet, DHCP
  reservation values, port numbers tied to a specific exposed service.
- Hardware identifiers — MAC addresses, serial numbers, the specific USB adapter
  binding the WAN.
- Anything that narrows down physical location or the upstream account.

**Describe instead:**

- **Topology conceptually** — "the gateway → the switch → the nodes," not a subnet
  map. The ASCII diagram in [overview](architecture/overview.md) is the right
  altitude.
- **Roles by function** — "the gateway," "the NAS," "the observability node," "the
  smallest node." Wolf hostnames are fine as labels; their *addresses* are not.
- **Internal service names** — `*.fangs.internal` is fine (it resolves nowhere
  public and reveals nothing). Pair it with the *idea* of the backend, not a
  `host:port`.
- **Mechanisms, not magic strings** — explain *that* a kernel flag enables PSI and
  *why*; don't paste the exact regex or file path if it isn't needed to make the
  point.

A quick self-check before every commit: *grep your diff for an IP, a MAC, a token,
or a password, and read it as a stranger on the internet would.* If a line only
makes sense to someone who could already log in, it doesn't belong here.

## Layout

- **`architecture/`** — the *steady state*. What the system is and the principles
  behind it. Present tense, no dates. Update these when the design changes, not
  when a task ships.
- **`log/`** — *dated* build entries. What got built, what fought back, what I'd
  tell past me. Newest first. This is where the war stories live.
- **`roadmap.md`** — the not-yet: near-term decided work, open questions, and the
  "Done recently" list that points back at the log.
- **`README.md`** — the front door; keep its "How to read this" links and the fleet
  table in sync when pages or nodes change.

When you add or rename a page, update the three places that index it: the relevant
section README, the top-level README's "How to read this," and (for log entries)
the `log/README.md` list.

## Writing a build-log entry

Log entries follow a shape, because the shape is the value — it forces the lesson
out. Match the existing entries:

- Filename `log/YYYY-MM-topic.md`; title `# YYYY-MM — Topic`.
- Open with a bold **Goal:** — what you were actually trying to achieve, in plain
  terms.
- A short **"shape of the solution"** so a reader gets the end state before the
  detours.
- The **detours themselves** — "Surprise N" or themed sections. This is the point
  of the log: not that it works, but *what fought back and why*.
- Close with **"What I'd tell past me"** — the portable lessons, stripped of the
  specifics.

Tone is honest and reflective, not a press release. "This looked like a half-day
job and turned into a tour of every sharp edge" is the register. Credit the
mistakes; they're the most useful part.

## Markdown style

- **Wrap prose at ~80 columns.** Tables, code blocks, and long links are exempt.
- **Relative links** between pages (`../architecture/tls-proxy.md`), so the repo
  reads correctly on GitHub today and through MkDocs later.
- Sentence-case headings. One `#` h1 per file.

## Commit messages

Subject lines are **5-7-5 haiku**, three lines joined with ` / `:

```
a public den log / the pack writes down its own paths / nothing private leaks
```

No conventional-commit prefix here (the private repo uses one; this repo doesn't).
A body is welcome for context but optional — the haiku carries the headline.

## Building the site (future)

The repo is plain Markdown today and reads fine on GitHub. A **MkDocs (Material)**
site on GitHub Pages is a roadmap item, not a current dependency — it adds a nav
sidebar and search without changing any of the Markdown. The `.gitignore` already
excludes its `/site/` build output so the scaffold can land without churn when the
pile is big enough to warrant it.
