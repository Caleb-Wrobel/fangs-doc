# A phone call to a sleeping PC

**2026-10-08** · infrastructure · power

The fleet has one big, hungry machine that sleeps most of the day and is woken on
demand. Waking it meant a laptop, a terminal, and remembering the incantation. This is
the write-up of putting a Discord slash command in front of it — wake it, keep it
awake for a while, let it go, put it back to sleep, tell me what it's doing — from a
phone, without opening a single new port at home.

## The shape of the solution

A small bot lives on a free-tier cloud box that is *outside* the home network. It dials
**out** to Discord and listens on nothing. From there a chain of three narrow hops
reaches the machine: the bot can only ask the gateway one fixed question; the gateway
can only relay a short, closed list of verbs; and each last hop is a key that can run
exactly one command and nothing else. Three credentials, three one-way doors. A
timed "hold" is a systemd unit on the sleeping machine itself, so it expires on its own
even if the bot, the gateway, or the whole home network is gone.

## Surprise 1: the gate that ran after the door

The bot has a self-test: build the whole command tree without connecting, and fail the
deploy if that breaks. The task even carried a comment saying it ran *before* the
service started. It didn't. A "flush handlers" step sat just above it, and the restart
handler fired there, so a broken build was already live — and crash-looping — before
the check ever ran. A comment is not an ordering guarantee. A review pass found it;
nothing in normal use would have, because the happy path never fails.

## Surprise 2: the command that said yes and meant no

"Put it to sleep now, regardless of what's running" sounded like the simplest verb.
It replied *suspending*, and the machine stayed awake. The suspend was scheduled a few
seconds out, detached, so the reply had already gone before the operating system
refused it: forcing a suspend past another program's sleep lock is denied, even for
root, unless a policy service is installed — and on this box none is. The common case
(the bot's own hold) always worked, which is exactly why it took a deliberate second
lock to see it. The fix was to stop promising what couldn't be delivered: the verb now
looks first, and if something else holds a sleep lock it refuses, names the lock, and
changes nothing. A claim like "regardless" was never going to survive contact with the
platform.

## Surprise 3: some questions have no valid test

One planned check asked whether the countdown stays accurate when a hold survives a
sleep cycle. It cannot be run: a hold *is* a sleep lock, so nothing can suspend the
machine while one exists. The only way through was a raw kernel write that skips the
driver's sleep hooks and risks a machine I can only wake with a network packet. The
right outcome was to mark it not applicable, with the reason, instead of manufacturing
a risky test to fill a cell.

## Smaller sharp edges

- Locking an account does not revoke its SSH key when PAM is in play — remove the key.
- "Only when every host is in this run" guards need the list of hosts that are still
  *alive*, not the list that were *planned*; otherwise a sleeping machine turns a
  graceful skip into an error.
- A validation sweep that quietly skips rows reads as a pass. The scorecard here marks
  what was never run as **not run**, and the entry is landed with that list attached.
- A check that proves nothing looks the same as one that passes: one secret-leak test
  passed on an empty token variable, until the match count was suspiciously equal to
  the number of lines.

## What I'd tell past me

- Prove the refusal path as carefully as the happy path, with a deliberate blocker.
- If a reply is sent before the action runs, the reply can only say "scheduled."
- Put the gate before the thing it gates, and don't trust a comment to say so.
- Decide what a verb *promises* before building it; delete the promise that the
  platform won't keep.
