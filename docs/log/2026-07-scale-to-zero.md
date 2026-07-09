# The sleeper learns to tuck itself in (and to say goodnight)

**2026-07-09** · infrastructure · observability · resilience

The basement machine already knew how to be *summoned*: a sleeping amd64 box, a Wake-on-LAN whisper
from the always-on AI node, a chat request that arrives to a GPU whose model never left VRAM. What
it couldn't do was go back to sleep on its own — every nap was a human typing a suspend command.
Tonight closed the loop, and then taught the fleet to tell a nap from a corpse. Almost nothing went
in on the first try, and every failure was the interesting kind.

## A benchmark that simplified the design

The load-bearing measurement: the model **stays hot in VRAM across suspend-to-RAM**. A wrongly
timed sleep therefore costs only the ~dozens-of-seconds wake — no model reload, no real harm. That
one fact collapsed the design space. No GPU-utilization sampling, no query-rate heuristics: a timer
checks once a minute whether anything is *connected* — an in-flight generation holds its socket
open for the whole streamed response, and an SSH session means a human or the config tool is at
work. Ten quiet minutes and the machine lays itself down. Metrics scrapes deliberately don't count,
which also means telemetry runs right up to the moment the lights go out.

Two subtleties earned their comments. Time spent asleep must not count as idle — otherwise the
first timer tick after a wake would immediately re-suspend the machine, before the request that
summoned it even arrives — so a resume hook re-zeroes the idle clock on every wake. And the check
rides a monotonic timer, never wall-clock: an old fleet lesson about clocks that step forward
after boot, kept warm even on a node that has a real hardware clock.

## The proof that failed because the ruler was broken

The validation harness watched the machine from the workstation, over the new road-warrior VPN
tunnel, by ping. It reported a beautiful pass — self-suspend right on schedule — then a damning
failure: the machine "re-suspended instantly" after waking. Except its journal showed it awake the
whole time, check timer ticking calmly, no suspend anywhere.

The pings were lying. Chasing *why* they lied uncovered a real, older bug: the VPN feature's
firewall rules only ever admitted tunnel traffic **terminating on the gateway itself** — the DNS
resolver, the reverse proxy, SSH — which is exactly and only what its original verification had
tested. Traffic *forwarded through* the gateway to any other node had been silently dropped since
the feature landed. The road reached the gate; every hall behind it was closed. One forward-chain
rule fixed it. The lesson got written in bold: **verifying a gateway feature means testing a
forwarded path, not just gateway-terminated ones** — the ways a proof can pass are not the ways a
feature can work.

## The ghost holding the door

Proof two, now measured from inside the LAN, failed differently: the machine refused to sleep at
all. The idle check vetoes sleep on any established SSH connection — and there sat a connection
over an hour old, its client process long dead, no FIN ever sent. A half-open TCP corpse, left by
an earlier interrupted script, would have pinned the machine awake *forever*: the veto trusted the
kernel's word "established," and nothing on the server ever probed whether the peer still breathed.
Server-side SSH keepalives (a minute between probes, three strikes) now reap dead sessions well
inside the idle window. The latch no longer believes a hand that isn't there.

## Ready is a lease, not a fact

Proof three: the machine slept on cue — and the summon returned a bad-gateway error. The
wake-on-demand shim keeps a tiny state machine (asleep → waking → ready), and once it reached
*ready* it believed it forever. Reasonable, back when sleep was a deliberate human act. The moment
autosleep landed, "ready" became a claim with a shelf life: the machine can vanish ten idle minutes
after its last request, and a stale *ready* skipped the wake gate entirely and proxied straight
into the void — every subsequent chat failing until someone restarted the container. Now *ready* is
a **lease**: it expires after thirty seconds unless refreshed, and every proxied request refreshes
it. Active conversations never pay a re-check; the first request after a lapse re-verifies in
milliseconds if the machine is truly awake, or triggers the wake if it isn't. A state machine that
models a self-willed peer has to treat its beliefs as perishable.

## Three truths: up, dreaming, or gone

With the machine napping on its own schedule, the fleet dashboard had a new lie to tell: a healthy
nap and a dead node both read as red DOWN. From outside they are the *same silence* — no ping, no
scrape. The trick is that sleep is always **voluntary**: the node can declare it on the way down.
Death never announces itself. So a tiny persistent register (a Prometheus pushgateway on the
observability host, persisted across its own reboots) now holds one number per summoned node:
*asleep, by my own choice*. The suspend hook sets it; resume and cold boot clear it. The dashboard
derives three states — **UP** green, **ZZZ** blue, **DOWN** red — and the alerting gap that was
consciously accepted when the machine first learned to sleep ("a real crash won't page") is closed:
a new rule pages precisely on *undeclared* silence. The wake shim reads the same register on a
failed summon, so its error now says *which* failure you're debugging: "declared sleep but didn't
wake" (suspect the wake path) versus "never said goodnight" (suspect a crash).

An MQTT last-will design — where a broker auto-announces ungraceful disconnects — was seriously
considered and banked: the register gets the same answer by defaulting (intent is only ever set
deliberately), without adding a broker to the power-state system's list of things that must be
alive. The pub/sub itch keeps its place in line.

Even the fixes needed fixing: the first resume-side clear fired six seconds after wake, before the
network card was routable, and the HTTP client's built-in retry flag treats "no route to host" as
permanent. A hand-rolled retry loop — patience, not a clever flag — carried the message through.

## What this taught

- **A proof is only as good as its ruler.** The most valuable failure of the night was a
  measurement artifact — because explaining it exposed a real bug older than the thing being
  tested.
- **State about a self-willed peer must expire.** Any cached "it's fine" about a machine that can
  leave on its own schedule is a lease, and something must refresh it.
- **Established is not alive.** A kernel will happily report a connection whose other end died an
  hour ago; anything that gates behavior on connectivity needs keepalives.
- **Record intent where the intender can't take it with them.** A node's last words have to live
  off-node, or they die with it — that's the entire design, and it fits in one metric.
