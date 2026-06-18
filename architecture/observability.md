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

## Why node_exporter and Alloy stay separate

There are two agents on every node — **node_exporter** for metrics and **Alloy**
for logs — and that's a deliberate choice, because it could plausibly be one.
Alloy is capable of collecting host metrics itself (it can run the same
node-exporter collectors internally and scrape them), so folding metrics into
Alloy and dropping node_exporter would mean **fewer moving pieces on
resource-constrained nodes**. That's a real pull on hardware this small, and it's
the obvious consolidation to reach for.

The fleet keeps them distinct anyway, for three reasons:

1. **Ecosystem compatibility.** node_exporter is the de-facto standard for host
   metrics. The huge body of off-the-shelf Grafana dashboards and Prometheus alert
   rules assume *its* exact metric names and labels — point them at a real
   node_exporter and they tend to work unmodified. Re-exposing the same data
   through a different agent invites subtle naming mismatches that turn "import a
   community dashboard" into "debug why three panels are empty."
2. **Separation of concerns.** Log shipping and metrics exposition are different
   jobs with different failure modes. Keeping them in separate processes means a
   problem in the logging pipeline can't take host metrics down with it (and vice
   versa), and each can be reasoned about, restarted, or replaced on its own.
3. **The cost of running both looks acceptable.** node_exporter is lightweight, so
   carrying it *alongside* Alloy shouldn't meaningfully burden even the smallest
   node. This is the softest of the three reasons — it's a judgement, not a
   measurement — so it's flagged as **worth actually profiling someday**: if the
   two-agent overhead ever turns out to matter on a 1 GB node, the consolidation
   above is the lever to pull, and reasons (1) and (2) become the price of pulling
   it.

The short version: the redundancy buys compatibility and isolation cheaply today,
and the day it stops being cheap is a measurement question left open on the
[roadmap](../roadmap.md).

## Reaching the dashboards

Grafana isn't exposed on its raw host:port. It's fronted by the
[reverse proxy](tls-proxy.md): from anywhere on the LAN you browse
`https://grafana.fangs.internal`, the gateway terminates TLS with the internal CA
and proxies to Grafana, with Grafana's own auth still in front. Clean padlock, no
port numbers to remember.
