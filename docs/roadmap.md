# Roadmap & open questions

The noodling half of the project — where things are headed, what's undecided, and
the ideas worth chewing on while away from the keyboard.

## Near-term, fairly decided

- **An off-site backup** (built, awaiting its first live run). Every backup the fleet keeps
  today is one hop from the NAS and inside the same building. The next copy goes
  off-premises to a free-tier object store, encrypted client-side before it leaves so the
  provider never holds plaintext: database dumps, the forge, the dashboard server's own
  state, and the full long-horizon metrics store. Measured before designed — the whole set
  turned out to be about 14 GB, not the 25–70 GB guessed, so it fits free with no trimming.
  Runs from the NAS, where the local backups already gather, memory-capped to live within
  its 1 GB. The repository ships *mutable* on purpose: a
  write-once lock would block pruning and bust the free quota while the pipeline is still
  unproven, so tamper-resistance is a follow-up once it has earned trust.
- **A witness that looks *in*** (designed, not built). The fleet's two outside-in checks —
  the third-party uptime ping and the off-fleet watcher — both only prove *the gateway can
  still phone home*. A dead DNS resolver or a crashed dashboard server leaves both green.
  The off-fleet box, already on the overlay, will actively resolve a name and fetch a real
  page through the tunnel, paging on its own path if either fails.
- **Finish moving into the forge.** The forge is the origin now, but four loose ends
  remain: its CI runner is online but not yet running real jobs (label and tooling
  mismatch); its database isn't in the nightly dump yet; the AI/data node's read-only
  mirror — the one the memory tools read — still pulls from the old origin, so it stopped
  seeing new commits at the cutover; and the old bare-repo origin is still standing as a
  rollback path until those are verified.
- **Auth gate in front of the reverse proxy.** Today services rely on their own
  auth behind the proxy. A single sign-on / forward-auth layer at the proxy would
  let new services be protected by default instead of each rolling their own.
- **Document the dry-run convention.** Two of this thread's three parts have landed:
  **`ansible-lint`** is enforced (a pinned `production` profile plus a pre-commit gate),
  and the fleet has passed a **zero-changes idempotency baseline** (bar two documented
  exceptions). What's left is *writing the convention down* — a short doc stating every
  role must be safe in check mode and re-run to zero changes (see the
  [WiFi failover log](log/2026-06-wifi-failover.md) for why that isn't a given), as the
  bar new roles are held to.
- **Canonical per-node imager config.** One reproducible image definition per node
  type, so any node can be reflashed to an identical starting point without
  hand-tuning.

## The free-agent node

The fourth node (a 16 GB Pi 5) has its role now: **local AI inference** (see
[Local AI](architecture/local-ai.md) and the [build log](log/2026-06-local-ai.md)). It
serves small language models on-device — a general chat model, a coding model, a fast
lightweight one, and an embedding model — behind the gateway's proxy, with a browser chat
front-end, reachable from the laptop over an SSH tunnel. Lighter AI tasks now run in-house
instead of on a cloud API.

Still on its list:

- ✅ **Reach it from the open internet** — shipped as a self-hosted WireGuard road-warrior on
  the gateway (2026-07-08), then **redesigned (2026-08-20)** so the gateway no longer accepts any
  inbound connection for this at all — the zero-inbound-port ideal, reached a different way than
  first planned. The off-fleet watcher box (fixed address) is now the one fixed point everything
  dials out to, gateway included; see the [build log](log/2026-08-wireguard-hub.md). Split-tunnel,
  DNS over the gateway's resolver, unchanged.
- **Authentication on the raw inference API** — the chat UI has its own login; the API itself
  is currently open on the trusted LAN.

## Things to actually noodle on

- **Git as the fleet's nervous system.** Now that the true git source lives *on* the fleet (see
  [Bringing the origin home](log/2026-07-fangs-git-origin.md)), a family of ideas gets cheap: pushing
  in-flight branches so the memory can reason about *unshipped* work, not just landed main; a heavier
  local clone on the GPU node for on-device search; and the far-off north star — the fleet applying
  *itself* from its own git instead of a human running the playbook (push-config → pull-gitops). One
  member of the family has since left the list and shipped — a real **self-hosted web forge** now runs
  on the NAS and is the fleet's origin (see *done recently*) — and a second, drift detection, has
  its first slice landed: a precise definition of what *one* drift event is, proven against a real
  dry run. Remembering drift across runs, so a new drift can be told from a repeat, is the next
  piece. Each is still a standalone piece; the set is only starting to look like a *direction*
  rather than a pile.
- **A relocatable observability "satellite."** The dashboards node is now WiFi-
  capable with failover. Could it become a *wireless-first*, relocatable node —
  carry the touchscreen to another room and have it just work — rather than being
  tethered to the switch? The AP and the failover plumbing already point this way.
- **TLS trust ergonomics.** Importing the fleet CA per workstation works but is a
  manual step that's easy to forget (and looks like a broken deploy when skipped).
  Is there a smoother trust-distribution story for a home network?
- **Split-tunnel egress policy.** Right now everything goes through the VPN tunnel.
  A future milestone is policy routing so *selected* traffic can take the direct
  path — useful for things that misbehave behind a VPN — without weakening the
  fail-closed default.
- **Profile the two-agent overhead.** Every node runs both node_exporter and Alloy;
  Alloy could in principle do both jobs, and collapsing to one agent would shed
  moving parts on the smallest hardware. The fleet keeps them separate for
  compatibility and isolation (see
  [Observability](architecture/observability.md#why-node_exporter-and-alloy-stay-separate)),
  on the *assumption* that carrying both is cheap — but that assumption is
  unmeasured. Worth profiling the real CPU/memory cost on a 1 GB node before
  treating it as settled.

## Done recently

- ✅ **The couch-room board learns the next few hours** — the living-room kiosk's forecast
  moved from the national weather service's twice-daily text outlook to an hourly
  **now / +3h / +6h** look-ahead, because the people who glance at it do so on the way out
  the door. It also gained a **severe-weather panel** that takes over the board's decorative
  corner only while an alert is active, with a fixed priority ladder so a distant watch never
  outranks weather at home. A test switch injects a synthetic alert through the *real*
  classification path rather than around it, so all three tiers were proven live before
  landing.
- ✅ **What counts as drifted** — the first slice of drift detection, scoped down twice to the
  smallest provable atom: define a drift event with two independent identity tiers and prove
  both are derivable from a real dry run. A deliberately introduced, then reverted change on
  a live node was the proof ([log](log/2026-08-drift-check.md)).
- ✅ **A self-hosted web forge, on the smallest node in the fleet** — the "real web forge"
  that sat in the git-nervous-system noodle above is now running on the NAS and is the
  fleet's **authoritative git origin**: web UI, pull requests, issues, and CI, backed by the
  Postgres data layer rather than its own embedded database, with the full branch history
  mirrored in and verified against a fresh clone. GitHub stays an offsite copy, now fed by
  the forge's own push mirror (a key the forge minted itself; only the public half left it).
  Repointing the origin quietly broke three things on the workstation — a branch still
  tracking the retired repo, so plain pushes *succeeded* into the wrong place; most branches
  with no upstream at all; and the local commit hooks silently switched off — which is the
  small permanent lesson: after moving `origin`, check where it points, what each branch
  tracks, and whether the offsite copy is attached to the path pushes actually take.
  It began as a **disposable spike** deployed specifically to be thrown away — the question
  was only whether a 1 GB board could hold it — and the measured answer was good enough that
  the throwaway became the build ([spike](log/2026-08-forgejo-spike.md)). Four bugs only a
  running instance could surface, none of which a dry run would ever have caught.
- ✅ **The doc-site question, answered by building it** — this notebook used to ask, right
  here in this list, where a doc-site should live and whether the pile was big enough to
  warrant one. It's been a **MkDocs (Material) site on GitHub Pages** since 2026-06-20, built
  and deployed by CI on every push, with a nav sidebar, full-text search, and per-page
  revision dates. The Markdown never changed, which was the whole bet — the site is purely
  additive, and every page still reads fine as plain text.
- ✅ **Small-screen kiosk legibility — closed by dropping the premise.** The open question was
  *which scaling lever* densifies a 7″ 800×480 panel: a larger logical resolution, an
  output-level scale, or page zoom. It was never answered, because it stopped mattering.
  Instead of scaling a board built for a desktop, the panel got **its own board, designed for
  its own viewport** and for an audience that isn't debugging anything
  ([the couch-room redesign](log/2026-08-couch-room-redesign.md)). The earlier finding still
  stands as recorded — a browser device-scale flag shrinks the whole window under this
  compositor instead of densifying content — it just no longer blocks anything. The mirror
  image of the "sound execution of an unsound premise" lesson that produced it: sometimes the
  fix for a stuck question is to stop needing the answer.
- ✅ **Six placeholder credentials replaced** — the file-share password, the dashboard admin
  password and four database role passwords were all still the literal placeholder string from the
  example secrets file. Never weak exactly; never *chosen*. All six are now real random values,
  verified at the server by logging in with the new one and confirming the old one is refused. The
  useful part was the discovery that **none of them rotated by editing the stored value** — every
  one needed a separate imperative command, and the dashboard server's rotation reported success
  while changing nothing at all. That finding is now the requirements document for the rotation
  engine, which has to record rotations it *verified* rather than ones a green run believes it
  performed ([log](log/2026-07-credential-rotation.md)).
- ✅ **Backups encrypted at rest, and the shares narrowed** — two third-party API keys were sitting
  in plaintext inside the nightly database backups, reachable over the network. The dumps are now
  encrypted to a key whose private half is deliberately *not* on the machine that stores them, so
  the storage node writes backups it cannot read; the restore was proven end-to-end by comparing
  row counts, not by trusting an exit code. The bigger finding was that the file share everyone
  worries about was the *stronger* of two doors — a second, unauthenticated export served the same
  tree — so both were re-scoped to a dedicated subdirectory instead of the drive root, which turned
  out to require moving no data at all. Both keys were then rotated at their sources and the old
  plaintext backups destroyed, in that order, because rotation is the only real revocation. Second
  piece of the **credential-hygiene** effort ([log](log/2026-07-secrets-at-rest.md)).
- ✅ **Key-only SSH across the fleet** — the shared login password is gone from the network. It was
  a second, never-rotated path into an account that is root in all but name, on every node, while a
  comment in the code claimed the opposite had been true for months. Now enforced rather than
  assumed, with a randomized console-only password left behind so a hands-on recovery visit is still
  possible. First piece of a new **credential-hygiene** effort whose organizing idea is that rotation
  is the *fallback* — prefer removing a credential, or making it expire on its own, over building
  something to rotate it ([log](log/2026-07-key-only-ssh.md)).
- ✅ A full-fleet convergence run, and the three bugs it surfaced — a wedged package upgrade that
  broke *silently* (service still serving, health green, nothing paged) while stopping the whole
  fleet from converging; a passwordless-sudo rule that was root-only by omission, hidden for months
  behind a guard that meant the task never ran; and two tasks on the GPU node that had been undoing
  each other every single run, rebuilding kernel modules from source each time
  ([log](log/2026-07-convergence-audit.md)).
- ✅ **Registry authentication** (the item that used to sit above, in "near-term") — the local
  image registry now requires a fleet-CA **client certificate** per node (mTLS at the reverse
  proxy) instead of running open on the trusted LAN; a request with no cert never completes the
  TLS handshake at all. Machine identity, not a login form — matching how everything else here
  authenticates node-to-node.
- ✅ A witness that watches from outside every failure domain the fleet has: a minimal instance
  on a public cloud provider's free tier, reachable only by its own public name, accepts a
  heartbeat the gateway pushes out over its normal egress and pages independently if that
  heartbeat ever stops — with a third-party uptime check watching *that* watcher in turn. It only
  became load-bearing once its TLS front and its own watch-itself logic were folded into one
  portable pod spec; killing the watcher container to prove the point surfaced the sharp
  lesson that a played pod spec isn't a cluster — a single crash needs a page, not a self-heal
  ([log](log/2026-07-embassy-sidecar.md)).
- ✅ Dashboard drift, cured structurally: shared panels across every board are now stamped at
  build time from one canonical source instead of hand-copied, so a fix lands everywhere at
  once. Four new boards landed alongside it (services, storage, links, DNS), and the topology
  board learned that a sleeping node is not a dead one ([log](log/2026-07-dashboard-consolidation.md)).
- ✅ Network-layer visibility on the gateway, the repo's oldest open promise: passive traffic
  transcription (not inspection) on the LAN bridge, logged and queryable beside everything else.
  Paid for itself within hours, catching an un-telemetried device on the network and a kiosk
  browser quietly phoning home far more than expected
  ([log](log/2026-07-zeek-flow-visibility.md)).
- ✅ A fifth node joined as **summoned muscle**: an aging amd64 desktop with a GPU, asleep in
  suspend-to-RAM until woken by a Wake-on-LAN packet from the AI/data node (~6 s round trip,
  memory preserved). The first non-Pi, non-ARM member surfaced a genuinely new monitoring
  question — a node *designed* to be off looks identical to a dead one, so uptime alone can't be
  the health signal for it ([log](log/2026-07-morel-wake-work-sleep.md)).
- ✅ A third noun for the feature pipeline: **themes**, standing cross-cutting concerns
  (`persistence`, `security`, …) that never finish, sitting orthogonal to the epic → feature
  hierarchy that actually ships things. The point is two machine-answerable questions: what's
  open toward a given theme, and what's already been done under it when something breaks
  ([log](log/2026-07-workflow-themes.md)).
- ✅ The fleet's first multi-part *epic*: a chaos-engineering harness that injects known,
  self-reverting faults into two leaf nodes only (never the gateway or the AI/data node) to
  prove alerts actually fire and nodes actually recover — treating a blind spot ("broke it,
  nothing paged") as a first-class finding, not a footnote ([log](log/2026-06-chaos-stack.md)).
- ✅ The fleet's git source of truth, brought in-house (since superseded by the forge, above): the NAS
  became the **authoritative git origin** (a bare repo served over its own SSH by a `git-shell`-confined service account), with GitHub demoted
  to an offsite **backup** that can only ever add refs, never delete them. The AI/data node's mirror —
  which the memory tools read — now pulls from an always-current LAN source, **read-only by
  construction** (a forced fetch-only command; proven it can pull and cannot push), instead of depending
  on a human pushing to a third party ([log](log/2026-07-fangs-git-origin.md)).
- ✅ RAG over the fleet's own telemetry: a local command-line tool that embeds the **notable**
  log lines the cluster already collects into the pgvector store, then answers plain-English
  questions — *"what's been failing on the NAS?"* — grounded in the retrieved logs, with
  citations, entirely on local hardware. The data layer's second retrieval consumer. A
  deliberately **local** interface (not a chat bot) keeps the fleet strictly outbound-only; a
  word-boundary filter that silently matched nothing — a bug a dry-run couldn't see, only a live
  run could — was the lesson ([log](log/2026-06-telemetry-rag.md)).
- ✅ Durable NVMe storage for the stateful nodes: the AI/data node and the gateway now
  keep their state (database, metrics, logs) on real SSD instead of the SD card —
  reboot-verified, with the gateway's data plane **gated** so a missing disk fails safe
  rather than silently starting an empty store. The earlier "enclosure-or-drive fault"
  that parked this turned out to be **user error, not hardware** — the same drive runs
  fine on the board's native PCIe (the USB-bridge path was the red herring; corrected
  in the [storage debug log](log/2026-06-storage-enclosure-debug.md)). Remaining: the
  stateless kiosk node was hardened with a read-only root — then **retired** (2026-07-05): the
  toggle-and-reboot friction outweighed the benefit for a node that reflashes in ~20 minutes, so
  reflash-on-death is the strategy instead ([retiring read-only root](log/2026-07-readonly-root-retired.md)).
- ✅ A structured-data layer: Postgres + pgvector on the 16 GB node (rootless container, a
  named volume, and a nightly `pg_dump` pulled to the NAS), built infrastructure-first with the
  schema deferred to its first consumer ([log](log/2026-06-postgres-data-layer.md),
  [architecture](architecture/data-layer.md)).
- ✅ A daily fleet report that comes to you: a morning digest of 24h uptime, outages, heat
  peaks, memory pressure, and error volume, posted to its **own** chat channel — separate from
  real-time alerting so a bulky summary never competes with a page
  ([log](log/2026-06-daily-report.md)).
- ✅ The fleet dashboard as a managed kiosk: the display node, reflashed to the lean OS, now
  drives the 7″ wall display as a resilient, observable **systemd service** that reaches the
  dashboards over the proxy with **anonymous read-only** access — no hand-opened browser, no
  login wall ([log](log/2026-06-kiosk.md)).
- ✅ Re-onboarded the reflashed display node as a managed member — and shook out three latent
  fleet bugs on the way (a package-cache proxy serving error pages the new OS read as "tampered"
  indexes, a failover role that cut its own link, and the clockless-boot landmine)
  ([log](log/2026-06-reflash-onboarding.md)).
- ✅ Fleet alerting that comes to you: Grafana-managed alerts for node heat (before it
  throttles) and a node going dark, delivered as push to a phone via a chat-channel
  webhook — no mail server, outbound-only, nothing new on the WAN
  ([log](log/2026-06-alerting-discord.md)).
- ✅ Tested (and ruled out) running the coding *agent* itself on the node's local models:
  the integration works natively with no translation layer, but CPU **prefill** of a large
  agent prompt is the wall — minutes per turn, not viable interactively. Confirmed what the
  node is for (chat / retrieval / light tasks) and raised the served context window along the
  way ([log](log/2026-06-local-coding-agent.md)).
- ✅ Decided **and built** the off-LAN access story: ruled out the egress VPN's built-in mesh (it
  force-enables a DHCP-breaking vendor firewall), and landed a self-hosted WireGuard road-warrior
  (split-tunnel) on 2026-07-08, replacing the interim SSH tunnel ([log](log/2026-06-remote-access.md)).
  Redesigned 2026-08-20 so the gateway carries **zero** inbound ports for this — see below.
- ✅ Flipped who has to be found for the road-warrior tunnel: the gateway's own address on the
  wider internet drifts (nothing tracked it, and it had already gone stale once), so the gateway
  now dials *out* to the off-fleet watcher box's fixed address instead of accepting inbound
  connections — a net **reduction** in the gateway's attack surface, proven from a genuinely
  external network (cellular, not home WiFi) after one honestly-corrected misdiagnosis along the
  way ([log](log/2026-08-wireguard-hub.md)).
- ✅ Local AI inference on the free-agent node: small LLMs (general / coding / fast /
  embeddings) with a browser chat front-end, fronted by the proxy and reachable from the
  laptop over an SSH tunnel ([log](log/2026-06-local-ai.md)).
- ✅ Onboarded the free-agent node as a managed, observable fleet member — and shook
  out three latent infra bugs on the way ([log](log/2026-06-auxin-onboarding.md)).
- ✅ WiFi failover, fleet-wide and physically verified
  ([log](log/2026-06-wifi-failover.md)).
- ✅ Centralized logs (Alloy → Loki) with nightly backup to the NAS, and a fix for
  silently-non-persistent storage.
- ✅ Reverse proxy + internal CA: clean `https://*.fangs.internal` names.
- ✅ Pressure-stall metrics live across the whole fleet.
