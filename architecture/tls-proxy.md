# TLS & reverse proxy

Internal services get a real `https://name.fangs.internal` with a clean padlock —
no port numbers, no self-signed-cert click-through — using a small internal PKI
plus a single reverse proxy on the gateway.

## Internal PKI with mkcert

The fleet runs its own certificate authority via **mkcert**. A single fleet root
CA signs a wildcard certificate for `*.fangs.internal`. Trust is established once:

- **Fleet nodes** trust the CA automatically (the base role installs it).
- **A workstation** trusts the CA once, manually, and from then on every fangs
  service shows a clean padlock.

The root CA certificate is public-safe and lives in the (private) infra repo; the
CA signing key and the leaf cert/key live encrypted and never leave the vault.

## One proxy, declarative services

**nginx** on the gateway terminates TLS for `*.fangs.internal` and proxies to the
right backend. The key property is that adding a service is **one line**: a
service's name and backend are declared once in a single list, and both the proxy
*and* the DNS resolver read from that same list. Append a line, run the playbook,
and the new `https://thing.fangs.internal` resolves and proxies — no per-service
nginx vhost or DNS record to hand-write.

> **Pairing gotcha.** Because one declaration feeds two systems, a deploy has to
> apply *both* the proxy config and the DNS config. Update the proxy alone and the
> resolver still returns NXDOMAIN for the new name — the service is up but
> unreachable by name.

## Deliberately LAN-only

The proxy listens on the **LAN side only** (the gateway's LAN address plus
loopback). The gateway is the WAN edge, and this listener is *never* published
there. So:

- From the LAN, browse `https://grafana.fangs.internal` directly — no tunnel.
- From off-LAN, there's no direct route by design; you join the network or tunnel
  in through the gateway.

A catch-all server block answers unknown hostnames with a hard close, so the proxy
only ever serves names it actually knows.

## Known rough edge

A workstation that hasn't imported the fleet CA yet will reach a service but show
"not secure" — the connection works, the trust doesn't. It's a per-workstation
one-time trust step, not a server problem, but it's an easy one to trip over and
mistake for a broken deploy.
