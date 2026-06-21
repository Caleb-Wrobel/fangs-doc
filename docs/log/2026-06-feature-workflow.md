# 2026-06 — Building features in stages

**Goal:** stop running every change as one long, sprawling effort and instead ship
features through a **repeatable pipeline** — distinct stages, each handing the next a
small written summary — so the work survives interruptions, fresh starts, and the
occasional confidently-wrong assumption. Then prove it by taking a real feature through
it end to end.

## The shape

One feature, one branch, one trip through a short pipeline: figure out **why**, then
**what** the system actually looks like today, then **how** to change it, then **how
we'll know it worked**, then **build**, then **validate**, then **land**. Between each
stage sits a "digest" — a page that carries forward only the *conclusion*, so the next
stage starts clean instead of re-deriving everything from scratch.

Two roles run it. One **holistic builder** owns the discussion, the build, and the merge
— the parts that need the whole picture in a single head. The middle research and planning
stages run in **fresh, throwaway contexts**, each producing exactly one digest. And one
rule turned out to matter more than the rest: the builder **never trusts a fresh context's
output blind** — it re-checks the conclusion before accepting it.

## The worked example

The feature was a dashboard refresh. The fleet's graphs identified each node by a bare
network address — unreadable at a glance and out of step with the wolf names used for
everything else. The job: label every node by its name, and add a small kiosk-friendly set
of boards (an at-a-glance fleet overview, a pressure/saturation view, a logs view).
Straightforward.

Except the value of the pipeline wasn't in the easy parts. It was in everything that
fought back — and, more to the point, in how *early* each thing got caught.

## Surprise 1 — the confident plan was wrong about the present

The starting plan — sketched on a phone, away from the code — was sensible and specific. It
was also wrong about the system as it actually stood, in several ways at once: it assumed a
configuration shape that didn't exist, named two reference dashboards to "retire" that
weren't installed the way it imagined, and assumed a telemetry label was present where it
wasn't. None of this was a *bad* plan. It was a plan written from memory instead of from
the source.

The **what** stage — a fresh context whose only job was to read the current system and
report back — caught every one of these before a single line changed. That is the whole
case for splitting "what do we want" from "what is actually true right now": the first is
easy to do from a comfortable chair, and easy to get wrong.

## Surprise 2 — a dashboard that wasn't what its number promised

One step was "import a well-known community dashboard by its ID." Fetched, it turned out to
be a different board than its reputation suggested — built around labels the fleet doesn't
produce, so it would have rendered empty without surgery, and redundant with one already
captured. The build stage made the call to **drop it** rather than force it, and wrote down
*why*, so the decision is traceable instead of mysterious. A pipeline that can't amend its
own plan mid-build is just a slower way to ship the wrong thing.

## Surprise 3 — the cosmetics needed two laps

Twice, the thing looked done and wasn't. A captured board labelled some tiles with both the
address *and* the name. A pressure board drew three near-identical lines per node and read
as duplicates. Neither was a real defect; both were "looks wrong" — and "looks wrong" only
shows up when a human actually looks. Each sent the work back one stage for a small fix and
a re-check. The lesson isn't that mistakes happened; it's that the pipeline had an obvious
place to *go back one step* without unravelling everything around it.

## Surprise 4 — the helper cried wolf

The validation stage ran in its own fresh context, and it reported two failures. Both were
**real data, wrongly read**: a query that returns stale history had listed long-gone
entries as though they were live, and an "it changed!" result simply meant a file hadn't
been deployed yet. The builder re-ran the checks a sharper way and both cleared. This is
exactly why the "never trust a fresh context blind" rule exists — a confident wrong answer
from a helper is more dangerous than no answer, and the only defence is to read the raw
evidence yourself.

## Surprise 5 — where the paper trail is allowed to live

The pipeline produces a stack of these digests, and they're worth keeping. The first
instinct was to park them in the loose scratchpad repo that the phone reads. But that repo
is kept deliberately **sterile** — no addresses, no usernames — and the digests are thick
with exactly that. A pre-commit check refused them, which settled the question cleanly: the
detailed paper trail lives in the **private** repo alongside the code, where coordinates
are fine; the sterile scratchpad gets a one-paragraph summary; the public log — this page —
gets the *story*. The constraint chose the filing system.

## What I'd tell past me

- **Separate "what we want" from "what's true right now," and do the second from the
  source.** The most expensive assumptions are the confident ones written from memory. A
  stage whose only job is to read reality pays for itself on the first run.
- **Let the build amend the plan — out loud.** Reality contradicts the plan often enough
  that a pipeline which can't change its mind mid-stream is brittle. The discipline isn't
  "never deviate"; it's "deviate, and write down why."
- **Give yourself an obvious 'back one step.'** Most of the fixes were small and cosmetic.
  What made them cheap was a structure where going back didn't mean starting over.
- **Never trust a fresh helper's verdict without re-reading the evidence.** The two
  scariest moments were both confident, wrong answers that *looked* authoritative. A second
  pair of eyes you don't check is just a louder guess.
- **Let your safety rails file your paperwork.** The sterility check on the public-facing
  repo didn't only block a bad commit — it decided, cleanly, where each kind of artifact
  belongs. Constraints, listened to, do design work for free.
