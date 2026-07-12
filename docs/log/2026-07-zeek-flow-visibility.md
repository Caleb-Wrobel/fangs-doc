# The transcriber in the doorway

**2026-07-11** · observability · networking · learning

Since the repo's first commit, one line in the architecture notes promised an IDS on the
gateway "someday": Suricata and Zeek, planned, never built. It was the oldest open promise
in the project. Today half of it landed — and the other half was deliberately torn up.

## Choosing to watch, not to judge

The fork in the road was what the network layer's telemetry should *be*. Suricata judges:
it matches signatures and raises alerts. Zeek transcribes: it converts packets into
structured, typed logs — every DNS question, every TLS handshake's disclosed server name,
every connection's shape — and leaves the judging to you. On a NAT'd home LAN, an IDS's
alert stream is mostly unactionable internet background radiation; what this fleet lacked
was not a judge but a *record*. Journals ship to the log store, metrics to the scraper, but
what the wire itself carried was invisible. So Suricata was descoped — possibly forever —
and the feature became **flow visibility**: the fleet's visibility-over-least-privilege
philosophy rendered as software. A transcriber, not a sentry.

## Where to stand

A gateway offers two places to tap. The WAN side carries exactly one flow: the VPN tunnel,
an opaque encrypted stream, useless to transcribe. The LAN bridge sees every client
conversation *before* it is swallowed by the tunnel — real destinations, TLS server names,
every query the fleet asks the resolver. So the tap stands on the bridge, and the WAN
interface is never touched; one of the acceptance checks literally proves the capture
process's command line names the bridge and the WAN NIC never enters promiscuous mode.

## Native by necessity, lean by choice

The fleet's packaging rule says new services default to rootless containers *unless* they
are genuinely host-coupled — and promiscuous capture on the gateway's bridge is about as
host-coupled as software gets, so Zeek runs native. Debian's own archive had no usable
package, but the upstream project's build service publishes an arm64 repository for exactly
this Debian release. The plan-stage worker went one step further than reading the package
index: it downloaded the actual `.deb` and looked inside, which caught a wrong assumption
(the install prefix wasn't what the version-suffixed package name implied) before it could
become a broken unit file. The lean core package alone sufficed — no control shell, no
plugin manager, no dev toolchain — run by a hand-written systemd unit as an unprivileged
user holding only the two capabilities raw capture needs.

Some inherited fleet wisdom shaped the details. The logs live on the gateway's durable
NVMe, never the SD card, and the unit refuses to start if that disk is absent — the same
gate the log store itself uses, so a dead drive can never silently redirect packet logs
onto the fragile medium. And the JSON switch lives in a separate policy file loaded after
the packaged site policy, because the packaged one is a dpkg conffile and templating it
buys you upgrade conflicts forever.

## One label per file, one source for all

Shipping the logs reused the existing journal shipper on the gateway; the only new
machinery is a file source that tails the curated set — DNS, TLS, oddities, notices — with
the log *type* as a queryable label. The shipper's config template is shared fleet-wide,
so the new block is gated on a variable only the gateway defines: every other node renders
a byte-identical config and never restarts. The connection log — the per-flow firehose —
was deliberately held back until its volume could be measured against the log store's
one-week retention. Three hours of capture answered that: on a quiet home LAN it amounts
to megabytes per week, and the hold-back was lifted the same evening.

## The blind spot speaks

The proof checklist was the usual nineteen gates — resource budget measured over a real
interval (a tenth of a percent of one core; a quarter of the memory bar), rotation
observed across its first hourly boundary without breaking the tail, firewall ruleset
hash-identical before and after, DNS latency unchanged. But the reward came from the first
hours of data. The Apple base station that serves as the fleet's second access point has
always been the one un-telemetried box on the network — no exporter, no logs, a sealed
appliance. It now has a voice: its NTP calls home, its config-sync chatter, its
name-service announcements, all transcribed in the DNS log. And the kiosk's browser turned
out to be quietly consulting a Google optimization service dozens of times an hour —
harmless, but invisible yesterday, and now a one-flag candidate for the kiosk role's next
touch-up. That is the feature working as intended: not alarms, just the wire, written down.

## Addendum, same evening: the first reader

A transcriber nobody reads is a disk heater, so the first consumer followed the same day: a
provisioned **Network dashboard** — top talkers, per-client DNS rates, top queried names, TLS
server names, and a ticker for the oddity channels. Fleet nodes display under their wolf names;
anything unrecognized stays a raw address on purpose, because an unfamiliar number on the board
*is* the signal. It worked immediately: two unknown addresses turned out to be a phone (iOS's
per-network randomized MAC) and — better — the Apple base station itself, which had quietly
drifted to a different address than every note said it had. That earned it a permanent DHCP
reservation via a new mechanism for pinning non-fleet appliances, and taught the general lesson:
**IP-keyed references to DHCP'd devices rot — pin the lease or don't write the number down.**
Two smaller lessons from the build: the log store's JSON parser flattens dotted field names, and
its query language refuses to add two unwrapped range-aggregations in one expression — the
dashboard joins two queries per table instead. Validation went through the dashboard engine's own
query API rather than the log store directly, so the datasource wiring was proven, not assumed —
and the one thing an API can't judge, the rendered board, got human eyes before the merge.
