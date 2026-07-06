# 2026-07 — Themes: a second axis for the work

**Goal:** give the backlog a way to say *"these things belong together"* without forcing
everything into a project shape. The feature pipeline already had two units — the **feature**
(one branch, one trip through the stages) and the **epic** (a chartered container of features
with a clear end) — but real work kept producing a third kind of thing: features that clearly
share a concern, where the concern itself **never finishes**.

## The dangling-feature problem

Security is the cleanest example. Registry authentication, SSH hardening, TLS trust — each is a
perfectly good standalone feature, and together they're obviously *about* the same thing. But
"security" is not a project. It has no deliverable, no done, no dependency order. Stretching the
epic shape over it would mean writing a charter for something that, by design, never completes —
and I like epics to have a clear end, even one that moves as the work teaches you things.

So those features dangled: real theme, no home.

## The fix — themes, orthogonal to the hierarchy

The framing that finally made it click: **themes are the top-level *objectives*; epics are the
top-level *deliverables*.** Epics feel top-level because they're the biggest thing that ships —
but they're not the top of the *why*. The objective is.

- A **theme** is a standing objective — `security`, `persistence`, `infrastructure`. It
  *persists*: no pipeline, no charter, no status of its own. The work that wears it carries the
  status; the theme outlives every item under it.
- An **epic** is a complex deliverable toward an objective, with an overarching purpose. It
  *ends*.
- A **feature** is a smaller unit of change toward a deliverable. It *ships*.

Objectives → deliverables → changes. The theme rides *alongside* the epic/feature hierarchy
rather than inside it.

The one-question discriminator: **does it finish?** Bounded and terminal → epic. Perpetual →
theme. And a guardrail keeps the line clean: the moment a "theme" grows a concrete deliverable
plus a dependency order among its pieces, that's the tell it has quietly become a project — spin
a real epic (which can still wear the theme) instead of running an unchartered one.

Themes also **inherit down the tree**: an epic declares its themes once, in its charter, and
every child feature inherits them, declaring only what it *adds*. A "secure the database" child
under a data-infrastructure epic inherits `persistence` and adds `security` — one line, no
restating.

## Why bother: themes exist to be searched

The whole point is mechanical answerability of two questions:

1. **"What open work is there toward theme X?"** — planning.
2. **"What was already done under theme X?"** — forensics, for the day something in that
   territory breaks and you want the prior art in front of you.

That drove the artifact design — three files, three jobs:

- Each feature's **"why" digest** declares its added themes in machine-readable frontmatter.
- A **dictionary** file defines what each theme word means, so labels stay consistent — the
  vocabulary is curated and finite, but expandable when a real concern emerges.
- A **registry** file is the queryable index: every feature and epic with its themes, its epic,
  and its lifecycle status, updated when work opens and when it lands. The two questions above
  are each a one-liner against it.

## Naming is a load-bearing decision

The first draft called these "tags" — and got caught in review, because in this repo "tag" is
already claimed twice: git tags, and the configuration tool's `--tags` flag that stages every
apply. A third meaning would have been a standing source of confusion in exactly the
conversations where precision matters ("run it with the security tag" — which kind?). Renamed
to **theme** before anything merged. Cheap now, expensive later.

## First customer, same day

Conventions earn trust by being used immediately. The very next feature through the pipeline — a
TLS trust-verification fix — became the first entry: `security` defined in the dictionary, the
feature registered, status flipped to landed at merge. The mechanism was deliberately shipped
**empty** otherwise: no retroactive re-labelling sweep of past work. Themes accrete going
forward, at the moment each feature opens, when the labelling costs nothing.

> **Superseded 2026-07-06.** The no-retroactive-sweep call was reversed — deliberately, with the
> original reasoning intact above. The registry was backfilled to the repo's first commit, and the
> sweep grew a new piece the original design lacked: per-entry roadside warnings. The why and the
> how: [The road looks back](2026-07-registry-retrofit.md).

## What I'd tell past me

- **Not everything bounded-looking is a project.** Some groupings are concerns, not
  deliverables. Forcing a charter onto something that never ends produces a zombie epic that
  can't close; a label with no lifecycle is the honest shape.
- **Make the grouping queryable or don't bother.** A label that only lives in prose is
  decoration. The registry — themes × status, one query away — is what turns "these belong
  together" into "show me the open security work."
- **Keep status out of the vocabulary.** Themes name *what it's about*; a separate field says
  *where it is*. Mixing lifecycle words into the label set is the first step toward the zombie
  epic again.
- **Check a new name against every namespace you already live in.** "Tag" collided with two
  existing meanings before the section was an hour old. The rename cost one word; the collision
  would have cost a little clarity forever.
