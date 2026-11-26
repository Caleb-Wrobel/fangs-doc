# Networking

The networking is split between two boxes. A dedicated **edge router** owns
everything that touches the outside or the wire: routing, NAT, the firewall, the
WAN, the wired switch ports, the WiFi access point, VPN egress and the leases.
The **LAN services node**, `limen`, owns the services the LAN leans on: the
primary resolver, the battery-backed time source, the reverse proxy and the
observability stack. It has no WAN and routes nothing. Every other node is an
ordinary DHCP client on a flat LAN.

## Interfaces and roles

- **The edge router** has one upstream port facing the residential router, and
  the rest of its ports bridged into the LAN with its WiFi radio. It is the LAN's
  gateway, its DHCP server and its second DNS server.
- **`limen`** sits on one switch port with a static address. It serves no DHCP
  and takes none. Its WiFi is idle; access-point duty belongs to the router.

> **Trixie note.** Recent Raspberry Pi OS dropped netplan, so the fleet runs
> three network stacks: `systemd-networkd` on `limen` (NetworkManager disabled
> so the two don't fight), NetworkManager on most nodes, and a per-interface
> DHCP client on the rest. That last split matters for time (below).

## VPN egress and the kill switch

Everything the LAN sends to the internet leaves the **edge router** through a
WireGuard tunnel to a commercial VPN, pinned to one server. There is no vendor
VPN client anywhere: the tunnel is a plain WireGuard interface on the router,
and the policy is the router's own. The notable design choice is still **where
the kill switch lives**: in the firewall, not in a client.

- **Policy routing** sends LAN-sourced traffic to a separate table whose only
  default route is the tunnel. Local destinations (the LAN, the remote-access
  tunnel, the upstream router's subnet) bypass it.
- **The kill switch** is a forward-chain drop for anything leaving through the
  upstream port in the clear. With the tunnel down, client traffic has no path
  at all. Fail-closed by construction, and a dead tunnel is a LAN-wide internet
  outage on purpose.
- **The router's own traffic stays outside the tunnel.** So does the
  remote-access tunnel, so the house stays manageable from outside while the
  VPN is down.
- **One switch.** A single variable tears the whole thing down and restores the
  plain upstream; the same variable puts it back. The runbook for a lapsed
  subscription, a provider swap or a dead server sits next to the role.

The catch is alerting. A dead tunnel also cuts the observability node off from
the internet, so the tunnel's own alert can't be delivered while it fires. The
pager that works during an outage is an off-site heartbeat that notices the
node has gone quiet. (The full story is in the
[build log](../log/2026-11-vpn-egress-on-the-router.md).)

> **Gotcha from the earlier design.** The VPN used to run as the vendor's client
> on a Pi gateway. That client's "firewall" setting, distinct from its kill
> switch, silently dropped LAN DHCP. Lesson: a vendor firewall toggle can stomp
> on services you're managing yourself. Own the policy in one place.

## DNS

Two resolvers, handed out in order by DHCP:

- **`limen`'s Unbound** is the primary. It does **not** do full recursion from the
  root servers; it **forwards over DNS-over-TLS** to an upstream resolver.
- **The edge router** is the fallback. It answers the fleet's own names from a
  static set generated from the same inventory as everything else, and sends the
  rest upstream over **DNS-over-HTTPS**, steered into the VPN tunnel. An output
  drop on the upstream port catches a failed steer, so it fails closed. Unknown
  internal names are forwarded and come back "no such name" from upstream: a
  zone-wide negative entry would hide every real name on this router (see the
  [build log](../log/2026-11-dhcp-on-the-router.md)).

Why forward instead of recurse? Behind the VPN, outbound plain DNS is intercepted,
which breaks the many small conversations full recursion depends on. An encrypted
upstream rides one connection that passes cleanly through the tunnel. So the
constraint (a hijacked DNS port) *chose* the architecture, not the other way around.

Every node also carries the full fleet by name locally, so host-to-host naming
works even if both resolvers are mid-restart.

## Time

The router serves time first and `limen` second. The router syncs from public
servers and never serves its own clock while unsynced; its answers then carry the
"not synchronised" flag and clients skip to `limen`. `limen` stays in the list
because it has the fleet's only battery-backed clock: after a power cut that
brings the house back before the internet, it's the one source that's right.

Only some DHCP clients pass a DHCP-supplied time server on to the system clock,
so the order is set on every node directly; the DHCP option covers whatever else
joins the LAN.

## Addressing that survives a reflash

Fleet IPs are pinned by **DHCP reservation keyed to each NIC's MAC**, not
configured statically on the nodes. A freshly flashed node boots stock, asks for
an address, and the router hands it the *same* address every time because the
MAC is burned into the hardware and survives SD-card reflashing. Add a node's MAC
to the inventory and it lands on the right IP on first boot, with no per-host
static config to maintain. The same inventory list renders the router's
reservations and DNS names, `limen`'s resolver, and the stopped rollback DHCP
server on `limen`, so they can't drift.

**One address per MAC.** The router can't reserve one address for two MACs, so the
old trick of keeping a node's address across a wired→wireless flip is gone. WiFi
failover was retired on the wired nodes; the one node that keeps a WiFi standby
has its own address and name for it. (The original design is in the
[WiFi failover build log](../log/2026-06-wifi-failover.md).)

## Remote access from off-LAN

The edge router is the only WAN-facing surface, and internal services are never
published there — the reverse proxy listens on the LAN side only. So reaching a
service from a machine that isn't on the home LAN means **tunnelling in**, not
exposing the service. It began as an SSH tunnel through the old Pi gateway — one
authenticated path, no new inbound port, the internal `*.fangs.internal` names
resolving back through it — which worked, but only from the same upstream network.
The overlay below replaced it.

A standing temptation is the commercial VPN's **built-in mesh overlay** — it would
need no inbound port and reuses a vendor already trusted for egress. It stays
**off**, for two reasons. First, *footprint*: it adds an inbound mesh surface on the
edge and enrols the edge in the vendor's coordination plane, when the edge's
whole job is to be minimal. Second, and decisively, enabling the mesh
**force-enables the vendor client's own firewall** — the very toggle that silently
drops LAN DHCP (above) — and won't let that firewall be turned back off while the
mesh is active. That would hand DHCP-safety to a vendor knob and re-import a second
filtering policy from outside, violating the principle that the firewall owns the
policy in one place. (The full story is in the
[remote-access build log](../log/2026-06-remote-access.md).)

That build now exists: a **self-hosted WireGuard road-warrior**, landed on the Pi gateway
2026-07-08, **redesigned 2026-08-20** so the edge is no longer the one accepting inbound
connections at all, and carried over to the edge router when it took over the edge. The off-fleet box (a small always-reachable cloud presence, fixed
address) is the one point everything dials *out* to now — every client, the edge router included —
which means the edge carries **zero** inbound ports for this rather than one. The vendor
firewall stays off and the kill-switch-in-the-firewall model stays intact throughout. It's still
**split-tunnel** — a client reaches the fleet by name (DNS resolved by `limen`'s
resolver, relayed the same way) while ordinary traffic stays on the client's own upstream, so
remote access doesn't drag everything through the egress VPN. See the
[build log](../log/2026-08-wireguard-hub.md) for the redesign itself.
