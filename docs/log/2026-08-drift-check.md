# What counts as drifted

**2026-08-28** · infrastructure · automation

Configuration management's whole promise is that a green, idempotent run means the
fleet matches the code. That promise had never actually been tested against a fleet
running for months, picking up a stray package here, a hand-edited file there. This is
the write-up of teaching the automation to notice when reality quietly stopped agreeing
with it — and the harder discovery underneath: *what even counts as one piece of
drift* is a real design question, not a given.

## The question before the code

The obvious plan — diff a dry-run against the live fleet, print anything that would
change — turns out to hide a much slower question: when the same stray change shows up
on every run, is that the *same* drift being reported five times, or five *new* ones?
Answering it needs an identity for a drift event, and an identity turns out to need two
independent tiers:

- **Task identity** — which task, on which host, would fire. Stable and easy: a
  dry-run's own file-and-line reference works fine.
- **Diff-content identity** — *what the change actually is*, so a config line flipping
  from A to B to A again isn't misread as "resolved."

The second one is the trap. Some task types carry their own diff content for free even
when nothing changed; others — a whole-system package upgrade being the worst offender
— report "this would change" with no way to tell *what* from the result alone, and
happily bundle a dozen unrelated package bumps into one opaque event. That's not a bug
in the dry-run — a package manager genuinely doesn't diff itself the way a config file
does — but it means the two identity tiers can't be built with the same confidence
everywhere, and pretending otherwise would have produced a tool that lied quietly on
its worst-covered case.

## Scoped down, on purpose, twice

The instinct on a feature like this is to build the whole pipeline in one pass: detect
drift, remember it, tell novel from repeat, decide what's worth paging about. That
instinct got cut back twice before any code was written. This slice does exactly one
thing — prove that a drift event, with both identity tiers, is actually derivable from
a real dry-run against the real fleet — and stops there. No memory of past runs, no
novel-vs-repeat classification (that needs history, which doesn't exist yet), no
scheduling, no alerting. Comparing today's drift against yesterday's is explicitly the
next piece, built on top of this one once it's proven, not folded in early because it
seemed adjacent.

## Proof, not a demo

The tempting way to "prove" this works is to run it against whatever the fleet happens
to be doing today and call a quiet result success. That's not proof of anything — a
quiet fleet and a broken detector look identical. The actual test: deliberately hand-
edit a config file on a live node, confirm the tool catches it with the right identity,
revert the edit, confirm the tool reports clean again. Both halves passed. Along the
way, the whole-system-upgrade bundling problem above showed up for real, not as a
hypothetical — one dry-run reported a single "this host would change" for what was
actually a dozen unrelated package updates riding together, with no way to separate
them from the task result alone. Worth knowing about the tool's blind spot before
anything gets built on top of it that assumes finer granularity than it can promise.

## Where it stands

Detection is proven and lives on its own, touching nothing — it changes no
configuration, it only reads the dry-run output that already exists. What it found
doesn't go anywhere yet; there's no memory behind it. That's next, and it's a
deliberately separate piece of work, not an afterthought bolted onto this one.
