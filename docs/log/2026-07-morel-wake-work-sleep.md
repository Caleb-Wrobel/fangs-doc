# The old man in the basement: a machine that sleeps until called

**2026-07-07** · infrastructure · resilience · onboarding

For its whole life the fleet was Raspberry Pis — five little ARM boards, all the same shape of
problem. Then a fifth node arrived that broke the mould: an aging amd64 desktop, a 2011-era
enthusiast build (a quad-core i7, 24 GB of RAM, a mid-range GPU someone dropped in years later, a
liquid cooler still humming). The fleet's **first non-Pi, non-ARM node** — and, as it happened,
already sitting in the basement, powered off, ahead of the fleet's eventual move down there.

## Onboarding as the runbook's first non-Pi customer

The onboarding runbook had only ever met Raspberry Pis. Walking a generic PC through it was a good
stress test of every hidden assumption — and it surfaced them the way only a real first customer
can. The installer's minimal image lacked a tool the Pi image always shipped, so a repository step
that had worked five times failed on the sixth; the fix belonged in the fleet baseline, where the
dependency was always latent. The machine had a resident Windows, so the installer quietly set the
hardware clock to local time (a dual-boot convention) — harmless anywhere else, but this fleet had
*just* built its whole time story on the hardware clock being UTC. Small papercuts, each one now a
line in a new "non-Pi deviations" section. The runbook came out better for having a stranger walk
through it.

## A name for a thing that comes and goes

The naming convention had drifted from wolves to a quieter theme: short nouns for emergent
phenomena — a threshold, a growth signal, the thing the light chases. The new machine wanted a name
in that key, and one fit almost too well: a **fungus that fruits briefly when conditions are right
and otherwise persists, unseen, underground.** The visible part is occasional; the organism is
always there. For a heavy box that would spend most of its life asleep on its own storage, waking
only when summoned — and that was *literally* already underground before the rest of the fleet — the
metaphor arrived after the fact and fit the object it named. (A runner-up got banked for a future
node whose defining trait is *not being present* — the fleet now pre-names its ghosts.)

## Summoned muscle: sleep, and a whisper to wake

The design principle: this node is **muscle you consciously recruit**, not part of the standing
nervous system. It holds no live state and runs no reflex duty. It sleeps — a true
suspend-to-RAM, near-zero draw, memory preserved — and the always-on AI node wakes it with a
**Wake-on-LAN magic packet**: a tiny broadcast frame the sleeping network card watches for even
while the rest of the machine is dark. Proven before a line of automation was written: suspend,
whisper, and it was answering again in about six seconds, same boot identity — a genuine resume, not
a reboot in disguise.

Two details turned the trick into durable capability. The wake flag on the network card is
*runtime-only* — it forgets across a reboot — so a small boot-time unit re-arms it every time.
And the monitoring had to be inverted.

## What I'd tell past me: a sleeping node looks exactly like a dead one

That last point is the real lesson. Every other node in the fleet earns a page when it stops
answering — silence means something broke. But a machine *designed* to be off most of the time
breaks that assumption completely: its silence is the plan working, not failing. Leave the normal
"node down" alert pointed at it and every nap pages you at 3 a.m.

So the node is **excused from the liveness alarm** while still being measured whenever it's awake.
The honest cost, named out loud: a *real* crash on that node won't page either — you've traded
away liveness monitoring for the right to let it sleep. The proper answer isn't "is it up?" but
"did the work it was summoned for actually get done?" — a dead-man's-switch on outcomes, not a
pulse. That's the harder half, deliberately deferred with the orchestration that will eventually
let the fleet wake this muscle, work it, and put it back to sleep on its own. For now, the summons
is by hand, and the old man rests undisturbed between them.

- **Not everything that goes quiet is broken.** Absence of signal has to be *interpreted*, not
  assumed to mean failure — the same lesson the fleet's chaos exercises teach from the other side.
- **A first non-native customer is a gift to a runbook.** Every assumption a familiar case lets you
  skip, a stranger trips over — and each trip is a line worth writing down.
- **Name the trade you make.** Excusing a node from its alarm buys you a quiet nap and costs you a
  crash notification. Both are true; write both down.
