# The road looks back: retrofitting the registry

**2026-07-06** · themes · workflow · archaeology

When the [themes mechanism](2026-07-workflow-themes.md) shipped, it shipped with a deliberate
non-decision: no retroactive re-labelling of past work. Themes would accrete going forward, at the
moment each feature opens, when labelling costs nothing. That entry even praised the restraint.

Today I reversed it, on purpose, with better tooling at hand. The work registry now reaches back to
the repo's **first commit** — every feature the fleet has ever shipped, registered, themed, and
searchable. Three epics, fifty-four features, and — the part I actually wanted — **thirty-five
warnings standing by the side of the road**.

## Why reverse a good decision

The accrete-only rule was right *for the labelling cost at the time*: a hand-sweep over three weeks
of history was hours of tedium for a registry that mostly answers questions about the future. What
changed is that the forensic question — *"when something breaks, what was already done under this
concern?"* — turns out to be the more valuable of the two, and it's worthless if the registry's
memory starts three weeks after the fleet's does. Half of everything this homelab has taught me
happened before the registry existed: the cache that forged package signatures, the enclosure that
was never broken, the SSID that wasn't the SSID it looked like. A forensics index that can't see
the formative mistakes indexes the wrong era.

## Archaeology, not fabrication

The history has three strata, and the retrofit respects them instead of flattening them:

- **Pre-workflow** — direct commits and early PRs, before the feature pipeline existed. These get
  registry entries with an explicit era marker and a pointer to the merge commit or PR. **No
  digests were fabricated.** A record written today about 2026-06-12 would be a forgery wearing a
  timestamp; the entry points at what was actually written at the time, and nothing more.
- **Workflow era, digest-less** — branch-per-feature discipline but no digest folder (the
  discipline was young). Same treatment: entry + pointer.
- **Digest era** — the full pipeline record exists. These get their theme declarations added to
  the original stage-0 documents, every insertion visibly marked *(retrofit)* so a future reader
  can tell the author's declaration from the archaeologist's annotation.

The vocabulary grew from three themes to ten to cover the corpus — and one candidate was
deliberately rejected. A `process` theme for workflow-and-hygiene work was on the table; it got cut
rather than minting a meta-label. The workflow documents its own evolution in its own changelog; the
registry indexes *fleet* work.

## Warnings by the side of the road

The new piece, and the reason for the whole exercise: registry entries can now carry **warnings** —
one-line lessons sitting on the exact piece of work that earned them, each pointing at where the
full story lives. The placement is the point. A theme query for networking work doesn't just list
the AP migration; it surfaces, right beside it, that the four-dot network name autocorrects into an
ellipsis that byte-mismatches invisibly. Query the caching theme and both package-cache corruptions
stand next to the cache that caused them. The lesson travels with the work, not in a separate
lessons-learned graveyard nobody queries.

Two rules kept it honest:

- **Wrong verdicts stay wrong.** The enclosure written off as faulty (it was user error), the
  kiosk zoom flag that executed perfectly on a false premise, the observability stack placed on
  the smallest node — all preserved *as the mistakes they were*, dated, with their corrections.
  A sanitized history that only remembers being right teaches nothing.
- **The warning is a signpost, not the story.** One line plus a pointer. The full narrative stays
  where it was written — the digest amendment, the gotcha list — and is never duplicated into the
  registry to drift.

## What I'd tell past me

- **A reversed decision needs a paper trail, not an erasure.** The old entry's "no retroactive
  sweep" paragraph now carries a dated supersede note pointing here. The original reasoning was
  sound for its moment; deleting it would delete the *why* of both decisions.
- **Index the era, not just the item.** Marking each entry pre-workflow vs. workflow cost one
  field and preserves the real story: the process itself was built mid-flight, and the registry
  now shows exactly where the discipline started.
- **Forensics wants the mistakes most.** If a retrofit budget only covers one thing, backfill the
  failures. The successes are in the architecture docs already; the dead ends live nowhere except
  where somebody deliberately marks the road.
