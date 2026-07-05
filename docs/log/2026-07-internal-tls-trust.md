# 2026-07 — The trust that wasn't: healing the CA bundle

**Goal:** make every fleet node's trust in `https://*.fangs.internal` **verified, not
assumed**. The internal CA and reverse proxy have been live for weeks ([that
build](2026-06-tls-reverse-proxy.md)); the base role installs the fleet root CA on every
node; `curl` from anywhere should just work. The whisper that started this feature: weeks
earlier, one node's system trust had turned out to be silently broken — CA file on disk,
but absent from the active trust bundle. That was patched by hand and parked as "gather
into a TLS revisit." This is the revisit.

## The audit: it was worse than the parked note said

The research stage's first move was a live read-only audit — every node, verify the CA
against the active bundle, then a real HTTPS request with no escape hatches. Result:
**half the fleet couldn't complete a TLS handshake to its own services.** Not just the
node from the parked note — a second node had the identical rot, undiscovered because
nothing on it had happened to need internal TLS yet.

The failure shape on both: the CA *file* was exactly where the base role put it, but the
*bundle* — the thing TLS clients actually read — contained only the stock Mozilla set.
And the state was **stable**: the role copied the file, and only a *change* to the file
triggered the bundle rebuild. File already converged → no change → no rebuild → broken
forever. A convergence-looking system that had quietly diverged.

## The fix: assert the effect, not the artifact

The change is one role, four small tasks, one idea: **prove the bundle, not the file.**

1. **Assert every run** — an `openssl verify` of the fleet root against the live bundle.
   Cheap, semantic, and it runs on every play including dry-runs.
2. **Guard the read-only node** — the kiosk node boots from a read-only card with a RAM
   overlay ([durable storage](2026-06-durable-storage.md)). A bundle rebuild there would
   *succeed*, land in RAM, and evaporate at the nightly reboot — a silent fake success.
   The role now refuses, loudly, with instructions, rather than pretending.
3. **Heal from scratch** — rebuild the bundle when the assert fails.
4. **Re-assert after healing** — run the same verify again, so the play itself proves the
   heal *worked* rather than merely *ran*.

That last task was insurance written out of habit — the pipeline's standing "prove the
effect, not the start" rule. It turned out to be the hero.

## Premise miss #1: the dry-run couldn't see the fix

The proof checklist predicted that a pre-apply dry-run on the broken nodes would flag
exactly the heal task as pending. It flagged nothing. Command-style tasks are *skipped*
in dry-runs — the tool can't predict a command's effect, so it doesn't pretend to — which
means the very task doing the healing was invisible to the safety check meant to preview
it. The fix is a tiny "flag" task that *is* dry-run-aware and reports "would change"
exactly when the probe fails. Now the dry-run tells the truth in both directions: pending
heal shows as a change; healthy fleet shows clean.

## Premise miss #2: the heal that heals not

The bigger one. First live apply: heal task runs, reports success — and the very next
task, the re-assert, **fails the play**. The bundle was still broken.

The culprit: the bundle-rebuild tool's default mode only appends certificates it
considers *new*. On a wedged node — cert present, bundle without it — it examines the
state, concludes "nothing new here, 0 added," exits successfully, and repairs nothing. A
no-op with a success code. Only the tool's from-scratch mode actually rebuilds the bundle
it's named after. One node healed with the from-scratch flag while the other still had
the fake heal made for a perfect natural experiment: same play, incremental no-op on one,
full rebuild on the other, only one came back trusting.

Without the re-assert, that apply would have *looked* green — heal ran, changed, done —
and the feature would have shipped with its central promise broken on the exact nodes it
existed to fix. The gate that caught it costs one read-only command.

## The proof got an upgrade from reality

The checklist had a manufactured-failure test: deliberately break a node's bundle, prove
the next run heals it without touching the CA source file. Reality provided a better one.
The second broken node *was* the genuine article — wedged for months — and the play's
heal fixed it with the source file's hash verifiably identical across the whole episode.
The synthetic break was waived as strictly weaker evidence than the real repair already
witnessed. Final sweep: every node × every proxied service, real TLS handshakes, no
escape hatches — all green.

## A bonus find: the read-only node eats applies

The final fleet-wide idempotency check surfaced an unrelated drift: a config change
applied to the kiosk node weeks ago had landed in its RAM overlay and been discarded by
the nightly reboot. The service still runs (the old config still points somewhere valid),
but the change never persisted — and every dry-run since has been flagging it. General
lesson, now recorded: **any change to that node's root filesystem while the read-only
guard is armed silently evaporates.** The only honest verification there is a re-check
*after* its next reboot. Filed as its own follow-up; not this feature's to fix.

## What I'd tell past me

- **Audit before you architect.** The parked note said one node; the ten-minute read-only
  audit said half the fleet. The fix barely changed, but the urgency — and the proof that
  the failure class was systemic, not a one-off — came from looking first.
- **"Converged" describes the artifact, not the outcome.** The file was perfect on every
  node. The system it was supposed to configure was broken on half of them. Assert the
  *effect* — the handshake, the verify — on every run, not the file's checksum.
- **A tool exiting 0 is a claim, not a fact.** The rebuild tool's happy exit while
  repairing nothing is the sharpest version of this lesson yet. The one-line re-assert
  after the heal is the cheapest insurance in the whole role.
- **Change-triggered handlers can't fix what's already wrong.** They fire on transitions,
  and a system can be broken *at rest*. Anything load-bearing deserves an every-run
  assertion, with the trigger as an optimization on top.
- **Read-only roots turn applies into lies.** A success report against a filesystem that
  forgets on reboot is worse than a failure — it closes the loop in your head while the
  fleet stays wrong. Fail loudly at apply time, and verify after the reboot.
