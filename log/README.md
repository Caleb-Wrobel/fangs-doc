# Build log

Dated entries on what got built, what fought back, and what I'd tell past me.
Newest first.

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
