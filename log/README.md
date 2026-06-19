# Build log

Dated entries on what got built, what fought back, and what I'd tell past me.
Newest first.

- **2026-06** — [Reaching in from outside](2026-06-remote-access.md): how to use
  internal services (the local AI especially) from a machine off the home LAN.
  The clever shortcut — the VPN's built-in mesh overlay — turned out to be welded to
  a vendor firewall that silently eats LAN DHCP, and a read-back assertion caught it
  before it shipped. The mesh stays off for two reasons now, not one.
- **2026-06** — [The free agent gets a job: local LLM inference](2026-06-local-ai.md):
  small models served on-device with a chat UI, so lighter AI tasks stay off the cloud.
  Three lessons on the way — memory (not disk) is the model ceiling, a magic variable that
  vanished in a privilege-escalation context, and a browser that won't trust what the system
  trusts.
- **2026-06** — [Onboarding the free agent](2026-06-auxin-onboarding.md): bringing
  the fourth node in was trivial (membership is one inherited baseline) — but a fresh
  node exercising old infrastructure flushed out three latent bugs: a package cache
  bound to loopback after a cold boot, cache dirs unwritable from a pre-reflash owner,
  and first-boot provisioning silently rewriting the hosts file on every boot.
- **2026-06** — [Pressure-stall metrics, fleet-wide](2026-06-psi-fleetwide.md):
  PSI on every node so one dashboard shows which box is actually straining. A
  one-flag feature that touched the bootloader — including a whitespace edge case
  that appended a second line to `cmdline.txt` and nearly cost a node its boot.
- **2026-06** — [WiFi failover](2026-06-wifi-failover.md): wired-primary /
  WiFi-standby with IP held across the flip. A short job that became a tour of
  netplan/NetworkManager idempotency, single-radio AP constraints, and a
  failback address-conflict bug.
- **2026-06** — [Centralized logging](2026-06-centralized-logging.md): every
  node's journal shipped to Loki on the gateway, queryable beside the metrics,
  backed up nightly to the NAS. Two reboots' worth of lessons: a "retention"
  window that lived on a tmpfs, and why journal labels have to be set at the
  source.
- **2026-06** — [Internal CA & reverse proxy](2026-06-tls-reverse-proxy.md): a
  clean `https://name.fangs.internal` for every service via one mkcert CA and one
  nginx proxy, with services declared a line at a time. Where it bit:
  proxy-and-DNS as an inseparable pair, reload-vs-restart on first install, and a
  trust step that looks like a broken deploy.
