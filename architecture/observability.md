# Observability

Two pillars: **metrics** (what's happening now, numerically) and **logs** (what
happened, in words). Both are fleet-wide and both land somewhere durable.

## Metrics

- **node_exporter** runs on every node, exposing host metrics (CPU, memory, disk,
  network, and pressure-stall information).
- **Prometheus** runs on the observability node and scrapes all four hosts.
- **Grafana** renders it, and runs as a **kiosk on a 7″ touchscreen** wired to the
  observability node — a literal always-on wall display for the fleet.

### Pressure Stall Information

Every node reports **PSI** (pressure-stall information) — the kernel's measure of
how much real work is being delayed waiting on CPU, memory, or IO. It's a better
"is this box actually struggling?" signal than load average on small hardware,
and getting it consistent across the fleet meant making sure every node had it
enabled and had rebooted into it.

## Logs

- **Grafana Alloy** runs on every node, reads the systemd journal, and ships it to
  **Loki** on the gateway.
- **Loki** keeps roughly a week of logs and is queryable from Grafana alongside the
  metrics, so a dashboard panel and the log lines behind it sit side by side.
- **Nightly backup:** the NAS pulls Loki's data once a night, so a gateway reflash
  doesn't lose the log history.

### Two lessons worth keeping

**Label at the source.** To get a useful `{unit=...}` label on journal logs, the
relabeling has to happen on the *journal source* stage — a later, downstream
relabel can't see the journal's internal fields, because they've already been
dropped by then. Order matters in a logging pipeline.

**Know where your data actually lives.** Loki was quietly writing to a temp
directory that a reboot wipes — so "a week of retention" was really "until the
next reboot." Pointing it at persistent storage (and configuring the deletion
store that retention actually needs) fixed it. The takeaway: verify persistence
empirically, don't assume a default is durable.

## Reaching the dashboards

Grafana isn't exposed on its raw host:port. It's fronted by the
[reverse proxy](tls-proxy.md): from anywhere on the LAN you browse
`https://grafana.fangs.internal`, the gateway terminates TLS with the internal CA
and proxies to Grafana, with Grafana's own auth still in front. Clean padlock, no
port numbers to remember.
