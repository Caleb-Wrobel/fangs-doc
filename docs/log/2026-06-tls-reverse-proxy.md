# 2026-06 — Internal CA & reverse proxy

**Goal:** stop reaching internal services by `host:port` over plain HTTP with a
self-signed click-through, and instead browse a real `https://name.fangs.internal`
with a clean padlock — from anywhere on the LAN, no tunnel, no port to remember.
One internal certificate authority, one reverse proxy, and adding a service should
cost a single line.

The end state is written up in [TLS & reverse proxy](../architecture/tls-proxy.md);
this is the log of how it actually came together and where it bit.

## The shape of the solution

- **An internal CA via mkcert.** A single fleet root CA signs **one wildcard cert**
  for `*.fangs.internal`. Fleet nodes trust the CA automatically (the base role
  installs it); a workstation trusts it once, by hand, and from then on every
  service is clean.
- **nginx on the gateway** terminates TLS for `*.fangs.internal` and proxies to
  the right backend.
- **One declarative list** of `name → backend` drives *both* the proxy and the DNS
  resolver. Append a line, run the playbook, and `https://thing.fangs.internal`
  both resolves and proxies — no hand-written vhost, no hand-written DNS record.

## Decision — flat names, one wildcard

Early temptation was per-service certs and nested names. I went the other way:
**flat, one-level names under `fangs.internal`**, all covered by a *single*
wildcard cert. A wildcard doesn't match multiple label levels, so flat names keep
every service inside one cert and one resolver entry. Nested subdomains only earn
their keep if a service needs to mint subdomains dynamically — none here do. Keep
it flat until something forces otherwise.

## The thing that makes it pleasant — and the gotcha that comes with it

The payoff is that one declaration feeds two systems. The price is that **a deploy
has to apply both halves**. Update the proxy config alone and the resolver still
answers `NXDOMAIN` for the new name — the backend is up, nginx knows the vhost,
and the browser still can't find it because DNS was never told. The two are a
*pair*; rolling out one without the other produces a service that is simultaneously
"running" and "doesn't exist." Worth a checklist line: new service = proxy **and**
DNS, same run.

## Surprise — a fresh daemon answers on the wrong door

First bring-up of the service unit looked healthy but didn't behave. A plain
*reload* of a daemon that had just been (re)installed picked up a stale view of its
own config — it was effectively listening at the wrong configuration. A *restart*,
not a reload, was what bound it to the intended state. Lesson filed: **reload is an
optimization that assumes a correctly-running daemon; on first install, restart.**

## Deliberately LAN-only

The proxy listens on the **LAN side only** — the gateway's LAN address plus
loopback — and is *never* published on the WAN edge. The gateway is the boundary
that matters, and this listener sits firmly behind it:

- From the LAN: browse `https://grafana.fangs.internal` directly.
- From off-LAN: there's no route by design. Join the network, or tunnel in through
  the gateway.

A catch-all server block answers any hostname it doesn't recognize with a hard
close, so the proxy only ever serves names it actually knows about.

## The rough edge that looks like a bug

A workstation that hasn't imported the fleet CA reaches the service fine but shows
"not secure." The *connection* works; the *trust* doesn't. It's a one-time,
per-workstation trust step — but it's invisible until you hit it, and it reads
exactly like a broken deploy. Half of "is the proxy working?" turned out to be "did
this laptop ever trust the CA?"

## What I'd tell past me

- **Make the easy thing one line, but remember it fans out.** A single source of
  truth feeding two systems is the whole win — just never apply half of it.
- **Reload assumes a healthy daemon.** On first install or a config-shape change,
  restart and stop guessing.
- **"Not secure" in the browser is usually a client-trust problem, not a server
  problem.** Check whether the workstation imported the CA before suspecting the
  proxy.
- **Bind internal listeners to the inside.** LAN-address-plus-loopback, never the
  WAN edge, is the cheapest way to guarantee a service can't leak outward.
