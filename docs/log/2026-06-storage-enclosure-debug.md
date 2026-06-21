# 2026-06 — Durable storage: enclosure-or-drive debug (parked)

**Goal:** add a real NVMe SSD as durable storage for the fleet — a brand-new drive,
temporarily mounted in a USB-to-NVMe enclosure for first checkout before it lands in
its permanent home. The checkout never got that far: the drive won't enumerate. This
is the write-up of how far the diagnosis got before it was **parked** for lack of the
one part needed to finish it.

## The symptom

Plug the enclosure in and the USB-to-NVMe bridge appears fine — it enumerates, reports
its own identity — but the drive behind it shows up as **zero bytes, no model string**.
A brand-new SSD should report its capacity and model even with no partitions on it, so
"0 B" doesn't mean "empty," it means **the bridge can't talk to the drive at all**.

The kernel log told the precise story: the bridge issued a *read-capacity* command and
got back an error, so it fell back to reporting zero blocks. Two corroborating clues
came with it: the link negotiated at **USB 2.0** (a SuperSpeed enclosure dropping to
high-speed is what these bridges do when there's no working drive to talk to), and the
USB stack quietly used the older mass-storage transport rather than the faster one.

## The useful move: isolate by swapping the host, not the part

The drive was first checked out against a **fleet node** (a Pi). The instinct is to
start blaming that host — its USB power budget, the well-known quirks of this bridge
chip on Raspberry Pi. Resist that. The tighter loop is to move the **same enclosure**
to a **completely different machine** (an x86 workstation) and look again.

Identical result: same zero-byte device, same USB-2.0 fallback. That single test
**eliminated the entire host as a variable** — not the Pi's power, not the Pi-specific
chipset quirks, nothing about the node. Whatever is wrong travels *with the enclosure
and drive*. An afternoon of chasing Pi USB tuning was avoided by one replug.

> Lesson: when a peripheral misbehaves, prove whether the fault is in the *host* or the
> *peripheral* before tuning either. Carry the suspect part to a second host; let the
> result pick the branch for you.

## What got ruled out

- **Wrong drive type for the enclosure.** A common trap: an M.2 SATA stick physically
  fits the same slot as an NVMe one but won't work in an NVMe-only bridge, and it
  presents *exactly* this 0-byte symptom. Checked the drive: it's a single-notch
  **PCIe NVMe** stick, which is what this enclosure wants. Not a mismatch.
- **The host.** Eliminated by the two-machine test above.
- **A loose drive.** The enclosure's pad doubles as a hold-down that presses the drive
  onto its contacts; reseating and pressing the drive firmly while testing changed
  nothing.

## What's left — and why it's parked

Three suspects remain, and they can only be separated with **a second piece of
hardware that isn't on hand**:

- a **bad cable** — cheap to rule out with a known-good one;
- a **dead drive** — provable by testing it in a direct M.2 slot;
- a **faulty enclosure** — provable by putting a known-good NVMe in *this* enclosure.

With neither a spare known-good NVMe nor a free M.2 slot available, the deciding
cross-test can't be run, so the verdict stays open. Rather than let a hardware
wild-goose-chase block other work, this is **shelved** until a durable storage path —
and the parts to validate it — are in hand.

## Resuming later

Pick up at the cross-test, fastest-first:

1. Swap to a known data-capable USB 3 cable and port. If it jumps to SuperSpeed and
   enumerates, the cable was masking everything.
2. Put a **known-good NVMe** in this enclosure. Still zero bytes → the enclosure's
   drive side is dead. Works → the original drive is the problem.
3. Put the **original drive** in a direct M.2 slot. Undetected there too → the drive
   is dead on arrival.

The methodology is the keeper here even though the hardware verdict isn't in yet:
**swap one variable at a time, host before part, and don't buy a theory you can't test.**
