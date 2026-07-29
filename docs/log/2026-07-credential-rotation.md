# 2026-07 — The rotation that rotated nothing

**Goal:** six live credentials in this fleet were the literal placeholder string
from the example secrets file. Not weak — *placeholder*. Replace all six with real
random values.

This was meant to be an afternoon of typing. It turned into the requirements
document for a piece of infrastructure I hadn't built yet, because **not one of the
six rotated the way the configuration management implied it would.**

## Shape of it

Six credentials: the file-share password, the dashboard admin password, and four
database role passwords including the superuser. All of them live in an encrypted
vault, referenced by the automation, applied to the fleet by the same tooling that
applies everything else.

The mental model going in: edit the vault, run the playbook, done. That model is
wrong in a specific and unusually quiet way.

The order that actually worked: change each credential **live on the running
service first**, *then* run the automation to update everything that consumes it,
then verify each consumer separately.

## Surprise 1: editing the vault rotates nothing

Every one of the six was a no-op if you only changed the stored value — and every
one of them failed silently, behind a run that reported success.

The reasons differ, and the variety is the point:

- **The database roles** are created by a guarded statement — *create this role if
  it doesn't already exist*. It does already exist. The guard short-circuits, the
  new password is never applied, the run is green.
- **The database superuser** is set from an environment variable the container image
  reads exactly once, when the data directory is first initialized. Forever after,
  that variable is decoration. Changing it changes nothing.
- **The file share** is guarded by an explicit "is this user already registered?"
  check, precisely so the password-setting command is idempotent. The cost of that
  idempotency is that the command can never run a second time.

None of this is a bug. Every one of those guards is *correct* — they exist so that
re-running the automation is safe. But they add up to a system where the declarative
layer can express "this credential should exist" and cannot express "this credential
should now be different."

Two of these were even documented. A comment in one of the schema templates says, in
so many words, that rotating this value requires a manual database command
afterwards. The knowledge was written down years of commits ago. The credential
still never got rotated. **Writing down a manual step is not the same as it
happening** — that's most of the argument for building the rotation engine at all.

## Surprise 2: the one that lied

The dashboard server was the one I flagged as *unproven* in the plan, because I
suspected but hadn't confirmed that it only reads its admin password from config on
first startup.

Here's what happened when the automation ran. The config file was rewritten with the
new password. The restart handler fired. The service came back healthy. The run
reported the task as changed. Every signal available said the rotation had worked.

Then I tried to log in:

```
new password -> HTTP 401
old password -> HTTP 200
```

The config file on disk claimed one password. The service accepted a different one.
And **nothing in a converged, green, idempotent run could tell those two states
apart.**

Fixing it took a purpose-built command-line tool that writes directly to the
service's own database — a completely different mechanism from the one the
automation was using. Afterwards the results flipped, which is how I know the fix
was real and not another confident no-op.

If I had done this rotation the "obvious" way — edit vault, run playbook, move on —
the fleet would now be carrying a config file that documents one password and a
login that accepts another. Indefinitely. There is no alert for that, because from
every monitored angle the service is perfectly healthy. It *is* perfectly healthy.
It's just not the thing I think it is.

## The consequence for what gets built next

I'd already sketched a rotation engine: generate, apply, record what was rotated and
when, so credential age becomes a number you can alert on. The sketch assumed the
record could be written when the automation reported success.

That assumption is now dead. The dashboard rotation *reported success*. Whatever
records rotations has to record ones that were **verified afterwards by actually
using the credential** — a login, a connection, an authenticated request — not ones
that a converged run believes it performed.

Which generalizes past credentials, and is the thing I'll carry: **an idempotent run
reporting "changed" is evidence that a file changed. It is not evidence that the
world changed.** Those are the same thing often enough to be a comfortable habit, and
this is what it looks like when they come apart.

## Ordering, and the window

Consumer configuration files are generated *from* the vault. So running the
automation before making the live change hands every consumer a password the server
doesn't accept yet — you break things in the exact order guaranteed to look like the
rotation failed.

Live change first, automation immediately after, then verify. There is a window,
between those two steps, where consumers are genuinely broken. It's unavoidable
without a great deal more machinery, and the honest mitigation is to make it short
and do the steps back to back rather than pretend it isn't there. Mine was under two
minutes.

One detail worth stealing: verify by **fingerprint**, not by eyeball. Comparing a
hash of the stored value against a hash of what each consumer's config actually
contains proves they agree without ever printing a secret to a terminal, a log, or a
transcript. It also caught me looking at the wrong host — an empty result hashes to
a well-known constant rather than erroring, so a missing file looks like *a value
that doesn't match* instead of like success.

## What I'd tell past me

- **A placeholder is a credential.** These six weren't chosen badly; they were never
  chosen at all. They came from an example file and were never replaced, and every
  run since has faithfully re-applied them. Nothing degrades, so nothing prompts you.
- **Idempotence guards make rotation impossible, by design.** "Create if absent" and
  "set only on first init" are the correct way to make automation safe to re-run, and
  they are exactly why re-running it cannot change a password. Expect to need a
  second, imperative mechanism for every secret — and expect it to be *different* for
  each one.
- **Verify the credential, not the run.** Log in with the new value. Then log in with
  the *old* one and require it to fail. The second half is the one people skip, and
  it's the half that catches a rotation that silently didn't happen.
- **Do the manual pass before building the machine.** Every genuinely useful
  requirement here — which command per credential, which order, which restarts, which
  config files move together — came from doing it once by hand. Designing the engine
  first would have produced something that automated a model of the system rather
  than the system.
- **Write-it-down is not a control.** A comment saying "this needs a manual step
  afterwards" sat in the codebase, was correct, was never acted on, and the
  credential stayed a placeholder. If a step matters, it needs something that
  notices when it hasn't happened.
