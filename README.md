# fangs — homelab build log

A public build log and architecture notebook for **fangs**, a small wolf-themed
Raspberry Pi homelab — its own gateway, firewall, DNS, VPN egress, internal
certificate authority, and metrics-and-logs stack, built to *learn the whole
stack by owning it*.

📖 **Read the docs:** <https://caleb-wrobel.github.io/fangs-doc/>

> **Scope note.** This repo is documentation only — architecture, design
> rationale, a running build log, and a roadmap. The Ansible that actually
> configures the fleet lives in a separate private repo. No secrets, no exact
> addressing, no host MACs: topology is described conceptually
> (gateway → switch → nodes).

The full notebook lives under [`docs/`](docs/) and is published as a MkDocs
Material site at the link above:

- **[Architecture](docs/architecture/overview.md)** — what the system is and the
  principles behind it.
- **[Build log](docs/log/README.md)** — dated entries on what got built and what
  fought back.
- **[Roadmap](docs/roadmap.md)** — future state, open questions, things to
  noodle on.
- **[Contributing](docs/CONTRIBUTING.md)** — conventions and the sanitization
  rules that keep this repo safe to be public.

New to the repo? Start with [`docs/context.md`](docs/context.md) for an
orientation, then the architecture overview.

Commit subjects are 5-7-5 haiku. Yes, really.
