# The room with two guards and no captain

**2026-07-24** · infrastructure · resilience

Every alarm the fleet had could only ring from *inside* the fleet. The gateway pages when a node
goes quiet, the drives page when they fall dark — but if the gateway itself dies, the whole nervous
system dies with it, and the house burns in silence. That was the one real gap, and it had already
cost me: a whole-house power cut earlier in the summer took every reporter down at once, and nothing
paged, because every reporter was inside the blast radius.

So the fleet grew a single organ that lives *outside* itself — a tiny free-tier cloud box, off in
someone else's datacenter, whose only job is to notice when home goes dark. Earlier chapters stood it
up, gave it a real service to run, and put a proper TLS front door on it. This chapter is the one
where it finally became *load-bearing* — and where I learned, the hard way, that a thing which looks
like Kubernetes is not Kubernetes.

## The pieces were built but nothing was armed

By the start of the night the off-fleet box was serving a real watcher behind a real certificate —
and *nothing was pinging it*. It sat there watching a subject that never checked in, its little state
file forever reading "waiting." The managed check-in service (the training-wheels layer I refuse to
retire until the homebrew one is boringly stable) still carried the actual duty. The tier was
assembled on the bench, not wired into the mains.

Arming it meant three things at once: fold the two containers — the TLS front and the watcher behind
it — into a single unit; point the gateway's heartbeat at the box for real; and make the box's own
watcher check in to the managed service, so the watcher gets watched too. A watcher that can die
silently is worse than no watcher.

## Choosing the harder shape on purpose

The two containers had been running as two separate units on a shared private network. The clean way
to collapse them is a **pod**: one shared network namespace, the TLS front reaching the watcher over
plain loopback, and only the front holding any public port at all — the watcher becomes structurally
unreachable except through its one intended door.

There are two ways to build that pod with rootless Podman. One is Podman's own native pod unit. The
other is to write a genuine **Kubernetes pod spec** — the same YAML you'd hand a real cluster — and
let Podman *play* it. The native way is simpler and fits the rest of the house. I chose the
Kubernetes way anyway, and entirely for the wrong-looking reason: it's the one artifact in this whole
project that would transfer, unchanged, to a real cluster. The point of this box was never the box.
It was the practice. So the pod is described in a portable spec, and that decision is the seed of the
whole rest of the story.

## The migration that had to touch nothing important

The dangerous part wasn't building the pod — it was *replacing* the running one without losing what
it was standing on. Two volumes held things I could not afford to lose: the watcher's little state
file, and the auto-issued TLS certificate along with its issuing account. Lose the cert volume and
the machine re-requests a certificate — and the public certificate authority rate-limits how often
you may do that, so a careless migration can lock you out of your own padlock for a week.

Two experiments on a throwaway pod, before touching the live one, bought all the confidence:

- **The pod spec adopts existing volumes by name.** Claim a volume by the exact name Podman already
  gave it, and the new pod mounts the *old* data rather than creating an empty one. The tell that it
  worked, after the swap: the certificate's serial number was byte-for-byte unchanged. The padlock
  never noticed it had been rehoused.
- **There is a flag that quietly destroys those volumes,** and it is exactly the flag a tidy-minded
  person reaches for. A "force" option on the pod's teardown looks like a clean-shutdown nicety;
  what it actually does is delete the pod's data volumes on *every stop*. I proved it on scratch
  volumes — default teardown leaves them, "force" reports them removed — and then wrote a small
  shouting comment into the unit so future-me never enables it. On this pod, "force" would mean
  destroying the certificate and the state file on the next routine restart.

One more sharp edge: secrets. In the old two-unit world, the watcher's token and webhook rode in a
plain environment file. A pod spec has no equivalent, and the obvious workaround — hand Podman a
pre-made secret — fails in a way that took a minute to read, because Podman insists a secret's
*contents* be themselves a Kubernetes secret manifest. The clean answer turned out to be an inline
secret document living in the same played file: no separate secret to manage, and the teardown
removes it so a rotated value is simply picked up on the next start. Encoding, not encryption — so
the file's permissions carry the whole weight, and the diff was checked to make sure not one byte of
it ever reached a log.

## The guard that fell and no one raised

Then the migration landed, the tier came alive, and I went looking for trouble in the one place I'd
flagged as risky: what happens when the watcher *crashes*? In a real cluster this is a non-event —
the supervisor notices the dead container and restarts it within seconds. The pod spec even *says* to:
restart policy, always.

I killed the watcher container. It stayed dead. Three minutes later it was still dead, its restart
count stubbornly zero, the public endpoint returning bad-gateway while the TLS front sat perfectly
healthy beside a corpse. The good half of the result: killing one container did **not** cycle the
whole pod, so the certificate front never even flinched. The bad half: nothing brought the watcher
back.

I tried every lever the spec offered — the restart policy, an exit-propagation setting that should
fail the whole unit when any container dies, a liveness probe that should restart on a failed health
check. On this version of Podman, **every one of them was inert.** And here's the thing worth writing
in bold: **a pod spec played by this container engine is not a Kubernetes pod.** The per-container
supervisor that makes `restartPolicy` mean something is a *cluster* component; the single-host engine
that merely *plays* the spec has no such daemon in this release. It honors the spec's shape, not its
promises. The very portability I'd chosen the format for came with a quiet asterisk: the paper says
Kubernetes, the runtime is not.

So the pod I'd built traded away something the two old units had for free. Two separate services,
each supervised by the host's init system, each restarted on death without a thought. Fold them into
one pod for the sake of the portable spec, and that per-service safety net goes with them. Nobody
warns you; the spec still cheerfully claims otherwise.

The resolution was to stop fighting the platform and lean on a design I already had. The watcher
checks in to the managed service *itself* — so a dead watcher stops checking in, and the managed
floor pages about it, exactly as it would page about a dead anything. The crash doesn't self-heal; it
*self-reports*. A human runs one restart command, or a reboot brings it back on its own. For a
process specifically engineered never to throw, a rare crash caught by a page is an honest trade for
a portability rep — and the real fix, a newer engine that restores the supervisor, arrives for free
on a future OS upgrade. I wrote the whole reasoning down so the "accepted cost" line in the plan
couldn't quietly rot into a lie; the earlier draft had claimed recovery "still happens, just less
visibly," and that was simply false. Measured, not assumed.

## Two bells for one silence

The final proof is the one I'd been building toward all along, and it's worth savoring because it
vindicates the paranoid version of the design. The gateway doesn't ping *only* the homebrew watcher;
it pings *both* the managed service and the homebrew watcher, on the same timer. I could have chained
them — gateway pings the watcher, watcher reports to the managed floor — but that leaves a gap: a
watcher that's *up but broken* would keep the managed floor happy while silently failing to watch the
gateway. Two independent pings, two independent judges.

To prove it, I stopped the gateway's heartbeat and waited. Twenty-two minutes later, two alarms rang
in the same channel from two entirely separate paths: the managed service, noticing the gateway had
gone quiet, and the homebrew watcher on the far box, noticing the very same silence on its own. One
restored ping healed both with a single recovery notice. The fleet now has an eye that sits outside
every way it can fail, and a second eye watching that eye — and both of them proved they can see the
dark.

## What I'd tell past me

- **A pod spec is not a cluster.** A single-host engine that plays Kubernetes YAML honors the
  *shape* and not the *supervision*. If you fold independently-restarted services into one played
  pod, you inherit the spec's portability and lose the host init system's per-service safety net —
  silently. Decide whether you're buying the rep or the resilience; on an older engine you can't
  assume both.
- **Measure the platform, don't read it.** Twice this build I "knew" something from a man page or a
  config field and was wrong — a start-timeout default that didn't apply, a restart policy that
  didn't fire. Both were caught only by killing something on a scratch instance and watching. The
  ways a feature is *documented* to work are not the ways it *does*.
- **The tidy-looking flag is the loaded gun.** The teardown "force" option reads like hygiene and
  behaves like a delete. When a knob's failure mode is "destroys persistent data on every routine
  stop," a shouting comment in the unit file is cheaper than the week-long rate-limit lockout it
  prevents.
- **Managed floor, homebrew ceiling.** The training-wheels service isn't something to be embarrassed
  by and retire early — it's the thing that catches the homebrew layer when the homebrew layer dies.
  The recursion (the watcher checks in to the watched service) turned a platform limitation from a
  hole into a page.
