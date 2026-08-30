# The couch learns to read

**2026-08-28** · observability · kiosk

The living-room kiosk board was built for a glance-from-across-the-room audience —
weather and internet up/down, nothing else — and this round of work is what it takes
to make "at a glance" actually true: real information density, a cursor that
disappears instead of hovering forever, and a color language that means something at
a distance. None of it is a single feature; it's a week of small, real fights with a
dashboarding tool that was never designed for this audience.

## The sanitizer teaches a lesson the hard way

The board's weather panel is built from an HTML text panel, not native chart widgets —
more layout control, in theory. In practice, the dashboard engine runs every panel's
HTML through a sanitizer before it ever reaches the screen, and the sanitizer strips
CSS properties selectively: shorthand goes, longhand survives. A `table-layout: fixed`
vanishes silently; an explicit `width: 25%` on each cell does not. A `flex: 1`
vanishes; `display: flex` plus that same explicit width does not. The result, before
this was understood, was a genuinely misaligned grid with no error anywhere to explain
it — the sanitizer doesn't warn, it just quietly returns different HTML than what was
sent. The fix, once found, held everywhere it was applied: never trust a CSS shorthand
to survive this panel type, always write the longhand.

## A color that means something, not just a color

The live up/down cell used to be a flat green-or-red. It now carries a third state,
because "up" isn't actually one situation: up-and-clean, up-but-flaky, and down are
three different things to a glance-from-the-couch audience, and only two colors can't
say all three. The fix folds a recent-outage count into the same cell as the up/down
status, and lets the *text color* — not the background — carry the third state: white
on green when nothing's happened recently, red text on the same green background when
the connection's been flapping, black when it's actually down. Getting there needed a
real definition of "an outage worth mentioning," too — a one-second blip that resolves
before a human would ever notice it was never the thing worth counting, so the metric
underneath now requires a sustained gap, not just one bad poll, before it counts as an
outage at all.

## The cat earns its keep

A small pixel-art cat clock sits in the corner — a cosmetic concession in an otherwise
information-dense board, kept specifically because it's legible at range in a way
numbers alone aren't. Getting it to read well at this size took more than scaling up:
the source frames all carried inconsistent transparent padding, so simply enlarging
them enlarged the empty space around the cat as much as the cat itself. Cropping every
frame to a shared bounding box first, then scaling, fixed it — the kind of fix that's
invisible until you compare the before and after side by side.

## What didn't ship

Not everything explored this round made it in. A full-width banner across the row's
open headroom — floated as a way to surface something urgent without displacing the
existing layout — got as far as a real mockup before the actual pixel budget said no:
measuring the true margins around the existing numbers showed almost none of the
headroom assumed to be free was actually free without covering real digits. It's
recorded as a known, deliberately-not-chased idea rather than something quietly
dropped — the board has genuine unused pixels in that row, and revisiting them with a
better plan is still on the table, just not this round.

## The invisible parts

A kiosk cursor that never moves again after boot sounds trivial and wasn't. The fix
that actually held is an active wait, over the browser's own remote-debugging
protocol, for the page's real content to finish rendering before parking the pointer
dead center — replacing an earlier fixed-delay guess that worked until it didn't.
Small, unglamorous, and exactly the kind of fix that only a non-technical audience
staring at a stray cursor for the wrong reason will ever notice is missing.
