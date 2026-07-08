# 2026-06 — Pressure-stall metrics, fleet-wide

**Goal:** give every node a real "is this box actually struggling?" signal —
**Pressure Stall Information (PSI)**, the kernel's measure of how much genuine work
is being delayed waiting on CPU, memory, or IO — and get it consistent across all
four hosts so a single dashboard reads the whole fleet.

A small feature on paper: flip one kernel flag, scrape one more metric. In practice
it touched the bootloader, needed a reboot per node to land, and had one editing
bug that could quietly cost a node its boot.

## Why PSI, and why it mattered most on the small node

On modest single-board hardware, **load average lies**. A box can show a calm load
while real work stalls waiting on memory, and a box can show high load while
everything's actually fine. PSI measures the thing you care about directly: the
*fraction of time* tasks spent blocked waiting on a resource. Rising memory
pressure is an early warning that a node is about to thrash — visible *before* the
squeeze actually bites.

The node this matters most for is a **memory-tight 1 GB node** — a Pi 3B+ doing
storage and caching work. It's the one with the least headroom and the most to gain
from seeing pressure climb before it tips over. So PSI started there and then went
fleet-wide so one dashboard could compare every node on the same axis.

## How it's turned on

PSI isn't on by default; it's a **kernel boot flag** (`psi=1` on the kernel
command line). Once enabled, the kernel populates `/proc/pressure/*`, which
node_exporter's pressure collector reads and exposes as metrics — and from there a
**"Fleet memory & pressure" Grafana dashboard** charts every node side by side.

Two consequences of it being a *boot* flag:

- **It only takes effect after a reboot.** Applying the role doesn't light up PSI;
  the node has to come back up with the new cmdline. So the rollout was inherently
  "change, reboot, verify" on each host — and "fleet-wide PSI" really meant *every
  node had been rebooted into it*, not just configured for it.
- **Editing the kernel command line is touchier than editing a config file.**

## The bug that nearly broke boot

The Raspberry Pi kernel command line lives in a file that must be **exactly one
line** — a single space-separated string of boot arguments. The bootloader reads
that one line; anything that turns it into *two* lines splits or strips the
arguments and can leave a node unbootable.

The idempotent way to add a flag is "append ` psi=1` only if it isn't already
there." The trap: a regex written to match "the line" with a permissive
end-of-line, run in multiline mode against a file that has a **trailing newline**,
*also matches the empty final line* — and dutifully appends a second ` psi=1` on
its own line. Now the file is two lines. One node hit exactly this and showed why
it matters before it became a real brick.

The fix was to require the matched line to be **non-empty** (match "one or more
characters," not "zero or more"), so the empty trailing line is never a candidate
and the flag is appended exactly once, in place, on the single real line. Re-runs
now change nothing, and `cmdline.txt` stays one line — which is the only thing the
bootloader will forgive.

## What I'd tell past me

- **A "small" feature that touches the bootloader isn't small.** Config-file
  mistakes get logged; cmdline mistakes don't boot. Treat that file with extra
  care.
- **"Configured" isn't "active" for boot-time flags.** Fleet-wide meant a reboot
  per node, and the rollout isn't done until every node has actually come back up
  into it.
- **Idempotent text-munging has edge cases hiding in whitespace.** A trailing
  newline turned "append if missing" into "append a broken second line." When a
  regex can match emptiness, decide on purpose whether it should.
- **PSI earns its keep on the weakest hardware.** The point isn't a prettier
  dashboard; it's seeing the smallest node strain before it falls over.
