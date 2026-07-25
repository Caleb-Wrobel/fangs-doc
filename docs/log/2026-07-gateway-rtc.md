# 2026-07 — A battery-backed RTC for the gateway (and how the diagnosis kept lying)

**Goal:** the fleet has no real-time clock anywhere — every node boots with a stale
clock until `timesyncd` reaches an NTP server, which breaks anything time-sensitive
(apt signature checks, TLS validation) until the network is up. The Pi 5 gateway node
has an on-board RTC; fitting it a coin-cell battery would let *that one node* keep
accurate time across a cold boot with no internet at all — a first step toward the
gateway someday serving as the fleet's own local time source.

The hardware side was simple: a coin cell on the board's battery header. Confirming it
actually worked took several rounds, because every quick test available gave a
**false positive**.

## False positive #1: the clock utility isn't even installed

The obvious first check, `hwclock -r`, failed immediately — not with a bad reading,
but with "command not found." On this OS release the utility was split out of the base
package set into an "extra" package. Looks exactly like a dead RTC; is actually a
packaging gap. Easy to fix, but a reminder to distrust an absent tool before blaming
hardware.

## False positive #2: the device exists whether or not the battery does

Once the utility was installed, `/dev/rtc0` was present and `hwclock -r` returned a
perfectly sane timestamp. Reasonable to read that as "confirmed working" — except
this SoC's RTC driver registers the device file **unconditionally**, battery or no
battery, and while the board has any external power at all, the RTC domain stays lit
from that supply, not the coin cell. So a plugged-in Pi will report a correct time
from a coin cell that's dead, missing, or never connected. The read tells you nothing
about backup power.

## False positive #3: a clean shutdown isn't a power-loss test

The natural next test — halt the machine and cold-boot it — *also* doesn't prove
anything, for the same reason: a soft shutdown still leaves the board's power input
connected. Only pulling power at the source (or, on hardware without a soft-power
path, waiting for a genuine outage) actually removes the supply the RTC domain has
been quietly riding on.

## The test that actually works

Two readings, together, are decisive:

1. **The battery-rail voltage**, read straight off the board's own ADC. A healthy
   coin cell reads a couple of volts; a value in the single-digit millivolts is not a
   weak battery, it's an **open circuit** — nothing electrically connected at all.
2. **What the RTC hardware reports at the very first moment of boot**, from the kernel
   log, *before* NTP has had any chance to correct it. A plausible date means the
   clock domain held through whatever power event just happened. A date sitting near
   the Unix epoch means the counter restarted from nothing — the backup failed.

Run against the gateway with these two checks, the picture flipped: the battery rail
read essentially zero, and the boot-time RTC value came back at the epoch. Not a weak
cell — an open circuit somewhere in the path.

## The detour: which coin cell is even correct

Before chasing wiring, it seemed worth confirming the right part was fitted in the
first place — RTC coin-cell chemistry advice online is inconsistent to the point of
contradiction. Settling it against the vendor's own documentation and an engineer's
public replies on their forum:

- Trickle-charging the cell is **off by default**, controlled by a single
  device-tree parameter that this fleet deliberately never sets.
- With charging off, a standard **non-rechargeable primary cell is the correct and
  safe choice** — despite some published guidance nudging toward a rechargeable
  lithium button cell instead, seemingly on service-life grounds.
- A rechargeable lithium-ion-chemistry button cell is flatly **the wrong part** —
  the charge controller has no charge-termination logic for that chemistry, and
  fitting one is a real safety hazard, not a preference. Any advice recommending it
  should be rejected outright.
- The one number that *looks* like it endorses the rechargeable chemistry — a
  programmable charge-voltage ceiling — is just the DAC's range limit, not a
  statement about what any given cell can tolerate long-term with no termination
  circuit.

Conclusion: the originally-fitted part was already the correct one. The open circuit
wasn't a chemistry mistake.

## The actual fault: a switch

With the right part confirmed and the wiring the only remaining suspect, the gateway
came down for an unrelated hands-on session — and the battery holder itself turned
out to have a small on/off switch molded into the case, left in the "off" position
since it was fitted. Not a bad crimp, not a connector mismatch, not a chemistry
error — a physical switch, invisible on a data-only inspection, silently keeping the
circuit open the entire time.

Switched on, and re-tested against the same two-reading method: the battery rail now
reads a healthy few volts, and — after the node was intentionally cut from mains
power as a real test, not a soft reboot — the very first boot-time reading from the
RTC hardware came back as a correct date, not the epoch. The clock domain held
through an actual power loss with no network in sight. Confirmed, not just plausible.

## The lesson

Every early "confirmation" in this saga was a real reading of a real device that
nonetheless proved nothing, because the device being read stays powered by something
other than the part under test. The fix wasn't clever: read the battery rail
directly, and read what the RTC hardware itself reports at the very first instant of
boot, before anything else has a chance to paper over the answer. And when a "wiring
fault" won't resolve, check for something dumber first — a case can ship with its own
switch turned off.
