# Onboarding a node

How a freshly-flashed node becomes a managed member of the fleet. This is the
steady-state procedure; the war story of the first node brought in this way lives in
the [build log](../log/README.md).

The fleet began all–Raspberry Pi and now carries one amd64 node, so this runbook is written
arch-agnostically where it can be. The genuine non-Pi deviations — legacy-BIOS boot instead of the
Pi bootloader, a hardware clock that starts in local time rather than UTC, and a package or two the
minimal installer omits — are called out where they arise. The first non-Pi walked every one of them
into the open.

The fleet sits behind the gateway on a flat, trusted LAN, and the machine that runs
Ansible is deliberately *not* on that LAN — so every node is reached by jumping through
the gateway. A new node therefore has to become both *addressable* and *reachable*
before it can be configured at all.

## Identity before configuration

Two facts about a node are settled before any role runs.

**Its address is pinned by hardware.** The fleet reserves a small static range for its
named nodes and hands everything else a lease from a separate dynamic pool. A node's
place in the static range is keyed to its NIC's hardware address rather than configured
on the node — so the gateway hands it the same address every time, and that address
survives a wiped SD card. One inventory entry per node is the single source that drives
both the DHCP reservation and the internal DNS record, so the two can't drift.

**It's reachable by key, not password.** Nodes behind the gateway are reached
non-interactively (the control host jumps through the gateway), so key authentication
has to be in place from the very first boot. The imaging tool forces a choice between
seeding a login password and seeding a public key — so the key wins. A node flashed
password-only has to be fixed up by hand before automation can touch it, which is a gap
worth not opening.

## The path a node walks

1. **Flash** the OS image — the lean headless build (every node, the kiosk included; the
   kiosk draws its screen from a minimal compositor, not a full desktop) — and seed the
   hostname and the fleet's SSH public key at flash time.
2. **First boot** brings the node up on a dynamic-pool lease. That's expected; it gets
   pinned next.
3. **Identify the node's hardware address** from the gateway. No login is needed: the
   gateway already sees the node in its DHCP leases, and its bridge tables tell a wired
   NIC from a wireless one — enough to record the right address without trusting a
   guess.
4. **Add the node to inventory** — its reserved spot in the static range plus its
   hardware address. A dual-homed node lists both of its NICs, so it keeps the same
   reserved address whether it joins by cable or over WiFi.
5. **Pin it from the gateway.** A single run *on the gateway* writes the DHCP
   reservation, publishes the internal DNS name, and refreshes the static
   name-to-address map every node carries — none of which needs the new node to be
   reachable yet.
6. **Move the node onto its pinned address** with a reboot or lease renewal, and
   confirm the internal name now resolves to it.
7. **Configure the node.** Membership basics are inherited automatically (below); the
   first run also needs the privilege-escalation password once, until the baseline
   grants the admin user passwordless sudo.
8. **Wire it into observability** by adding it to the metrics scrape targets, so the
   monitoring node starts collecting from it. Logs flow on their own as soon as the log
   shipper is running.

## Membership is inherited, not assembled

The basics that make a box a *fleet member* — the package-cache pointer, base packages,
trust for the internal certificate authority, the fleet name map, journal access,
passwordless sudo for the admin user, pressure-stall telemetry, plus the metrics
exporter and the log shipper — are applied to *every* node by a single baseline that
targets the whole fleet. A new node gains all of it just by existing in inventory;
there is no per-node wiring to remember. A node's actual *job* is layered on top only
when it has one — so a node whose role is still undecided is already a complete,
observable member carrying nothing but the baseline, which is a perfectly good place
for it to sit.

## Three things that would bite, and why they don't here

**Reflash keeps the address.** Because the reservation is keyed to the NIC's hardware
address and that survives reflashing, a wiped-and-rebuilt node returns on the same
address with the same name — no per-host reconfiguration. A node that turns up on an
*unexpected* address is leasing from something other than the gateway, which is a
useful signal in itself.

**Provisioning hands off cleanly to config management.** The image's first-boot
provisioning (cloud-init) does its one job — create the user, seed the key, set the
hostname — and is then deliberately stood down, so it can't keep re-asserting itself on
later boots and quietly undo state the fleet's own automation owns. (The fleet name map
was the casualty that made this rule explicit: first-boot provisioning was rewriting
the hosts file on every reboot.) A reflash starts fresh and provisions again; the next
automation run stands it down again. First boot provisions; everything after belongs to
config management.

**A clockless board can fail its own first run.** These boards have no battery-backed clock,
so a freshly flashed node boots believing it's some default past date until it reaches a time
server — and a wrong clock silently fails anything that checks a validity window: package
signatures, and TLS against the internal CA. So "confirm the clock is synced before the first
real run" is a written step. It usually syncs within seconds of boot; when it hasn't, a
skewed clock is the unglamorous explanation for an otherwise baffling signature or
certificate failure.
