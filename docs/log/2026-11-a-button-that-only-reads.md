# A button that only reads

**2026-11-21** · gitops · security

The fleet is managed from one workstation. Whether the live machines still
match the repo was only known when someone ran a dry run from there and read
it. This entry adds a second place to ask: a **Run** button in the self-hosted
forge, wired to the small always-on ops node. Press it and that node runs the
whole playbook in check mode against `main`, as the fleet's automation account,
while you watch the job log. It never applies anything and never prints a diff.

That sounds small. The hard part is that a dry run still needs root on every
machine it checks. So the moment this works, the ops node holds the keys to the
fleet, and the question becomes who gets to tell it what to run.

## The shape of the solution

The CI runner on the ops node holds no keys. It may run exactly one command as
the automation account, through `sudo`, and that command is a small root-owned
helper. The helper takes at most one argument, a single inventory host name,
and refuses anything else. It fetches `main` into its own checkout, prints who
it is running as, which commit, and which hosts it will never touch. Then it
runs the playbook with flags and an environment it builds itself. Nothing comes
from the caller's environment, and nothing comes from the job's workspace.

The design rests on one fact: **a branch can rewrite its own workflow file.**
So the workflow is not the control; the helper is. I tested that directly. A
throwaway branch tried fourteen ways to steer the runner: reading the account's
files, `sudo` to anything else, passing environment through `sudo`, smuggling
flags into the host argument, naming a group or `localhost`, asking for a diff,
and planting Python modules and poisoned Ansible variables in the workspace.
All fourteen were refused. Then the branch dispatched its own edited copy of
the workflow. It ran, and the helper checked `main` anyway. Pushing a branch
gets you a check of `main`. Only merging changes what the button checks.

Revocation is one line. The automation key is listed once in the fleet's
inventory, and an apply removes it everywhere. I rehearsed it on one node: line
out, apply, and the next run was refused at the door. The vault password is a
separate brake; moving it aside turned the next run red in three seconds,
before it reached any host.

A full run takes about 33 minutes and barely touches the ops node: a couple of
hundred megabytes of memory, no swap, nowhere near warm.

## Surprise 1: one sleeping machine stopped the whole run

The first full run from the button died in under two minutes, having checked
nothing.

The cause was mine. One machine was asleep on the day its half of the key
change was applied. I skipped it and never went back. So the button's account
couldn't log in there. What made it confusing was the error. After a few
refused logins, that machine's SSH server started dropping connections from the
ops node before the handshake. The log said "connection reset", which reads
like the network, not a missing key.

The second lesson was bigger. That machine sleeps by design, so the playbook
opens with a play that wakes it. That play has only that one machine in it.
When it failed, every host in the play had failed, and Ansible's rule is that a
play whose every host fails ends the whole playbook. The comment above the play
said a node that won't wake "drops out". It didn't drop out. It took the fleet
with it, and that was true of every run from the workstation too.

The fix is to end that host instead of failing it. The node then shows up as
unreachable at its next play and is skipped for the rest of the run, while
everyone else carries on. I proved that against a fake host that could never
answer before touching the real playbook.

## Surprise 2: the cancel killed the messenger

Cancelling a run turned the job grey in the forge, and the check kept running.

The runner can only signal processes that run as its own user. It killed
`sudo`, which it is allowed to signal. The helper underneath runs as the
automation account, so it never got the signal. It was quietly reparented to
init and would have carried on until the run ended, about half an hour. It
held the lock that keeps two checks from overlapping, and it held the sleeping
machine awake. Any press of the button in that time would have been refused
with "another check is running".

The helper already had a careful cancel handler. It just could never be
called. The fix stops waiting to be told: every five seconds the helper checks
whether its parent is still the process that started it, and if not, it shuts
the run down itself. A cancelled run now leaves nothing behind within seconds.
It happened twice before the fix, which at least settled the cause.

## Surprise 3: green over a planted drift

To prove the button catches drift, I added one comment line to a config file on
a live node and pressed Run. The log showed it plainly: the task that owns that
file came back "changed", and its restart handler would have fired. No diff
body, and nothing on the node was touched. The job went **green**.

That is correct. A check-mode run exits zero when it ran cleanly; "changed"
means "an apply would do something", and that isn't an error. So the green tick
answered "did the check run?", not "is the fleet as declared?". To get the real
answer you have to read the log.

Turning every change red doesn't work either. The fleet is never at zero: every
run shows pending package upgrades and a handful of long-standing items that
always report changed in check mode. A permanently red job tells you nothing,
and you learn to ignore it.

So that moved to the next rung, the nightly unattended check, as its first
item. It gets a per-host drift summary, a short known-drift list where every
entry has a reason, and a red job only for a change that isn't on the list.
Nobody reads a half-hour log at 3 a.m.; it has to say so.

## What I'd tell past me

- **When a branch can rewrite its own workflow, the workflow is not the
  boundary.** Put the decision in something the branch can't edit, and test it
  by letting a branch try.
- **"Skip that node, it's asleep" is a debt.** Write down what you skipped while
  you're skipping it, or the next run collects it.
- **Read the rule behind the comment.** "A node that won't wake drops out" was
  true in a play with other hosts and false in a play of one.
- **A signal you can't receive is a handler that never runs.** Across a user
  boundary, don't wait to be told; check for yourself.
- **Green is an answer to a question; know which one.** "It ran" and "nothing
  drifted" need different signals, and the second has to know what normal looks
  like.
- **Rehearse the revocation before you need it.** One line and one apply turned
  out to be true. Until I'd done it, I only believed it.
