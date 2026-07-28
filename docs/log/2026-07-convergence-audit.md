# 2026-07 — Three bugs behind a green run

**Goal:** run the *entire* configuration playbook against the *entire* fleet, in one
go. The staged workflow here almost always applies narrow tagged slices to one or two
nodes, which is fast and safe and means the whole thing rarely executes end to end.
This was meant to be a tidy-up. It found three bugs, two of which had been live for an
unknown length of time while every runtime signal said everything was fine.

## Shape of it

The first run died in the first play and never reached the other nodes. Fixing that
let the second run converge all six hosts cleanly. Then the **dry run afterwards** —
the one that's supposed to be a formality — found the other two.

That ordering is the whole story. The convergence run found the blocker. The
*verification* found the bugs.

## Bug 1: the upgrade that failed loudly and broke quietly

The run stopped on the gateway during routine package upgrades. The dashboard server's
new version wouldn't configure: its post-install step moves a bundled-plugins directory
into the service's data directory, unconditionally, and that move failed.

Two things had to line up. The data directory here is a **bind-mount onto a separate
disk** (part of an earlier durability push to get state off the SD card), so it's an
inter-device move rather than a rename. And the destination already existed, populated
by the *previous* install. The upstream script assumes it won't.

The package manager left the package half-configured. Here's the part worth writing
down: **nothing looked wrong.** The already-running process kept serving on the old
binary. The health endpoint returned 200. The reverse proxy in front of it returned
200. No alert fired, because from every angle the service was up — and it genuinely
was.

The only symptom was a failed automation run. And because package upgrades happen in
the *first* play, against the gateway, one wedged package meant **the entire fleet
stopped converging.** A silent data-plane success masking a total control-plane
failure.

The repair was a rename and a re-configure, about thirty seconds once understood. It
will recur on every upgrade of that package, which is now written down rather than
automated around — a half-minute manual fix on an occasional event doesn't justify
standing machinery. (That's the same reasoning that
[retired the read-only root](2026-07-readonly-root-retired.md).)

## Bug 2: the guard that hid a broken door

With the fleet converging again, one node still failed a role that escalates privileges
to a locked-down service account — the one that owns the fleet's git origin. The error
was a sudo password prompt, from automation that has never had a password to give.

The cause was one missing word. The baseline grants the admin account passwordless
`sudo`, and the rule was generated **without an explicit run-as clause**. Omitted, the
parser reads that as *root only*. Escalating to any other user therefore demanded a
password, and always had.

Why nobody noticed: the failing task creates a repository *if it doesn't already
exist*, and it did already exist. The guard short-circuited the work every time, so the
task never *did* anything — which meant nobody noticed it also never *could*. It
would have surfaced on the day someone re-imaged that node and found the fleet's
authoritative git origin quietly absent.

Adding the run-as clause grants no new privilege whatsoever: the same rule already
makes that account passwordless root, and root can become anyone. It only stops sudo
refusing the short path.

## Bug 3: two tasks undoing each other, every single run

The post-apply dry run is held to a hard bar here: **a converged fleet reports zero
changes.** Anything else is either drift or a bug. It came back with one node reporting
a change it had presumably been reporting forever.

The GPU node installs its graphics driver from the vendor's own repository rather than
the distribution's, because the distribution's is too old for the card. The role
sensibly purges the distribution's packages first, to clear the way.

The problem: **the vendor ships packages with the same names**, and those same names
are what the vendor's own driver metapackage *depends on*. So once the intended driver
was installed, the purge task and the install task were undoing each other on every
run — purge rips the driver stack out, the next task puts it straight back.

The receipts, from package history and kernel module timestamps during the run: about
**150 packages** removed and reinstalled (the whole driver userland, plus the desktop
graphics stack the driver package drags onto a headless machine), and the kernel module
**rebuilt from source for every installed kernel**. Roughly four minutes of teardown
and rebuild per run — plus a window in which a live GPU host has no driver at all, on
the node that runs batch embedding jobs, and whose one-time driver build race had
already bitten once before.

The fix is a guard: skip the purge when the intended driver is already installed. That
preserves the task's actual purpose — if the distribution's packages or a wrong driver
branch are what's present, the intended one *isn't*, the guard opens, and the purge
still clears the way exactly as designed. It only stands aside once the thing it was
clearing the way *for* has arrived.

Proven by the thing that should be true and wasn't: after the fix, a real apply reports
zero changes and the compiled kernel module's timestamps **don't move**.

## What I'd tell past me

- **Run the whole thing occasionally, just to read the summary.** A workflow built on
  narrow, fast, targeted slices is good for shipping and blind by construction. Two of
  these three had been live for an unknown span precisely because nothing ever executed
  the full set and looked at the result.
- **A perpetually-changed task is not cosmetic.** It's easy to read one stubborn line
  as harmless drift and mentally filter it out. Here it was two tasks actively fighting,
  burning minutes and rebuilding kernel modules every run. Hold the zero-changes bar and
  actually mean it — it is the single highest-yield check in this whole setup.
- **"The service is up" and "the system is correct" are different questions.** The
  wedged upgrade answered the first one perfectly while failing the second completely.
  Health checks watch the data plane; nothing was watching whether the control plane
  could still *converge*.
- **A conditional guard can hide a broken mechanism indefinitely.** If a task never has
  to do its work, you will never learn that it couldn't have. Worth a suspicious look
  at any task that's been skipping happily since the day it was written.
