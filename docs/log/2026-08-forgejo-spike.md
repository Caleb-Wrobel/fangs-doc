# A spry little forge

**2026-08-29** · infrastructure · self-hosting

Self-hosting a git forge — issues, pull requests, and eventually CI — on the fleet's
own small NAS node has been a standing idea for a while, blocked on one honest
unknown: does the smallest, most memory-constrained node in the fleet actually have
room for it, or is that wishful thinking dressed up as a plan? Generic advice online
says no, or at least "not comfortably" — but that advice assumes a multi-user server
running its own CI jobs on the same box, and neither assumption held here. Rather than
keep guessing, this stood the real thing up, measured it under real load, and tore it
back down the same day.

## Designed to be thrown away

Every choice in this deployment was made for speed of measurement, not for
correctness of the eventual real thing: a bundled single-file database instead of the
fleet's normal shared database server, plain HTTP on the LAN instead of the usual
TLS-everywhere treatment, and throwaway credentials rather than anything that needed
protecting. That's not corner-cutting — it's the right shape for a question that's
purely "does this fit," asked and answered in isolation, with nothing to unwind
carefully afterward because nothing load-bearing was ever built on top of it.

## The measurement, not the guess

Deployed live, the fleet's own full git history — every branch, several megabytes of
it — was pushed in as a real mirror, and a genuine build-runner was registered against
it on the fleet's spare compute node, which is normally powered off between jobs. A
real workflow ran end to end. The numbers that came back were the actual point of the
exercise: idle memory use crept up only modestly from the node's baseline, and even
the heaviest moment measured — pushing the entire mirrored history at once — topped
out at roughly half the node's total memory, with a brief, small dip into swap that
recovered cleanly afterward. Steady-state usage afterward left this node still *not*
the fleet's hungriest — that title still belongs to the one running a full browser
stack for its display. The generic sizing advice assumed a workload this node was
never going to carry; the real numbers confirm that assumption was the actual
mistake, not the plan.

## Two real snags, worth remembering

Neither snag was about capacity — both were rootless-container plumbing, and both are
exactly the kind of thing that looks like the obvious fix and isn't:

- Making a bind-mounted host folder appear as a specific non-root user *inside* a
  rootless container is not the same operation as remapping the container's entire
  user namespace to match the host user. The namespace-remap option looked like the
  right tool and instead broke the application's own internal startup sequence, which
  assumed its normal internal root mapping was intact. The actual fix touches only the
  one folder that needed it, leaving everything else alone.
- A background job runner, left running after its controlling terminal disconnects,
  is not covered by the same "don't sleep while someone's connected" rule that
  protects an active session on the spare compute node. It got suspended mid-job when
  that node went to sleep on its own schedule with nobody watching. The forge itself
  handled this gracefully — the job stayed queued and delivered the moment the runner
  reconnected — so this cost nothing, but it's a real gap in the wake/sleep logic
  worth closing before anything less patient depends on it.

## What this proved, and what it didn't decide

It proved the premise: the node has genuine room, comfortably, for a single-user forge
plus occasional CI runs handled elsewhere. It did not decide whether to keep this
particular deployment running — the whole point of building it disposable was to
separate "does this fit" from "build it properly," and those are different
conversations. The disposable version came down the same day it proved its point; a
real version, built to the fleet's normal standards (a proper shared database, real
internal TLS, a fully automated build runner instead of a hand-registered one), is a
decision for later, made with real numbers behind it instead of a guess.

## Addendum — 2026-08-30: the decision that was "for later" came two days later

The last paragraph above holds a decision open. It closed faster than expected: the
real version was built and is now running, on the same node the spike measured.

It was built to the standards that paragraph named, which is the useful part — the
spike's numbers were the argument for doing it properly rather than for keeping the
throwaway. The forge now uses the fleet's shared **Postgres data layer** instead of an
embedded database (the placement rule the fleet applies to any new service that would
otherwise bring its own), sits behind the gateway's internal TLS like everything else,
and has its build runner deployed by role rather than registered by hand. The complete
branch history was mirrored in from the existing origin and then **gate-verified** —
an exact branch-by-branch diff and a HEAD match against a fresh clone — rather than
trusted because the push reported success.

Four bugs surfaced that only a running instance could have produced, and none of them
would have failed a dry run: a play ordering that started the forge before the database
role it depends on existed; an install-lock flag that made the forge refuse every
administrative command against its own "uninstalled" instance; a container that cannot
bind a privileged port even when granted the capability, because the image's own
entrypoint drops privileges before the process starts — fixed by not needing the
capability at all rather than by fighting for it; and a service published on loopback
when the reverse proxy reaches it from a *different host*, which the comment justifying
the loopback binding had gotten wrong on its own terms.

The old bare-repository origin is still live and is deliberately kept as the rollback
path, not deleted. That is the honest state of it: the forge is the origin now, and
the thing it replaced is still sitting there in case it shouldn't be.
