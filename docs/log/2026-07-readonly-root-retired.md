# 2026-07 — Retiring read-only root (removing a guard that cost more than it saved)

**Goal:** take out a piece of infrastructure that was built with good intentions and turned into a
constant tax. The kiosk node ran a **read-only root filesystem** — the SD card mounted read-only, all
runtime writes going to a RAM overlay that's wiped every reboot — to spare a cheap flash card from
wear. This is the story of deciding it wasn't worth it and pulling it out cleanly.

## Why it looked like a good idea

The kiosk is a tiny, constrained node that just displays a dashboard. It writes almost nothing worth
keeping, and cheap SD cards die from write wear. Making the root read-only means the card is never
written, so it can't wear out or corrupt on a power cut. On paper: elegant, and it worked.

## Why it stopped being worth it

The problem is what a read-only root does to *every ordinary change*. Once the overlay is armed, any
config update you apply lands in RAM and **evaporates at the next reboot** — so making a change means
a whole dance: disarm the overlay, apply, reboot, change, re-arm, reboot. Forget the dance and your
change silently vanishes, and the system *reports success* while doing it. Over time it cost real
pain:

- Two separate config changes were quietly eaten by the overlay and had to be chased down later.
- It interacted badly with the node having no real-time clock, once wedging the machine in a reboot
  loop (a scheduled reboot firing on the clock jumping forward at boot).
- Routine dry-runs threw spurious errors because units couldn't be pre-created under the read-only
  filesystem.

So the guard was protecting against a failure — a worn-out card — that is **cheap and easy to
recover from**: the node is fully described in configuration, so a dead card is a ~20-minute reflash,
and there are spare cards in a drawer. Meanwhile the guard itself demanded a tax on every single
change. **When the thing you're protecting against is a cheap reflash and the protection is a daily
tax, you remove the protection.**

## The tempting mistake I didn't make

The obvious move after removing it is to add a *lighter* wear-reducer — put just the busiest write
directory on a RAM disk, say. I nearly recommended it. But I talked myself out of it, for two
reasons. First, **consistency**: I was removing this precisely because it was anticipatory machinery
guarding a cheap failure — bolting on new, lighter anticipatory machinery is the same instinct I'd
just decided against. Second, and more concrete: a RAM disk *spends RAM*, and this is the single most
memory-starved node in the fleet — the one place where memory is the actual binding constraint on
whether it runs well. Trading card-wear for memory pressure on *that* node is a bad trade. So the
replacement is: **nothing.** Reflash the card if it ever dies. That's the whole strategy, and it's
the right amount.

## Removing it without leaving a mess

One real gotcha in *deleting* an infrastructure role: the role has to **undo itself on the machine
before you delete it from the code**, or you strand the node in the exact state the role managed with
no code left to manage it. A read-only root with no tooling to un-read-only it is a trap. So it went
in two phases: first flip the switch that disarms the overlay and reboot (using the role while it
still exists), confirm the filesystem came back writable, *then* delete the role. Even then, one
artifact the role had installed — a nightly reboot job — outlived the deletion and needed a one-time
manual cleanup, because a deleted role can't tidy up after itself.

And the record got the **annotate, don't erase** treatment: the architecture docs now say read-only
root was *tried and retired*, with the reasoning — but the hard-won lesson from its worst bug (on a
clock-less machine, never schedule anything on a wall-clock time; it'll fire when the clock jumps at
boot) is **kept as a standing gotcha**, because that lesson outlives the feature that taught it.

## What I'd tell past me

- **Weigh a guard against the cost of the failure it prevents, not just the failure itself.** A
  cheap, easy recovery changes the whole calculation. Protecting a $10 card with a daily tax is
  upside-down.
- **Beware replacing removed complexity with lighter complexity of the same kind.** If you're
  deleting something because it was anticipatory overkill, adding a smaller anticipatory thing is
  often the same mistake wearing a smaller coat.
- **On a constrained node, spend the scarce resource, not the cheap one.** RAM was worth more than
  SD lifespan here; the "wear-saving" replacement would have taxed the wrong budget.
- **A role that changes machine state must be able to un-change it — remove the effect before you
  remove the code.** Otherwise you strand the very thing you were trying to clean up.
