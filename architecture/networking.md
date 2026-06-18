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

Client traffic egresses through a commercial VPN using a WireGuard-based
transport. The notable design choice is **where the kill switch lives**: not in
the VPN client, but in the firewall itself.

The firewall's forward chain permits client egress *only* via the tunnel
interface. There is simply no rule that would forward LAN traffic straight to the
WAN. So when the tunnel is down, client traffic isn't "blocked" by a feature —
there's no path for it at all. Fail-closed by construction.

The VPN client's *own* kill switch is deliberately turned **off**: it's redundant
with the firewall rule and, worse, it also blocks the gateway's *own* management
and update traffic when the tunnel drops. Letting the firewall own the policy
keeps the box itself reachable for maintenance.

> **Gotcha that cost real time.** The VPN client also has a "firewall" setting
> distinct from its kill switch — and when on, it silently dropped LAN DHCP.
> Lesson: a vendor "firewall" toggle can stomp on services you're managing
> yourself. Turn it off and own the policy in one place.

## DNS

DNS is split into two jobs on purpose:

- **DHCP server** hands out leases and is configured to do *DHCP only* — it is not
  the resolver.
- **Unbound** is the resolver. Interestingly it does **not** do full recursion
  from the root servers; it **forwards over DNS-over-TLS** to an upstream resolver.

Why forward instead of recurse? Behind the VPN, outbound port 53 is intercepted,
which breaks the many small UDP/53 conversations full recursion depends on.
DNS-over-TLS rides a single encrypted 853 connection that passes cleanly through
the tunnel. So the constraint (a hijacked :53) *chose* the architecture
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
