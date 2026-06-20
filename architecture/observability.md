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

### Thermals

node_exporter also exposes each node's **SoC temperature**, charted on a fleet
thermals dashboard. On small-board computers with modest cooling, a creeping
temperature is an early sign of a failing fan or blocked airflow — so it's both a
panel and the basis for a heat [alert](#alerting).

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

## Alerting

Dashboards tell you something's wrong *if you happen to be looking*. Alerts come
find you. The fleet's alerts are **Grafana-managed** — defined as code, evaluated by
Grafana itself, and delivered to a phone.

**Why Grafana-managed, rather than the metrics system's own alerting.** The
alternative is to write alert rules down in Prometheus and route them through a
separate notifier. The fleet keeps alerting *in Grafana* on purpose: a Grafana alert
targets a **data source**, not a particular collector. If the way metrics are
gathered ever changes underneath it, the alert keeps working — you repoint the data
source and the rule is untouched. It also keeps the graph and the alert built on it
in one place.

**What fires today:**

- **Heat.** Each node's SoC temperature, alerting on a sustained climb *before* the
  hardware would start throttling — early warning for a failing fan or blocked
  airflow, not a post-mortem.
- **A node going dark.** If a host stops being scraped for long enough, that's an
  outage. This rule was motivated by a real incident: a node dropped off and
  *nothing said so* — the monitoring fleet couldn't report its own member missing.
  It's deliberately **slow to fire** (a sustained outage, not a blip), because one
  node rides a flaky wireless link and a brief drop there isn't worth a 3 a.m. ping.

**A subtlety worth stating: don't alert on *absence* the way you alert on *badness*.**
A node that's genuinely down still reports a clear "I'm down" reading the rule can
see. "No data at all" is a *different* condition — the collector is gone, or the
target never existed — and treating missing data as an automatic page means a
flapping link spams you. The down-rule treats missing data as "fine," because a true
outage shows up as data, not as silence.

## Delivery: push, not pull

Alerts go to a **chat-channel webhook** — a private channel that pings a phone. Three
things make this a good fit for a home fleet:

- **No mail server.** A webhook is a single outbound HTTPS request to a URL: no SMTP,
  no deliverability tuning, nothing extra to host.
- **Outbound only.** The notification leaves a node, rides the gateway's VPN egress,
  and reaches the chat service over HTTPS. Nothing new is published on the WAN — the
  same fail-closed posture as the rest of the fleet.
- **The webhook URL is a secret.** Anyone holding it can post to the channel, so it
  lives encrypted in the vault, is written to disk with restrictive permissions, and
  is kept out of logs. It's a *bearer* credential — treat it like a password, and
  rotate it if it's ever exposed.

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
