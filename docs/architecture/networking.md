# Networking

All of the interesting networking lives on the gateway, `limen`. The other nodes
are ordinary DHCP clients on a flat LAN.

## Interfaces and roles

The gateway has two sides:

- **WAN** — a USB ethernet adapter facing the upstream residential router. It's
  matched **by MAC address**, not by interface name, so its role survives kernel
  interface-enumeration reshuffling (`eth0` vs `eth1` is not guaranteed stable
  across boots; the MAC is).
- **LAN** — a bridge carrying the wired switch port and a WiFi access point. DHCP
  and local DNS are served on the bridge.

> **Trixie note.** Recent Raspberry Pi OS dropped netplan; networking is
> configured directly with `systemd-networkd`, and NetworkManager is disabled on
> the gateway so the two don't fight over the interfaces.

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

DNS is split into two jobs on purpose:

- **DHCP server** hands out leases and is configured to do *DHCP only* — it is not
  the resolver.
- **Unbound** is the resolver. Interestingly it does **not** do full recursion
  from the root servers; it **forwards over DNS-over-TLS** to an upstream resolver.

Why forward instead of recurse? Behind the VPN, outbound plain DNS is intercepted,
which breaks the many small conversations full recursion depends on.
DNS-over-TLS rides a single encrypted connection that passes cleanly through
the tunnel. So the constraint (a hijacked DNS port) *chose* the architecture
(forward-over-DoT), not the other way around.

Every node also carries the full fleet by name locally, so host-to-host naming
works even if the resolver is mid-restart.

## Addressing that survives a reflash

Fleet IPs are pinned by **DHCP reservation keyed to each NIC's MAC**, not
configured statically on the nodes. A freshly flashed node boots stock, asks for
an address, and the gateway hands it the *same* address every time because the
MAC is burned into the hardware and survives SD-card reflashing. Add a node's MAC
to the inventory and it lands on the right IP on first boot — no per-host static
config to maintain.

A nice consequence: WiFi failover can keep a node's IP across a wired→wireless
flip by reserving the *same* address against **both** the wired and wireless MACs.
(More in the [WiFi failover build log](../log/2026-06-wifi-failover.md).)

## Remote access from off-LAN

The gateway is the only WAN-facing surface, and internal services are never
published there — the reverse proxy listens on the LAN side only. So reaching a
service from a machine that isn't on the home LAN means **tunnelling in**, not
exposing the service. It began as an SSH tunnel through the gateway — one
authenticated path, no new inbound port, the internal `*.fangs.internal` names
resolving back through it — which worked, but only from the same upstream network.
The overlay below replaced it.

A standing temptation is the commercial VPN's **built-in mesh overlay** — it would
need no inbound port and reuses a vendor already trusted for egress. It stays
**off**, for two reasons. First, *footprint*: it adds an inbound mesh surface on the
gateway and enrols the edge in the vendor's coordination plane, when the edge's
whole job is to be minimal. Second, and decisively, enabling the mesh
**force-enables the vendor client's own firewall** — the very toggle that silently
drops LAN DHCP (above) — and won't let that firewall be turned back off while the
mesh is active. That would hand DHCP-safety to a vendor knob and re-import a second
filtering policy from outside, violating the principle that the firewall owns the
policy in one place. (The full story is in the
[remote-access build log](../log/2026-06-remote-access.md).)

That build now exists: a **self-hosted WireGuard road-warrior**, landed on the gateway
2026-07-08 and **redesigned 2026-08-20** so the gateway is no longer the one accepting inbound
connections at all. The off-fleet box (a small always-reachable cloud presence, fixed
address) is the one point everything dials *out* to now — every client, the gateway included —
which means the gateway carries **zero** inbound ports for this rather than one. The vendor
firewall stays off and the kill-switch-in-the-firewall model stays intact throughout. It's still
**split-tunnel** — a client reaches the fleet by name (DNS resolved by the gateway's own
resolver, relayed the same way) while ordinary traffic stays on the client's own upstream, so
remote access doesn't drag everything through the egress VPN. See the
[build log](../log/2026-08-wireguard-hub.md) for the redesign itself.
