# 2026-07 — The claim the code never made

**Goal:** work out what automated credential rotation would actually look like here,
using free and self-hostable tooling. The answer turned out to start somewhere else
entirely: the single biggest exposure in the fleet needed no rotation machinery at
all, just deleting a credential nobody was using.

## The question, and the better question

The prompt was reasonable — several credentials in the fleet had never been rotated
since the day they were set, and there was no mechanism, manual or automatic, to
rotate them. What's the open-source path to fixing that?

Surveying the landscape produced a ranking, but also a reframing. **Rotation is the
fallback, not the goal.** A credential you have to *remember* to rotate goes stale
eventually, because the remembering is the part that fails. In preference order:

1. **Eliminate it** — take the credential out of the authentication path entirely.
2. **Make it short-lived** — something that expires unattended needs no discipline.
3. **Rotate it on a schedule** — for statics that can be neither of the above.
4. **Track it and nag** — for the ones nothing can rotate.

That fourth category deserves naming, because every "manage your secrets" tool
quietly ignores it. Roughly a third of this fleet's credentials are **third-party
bearer tokens with no rotation API** — chat webhooks, search and inference API keys,
a VPN account token, a couple of capability URLs. A secrets manager can *store* those.
Nothing can rotate them without a human logging into somebody else's web dashboard.
Any tool claiming to "rotate your secrets" is overselling unless it says so out loud.

The heavyweight option — a real secrets daemon issuing database credentials that
expire on their own — is genuinely the *correct* answer to a problem this fleet has a
very small version of. It got ranked last and marked optional, for two honest reasons.
For a dozen-odd passwords on a single database host it's a bank vault holding a spare
key. And its unseal key is a secret on disk that protects all the other secrets, which
is *precisely* what the existing encrypted-vault passphrase already is. That's the
bootstrap problem relocated, not solved. Any design here that claims otherwise has
misunderstood it.

## The thing that was actually wrong

Working through the survey, a check on the current state produced the finding that
became the whole feature.

The baseline role every node runs grants the admin account passwordless `sudo`. That's
deliberate — this is a trusted LAN and the account exists to operate the fleet. The
justification written in the code included the phrase *"reaches every node over
key-only SSH."*

Nothing in the repo had ever enforced that. Asking each node directly what it was
configured to accept came back the same on all five: **password authentication
enabled.** The one place in the whole tree that disabled it was the off-fleet cloud
node, which has a different threat model and its own hardening.

So the fleet had a reusable login password that was identical everywhere, had never
been rotated, was known to me as a default, and was a second independent path to an
account that is root in all but name. The comment describing the security posture had
been true as an *intention* for months and false as a *fact* the entire time.

Key authentication already worked on every node — verified before touching anything.
So the password bought exactly nothing operationally. It was pure standing exposure.

## Shape of the solution

A drop-in config file on every fleet node turning off password authentication,
keyboard-interactive authentication, and direct root login. Then the shared default
password replaced with a long random one held in the vault, scoped to a single
purpose: logging in at a physical console.

## Surprise 1: the filename's number is load-bearing

SSH's daemon reads its drop-in directory in lexical order and, for most settings, the
**first** value it sees wins. Not the last. So a hardening file that sorts *after* the
drop-ins already on disk would be silently overruled by them.

The off-fleet node's equivalent file uses a high number — correct there, because the
cloud image's own drop-in sets the same value anyway. Copying that number onto the
fleet would have produced a file that looked right, read right in review, and did
nothing the day something else landed ahead of it. The fleet's version sorts first
deliberately, and the reason is written above it in the file.

## Surprise 2: turning off passwords doesn't turn off passwords

`PasswordAuthentication no` on its own is not sufficient. There's a second mechanism —
keyboard-interactive authentication — which, left at its default and backed by PAM,
happily prompts for the same password through a different door. Disable one and not
the other and you've written a comment, not a control.

It happened to already be off in the shipped config here, which is exactly the kind of
accident that turns into a regression later. It's now asserted explicitly.

## Surprise 3: don't lock the account, randomize it

The tidy instinct is to lock the login entirely. That would have been a mistake.

With password authentication off, the account password is no longer a network
credential at all — it only works at a **physical console**. And a physical console is
the one recovery path left when a node is unreachable over the network. The display
node in this fleet is already documented as needing hands-on visits it cannot
self-heal from: if its access point blips, it never re-associates on its own, and
someone has to go and fix it with a keyboard.

Locking the account would have made that visit useless. So the password is randomized
and stored, not removed. It stops being a *shared default* without ceasing to be a
*way back in*.

One small mechanical note that matters for repeatability: the password hash is salted
from the hostname rather than randomly. A random salt produces a different hash every
run, which reports as a change every run, which destroys the "a converged fleet shows
zero changes" bar that catches real drift.

## The interlocks, because this is the class of change that strands you

Three, all of them cheap:

- **Refuse to proceed without a key.** Before the hardening file is written, the run
  asserts the admin account actually has an authorized key installed, and fails loudly
  if not. In practice the automation couldn't have connected without one — but
  onboarding a fresh node interactively could bypass that, and this is not a mistake
  you want to discover afterwards.
- **Validate the whole config as an ordinary step.** The daemon can check its own
  configuration, drop-ins included. Running that as a normal task means a malformed
  file fails the run *at that point* — before the reload that would apply it — so the
  daemon keeps its old, working config and the connection being used to make the
  change stays alive. Recoverable by construction.
- **Reload, don't restart.** The daemon re-reads its config on a signal while
  established sessions stay up. A restart would probably be fine; a reload *cannot*
  drop the session applying the change.

## The check that couldn't be run

The acceptance list had one item that cannot be satisfied remotely: proving the new
console password actually works. You cannot test a physical-console credential over
the network. It needs a keyboard.

It's recorded as deferred rather than quietly upgraded to a pass. That's the honest
state, and it's the kind of thing that's tempting to fudge at the end of a run where
everything else went green.

## The cost

Onboarding gained a one-way window. New nodes are flashed with a password and get
their key planted immediately afterward; now the first baseline run *closes that door
behind it*. Miss the key-planting step and the flash password stops working over the
network the moment the baseline applies. The refuse-without-a-key interlock turns that
from "stranded node" into "failed run," but the runbook says so explicitly now,
because the alternative is finding out with a monitor and a keyboard.

## What I'd tell past me

- **A documented assumption is not an enforced one.** The comment claiming key-only
  access was written in good faith and was wrong for months. Grep for the
  *enforcement*, never for the claim — and if you find yourself writing a security
  justification that depends on something being true, go check that it is.
- **The cheapest security win usually deletes something.** A whole survey of secrets
  managers, and the thing worth doing first cost one config file and removed a
  credential rather than managing it better.
- **Name the credentials your tooling can't help with.** The un-rotatable third of
  this vault would have sat behind whatever got built, quietly not being rotated,
  while a dashboard somewhere claimed everything was under control.
- **The bootstrap problem doesn't dissolve, it moves.** Every design here ends with
  one secret at rest protecting the others. Pick where it lives deliberately; don't
  believe a tool that implies it made the problem go away.
