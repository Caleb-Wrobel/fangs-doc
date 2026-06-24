# 2026-06 — Durable storage: enclosure debug, and how the verdict was wrong (resolved)

> **Update (resolved): the drive was never faulty.** Mounted directly on the Pi 5's
> M.2 HAT, the *same* NVMe enumerates cleanly over native PCIe and now runs as the
> fleet's durable storage — formatted, mounted, and carrying the data layer (the
> database was migrated onto it and survives a reboot). So the parked conclusion below
> — that the fault "travels with the enclosure and drive" — was **mistaken**. The
> host-vs-part isolation was sound as far as it went, but it stopped one step short: a
> zero-byte reading *through a USB bridge* is not proof the drive is dead. The real
> lesson is the cheaper one — **before condemning a part, try it on its native
> interface.** The original narrative is kept below as an honest post-mortem of a
> correct method that drew the wrong conclusion.

**Goal:** add a real NVMe SSD as durable storage for the fleet — a brand-new drive,
temporarily mounted in a USB-to-NVMe enclosure for first checkout before it lands in
its permanent home. The checkout never got that far: through the enclosure, the drive
wouldn't enumerate. This was written up as a **parked** diagnosis — see the correction
above for how it actually resolved.

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

## How it actually resolved

The cross-test above never had to be run, because the answer came from the suspect's
*native* interface instead. The drive was seated directly on the Pi 5's M.2 HAT — no
USB bridge in the path — and it enumerated immediately as a PCIe device, full capacity
and model string, healthy. That single result collapsed all three remaining suspects:
the **drive is fine** (it works direct), so the zero-byte reading was an artifact of
the USB-bridge path, not a dead SSD. The enclosure was simply set aside; the HAT is a
better permanent home anyway (PCIe, not USB).

It's now the fleet's durable storage: partitioned, formatted, and durably mounted, with
the data layer relocated onto it and verified to come back cleanly after a power cycle.

**The corrected lesson:** the host-before-part isolation was right, but "the fault is in
the peripheral" is not the same as "the part is dead." A USB-to-NVMe bridge reporting
zero bytes can mean the *bridge path* is the problem, not the drive. Before buying a
"dead drive" theory — or a replacement — try the drive on its native interface, which
here was both the cheapest test and the intended destination. The method was sound; the
verdict it was *about* to reach was not.
