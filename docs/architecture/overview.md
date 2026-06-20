# Architecture overview

fangs is a four-node Raspberry Pi cluster that behaves like a miniature, fully
self-hosted network: its own gateway, its own DNS, its own VPN egress, its own
internal certificate authority, and its own observability stack. Nothing here
depends on a cloud provider; the only upstream dependency is a residential
internet handoff.

## Shape of the system

```
            internet
               │
        ┌──────┴───────┐
        │    limen      │   gateway: NAT, firewall, VPN egress,
        │  (WAN edge)   │   recursive DNS, IDS/IPS, log aggregation
        └──────┬───────┘
               │  flat, trusted LAN
        ┌──────┴───────────────────────┐
        │        managed switch         │
        └──┬──────────┬──────────┬──────┘
           │          │          │
        ┌──┴──┐    ┌──┴──┐    ┌──┴──┐
        │cream│    │skoll│    │auxin│
        │ NAS │    │ obs │    │ TBD │
        └─────┘    └─────┘    └─────┘
```

Only `limen` touches the WAN. The other three are peers on a single flat LAN —
deliberately trusted, because the security boundary that matters is the WAN edge,
not host-to-host. (See *design principles* below.)

## Design principles

**One gateway, everything behind it.** A single node owns routing, firewalling,
DNS, and VPN egress. That concentrates the security-relevant config in one place
and keeps the other nodes simple — they're just services on a LAN.

**Tunnel-or-drop egress.** All client traffic leaves through a VPN tunnel. The
kill switch isn't a feature toggle in the VPN client — it's the *structure* of
the firewall: the forward chain only permits egress via the tunnel interface, so
if the tunnel is down, traffic has nowhere to go. Fail-closed by construction.

**Visibility over least-privilege, inside the LAN.** On a trusted home network,
the scarce resource is insight, not isolation. Nodes carry generous read access
and ship metrics and logs freely. Hardening effort is spent on the WAN edge,
where it counts, not on locking peers away from each other.

**Reproducible from bare metal.** Every node is described in Ansible. A node can
be wiped and reflashed and come back with the same identity and the same address,
because addressing is pinned by hardware (DHCP reservations keyed to each NIC),
not hand-configured per host. Reflash, re-run the playbook, done.

**Idempotent convergence.** Roles are written to converge from *any* prior state,
not just a clean image — re-running changes nothing once the system matches the
desired state. This is harder than it sounds (see the
[WiFi failover build log](../log/2026-06-wifi-failover.md) for a war story) but
it's what makes the fleet trustworthy to re-apply at any time.

**Caching and self-sufficiency.** A node on the LAN serves a package cache and an
internal image registry, so rebuilds don't hammer the internet and the fleet
keeps working through upstream hiccups. (See [NAS & caching](nas-caching.md).)

## Build order

Dependencies dictate sequence, not preference:

1. **Gateway** — networking foundation everything else needs.
2. **NAS / caching** — storage and the package/image caches that speed up the rest.
3. **Observability** — last, so there are already targets to scrape and logs to ship.
4. **Free agent** — role still being decided.
