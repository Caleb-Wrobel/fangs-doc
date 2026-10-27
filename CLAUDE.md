# fangs-doc

The public build log and architecture notes for the fangs homelab, published as a
MkDocs site. **This repo is public.** Everything committed here ends up on the
internet, history included.

Private fleet detail belongs in the private `fangs` repo, never here. This repo
describes the *shape* of the system; `fangs` holds its coordinates.

## What counts as a leak

Never commit any of these, in docs, examples or commit messages:

- **Secrets:** keys, tokens, passwords, vault contents, CA signing keys.
- **Addresses:** IPv4/IPv6 addresses and CIDRs. Use the documentation ranges
  (`192.0.2.0/24`, `2001:db8::/32`) when an example needs one.
- **Full internal hostnames:** `<node>.fangs.internal`. Bare node names (`cream`,
  `limen`) are fine, and so is the pattern `*.fangs.internal`.
- **Ports** other than 22, 80 and 443.
- **Hardware identifiers:** MAC addresses, serials, device paths.
- Anything that narrows down physical location or the upstream account.

`.gitleaks.toml` is the machine-checked version of this list.
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) is the prose version and the
writing conventions. Read it before editing docs.

## How changes reach the public

- `main` reaches GitHub **only** through `.forgejo/workflows/publish.yml`, which
  rescans the unpublished commits and pushes `main` alone. No push mirror, no
  manual push.
- Every PR to `main` must pass `leak-check`, which scans every commit in the PR.
- Changes to `.gitleaks.toml`, `ci/gitleaks.sh` or `.forgejo/workflows/` go in
  PRs of their own, so review of the gate isn't mixed with content.
- Work arrives as Forgejo issues: one issue, one branch, one PR (`Closes #N`).
  Darby reviews and merges.
- Before opening a PR: run `mkdocs build --strict` (commit first; the git plugins
  read history), and add any new page to `mkdocs.yml`'s `nav:`, which the strict
  build does not check.

## Hostnames

Each hostname is five letters and reflects that node's role: cream is "cache rules
everything around me"; skoll, the wolf that watches the world, was the
observability panel. That is the whole convention. Don't infer a broader theme
from what a name looks like.
