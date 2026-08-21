# Build log

Dated entries on what got built, what fought back, and what I'd tell past me.
Newest first.

- **2026-08** — [The road that never left the house](2026-08-wireguard-hub.md): the off-fleet
  watcher box came back for a different reason — the gateway's own address on the wider internet
  drifts, and nothing had ever tracked it. The fix flips who has to be found: every device,
  gateway included, now dials *out* to the box's fixed address instead of anyone dialing in to the
  gateway, which nets the gateway a **smaller** attack surface, not a bigger one. Three real bugs
  on the way — a network manager that was never running, a private key stored under a name that
  collided with a more generic one and silently stole an identity, a route nobody actually wrote —
  and one mistake corrected in public: a symptom on my own laptop, at home, looked identical to a
  provider issue I'd diagnosed once before, and I said so with more confidence than I'd earned. It
  was a loop through my own router, never the provider, and someone else in the house caught it.
  The real proof came from a phone on cellular data, nowhere near the house, loading a dashboard
  on the first try.
- **2026-07** — [The rotation that rotated nothing](2026-07-credential-rotation.md): six live
  credentials were the literal placeholder string from the example secrets file — never weak, never
  *chosen*. Replacing them was meant to be an afternoon of typing, and instead became the
  requirements document for the rotation engine, because **not one of the six rotated the way the
  configuration management implied.** Guarded "create if absent" statements, an environment variable
  read only at first initialization, an idempotence check that by design can never run twice: every
  guard correct, and collectively a system that can express "this credential should exist" but not
  "this credential should now be different." The centrepiece is the dashboard server, which rewrote
  its config, restarted, reported the task changed — and kept accepting the old password (new → 401,
  old → 200), with nothing in a green idempotent run able to tell those states apart. The keeper: a
  run reporting "changed" is evidence a *file* changed, not that the *world* did — so verify the
  credential, and require the old one to fail.
- **2026-07** — [The locked door beside the open one](2026-07-secrets-at-rest.md): two
  third-party API keys were sitting in plaintext inside the nightly database backups, because the
  application storing them doesn't encrypt config values and a binary dump format is compression,
  not encryption. The plan was to move the backup directory out of the password-protected file
  share — until measuring found a **second** export serving the same tree with **no credential at
  all**, making the share I meant to fix the *stronger* of two doors. Fixing only it would have
  closed nothing while feeling like completion. The eventual fix was cheaper as well as broader:
  the drive root held no user data at all, so both shares were re-scoped to an empty subdirectory
  and nothing moved. Dumps are now encrypted to a key whose private half is deliberately absent
  from the machine holding them, the restore was proven by **row count** rather than exit code, and
  rotation was deliberately sequenced *last* — because nothing un-exposes what's already written,
  and rotation is the only real revocation. The keeper: enumerate every protocol serving a path,
  and find the version of a check that fails today instead of in two weeks.
- **2026-07** — [Three bugs behind a green run](2026-07-convergence-audit.md): running the
  *whole* configuration playbook against the *whole* fleet — something a workflow built on narrow,
  fast, tagged slices almost never does. The run found a blocker; the routine dry run *afterwards*
  found the two real bugs. A dashboard package upgrade wedged because its post-install step moves a
  directory onto what is now a separate disk and the destination already existed — and it broke
  **silently**: the old binary kept serving, health returned 200, nothing paged, while one wedged
  package in the first play stopped the entire fleet converging. A passwordless-sudo rule written
  without a run-as clause meant *root only*, so escalating to the locked-down git account had always
  demanded a password — hidden for months because a create-if-missing guard meant the task never did
  work, so nobody noticed it never could. And on the GPU node, two tasks were undoing each other every
  run: the vendor ships the same package names the purge step removes, so ~150 packages churned and
  the kernel module rebuilt from source, every run, forever. The keeper: hold the "a converged fleet
  reports zero changes" bar and mean it — a stubborn changed line is not cosmetic drift.
- **2026-07** — [The claim the code never made](2026-07-key-only-ssh.md): a survey of open-source
  credential-rotation options that ended somewhere else — the fleet's biggest exposure needed no
  rotation machinery at all. A comment justifying passwordless `sudo` asserted the admin account
  "reaches every node over key-only SSH"; nothing had ever enforced it, and every node was in fact
  still accepting passwords. The reframe that came out of it: **rotation is the fallback, not the
  goal** — eliminate the credential, or make it expire unattended, before you build something to
  rotate it on a schedule; and name the third of any vault that *nothing* can rotate (third-party
  bearer tokens with no API), because tools that claim to "rotate your secrets" quietly ignore them.
  Three sharp edges: the hardening file's *number* is load-bearing (first-match-wins, lexical order),
  disabling password auth does nothing if keyboard-interactive is left to reopen the same door through
  PAM, and the account gets a random password rather than being locked — because with network logins
  gone, that password is the only way back in at a physical console, and one node is already known to
  need hands-on visits.
- **2026-07** — [The switch nobody flipped](2026-07-gateway-rtc.md): fitting the gateway node
  with a battery-backed real-time clock, so it can keep accurate time across a cold boot with no
  network — and three rounds of false-positive "it works" readings before the real test caught the
  fault. Every quick check available lied for a different reason: the clock utility wasn't even
  installed, the RTC device file exists whether or not a battery is attached, and a clean shutdown
  never actually removes the power the clock domain was riding on. The test that finally worked
  reads the battery rail directly and checks what the RTC hardware itself reports at the very first
  instant of boot, before NTP gets a chance to paper over the answer. A detour into cell-chemistry
  research confirmed the right part was already fitted — so the fault was neither wiring nor
  chemistry, just a switch molded into the battery holder, left off since day one.
- **2026-07** — [Bringing the origin home](2026-07-fangs-git-origin.md): the fleet's git source of
  truth was off-site — the memory tools all read a mirror that only reflected what a human had pushed
  to GitHub. This makes the **NAS the authoritative git origin** (a bare repo served over its own SSH
  by a `git-shell`-confined account) and demotes GitHub to a best-effort **backup** that can only ever
  add refs, never delete them. Two keys, two authorities: the workstation reads/writes; the AI/data
  node is read-only *by construction* (a forced fetch-only command — proven it can pull and cannot
  push). Three cutover bugs off the happy path — the first fleet role to *become* a locked-down user
  needed an ACL tool nobody had installed; a shared address that only resolved on the serving side; and
  a dry-run that lied about being converged — plus the permanent small lesson: when you've just moved
  where `origin` points, run `git remote -v` before you push.
- **2026-07** — [The room with two guards and no captain](2026-07-embassy-sidecar.md): the off-fleet
  cloud box that watches the fleet from outside every failure domain finally became load-bearing —
  the TLS front and the watcher folded into one pod described by a portable Kubernetes spec, the
  gateway's heartbeat cut over to ping it for real, and the watcher taught to check in on *itself*.
  The pod adopted its old data volumes untouched (the certificate's serial never changed), but killing
  the watcher container proved the sharp lesson: a played pod spec is *not* a cluster — the
  single-host engine honors the spec's shape and not its supervision, so `restartPolicy` and its
  cousins are inert and a crashed watcher is caught by a *page*, not a self-heal. The proof: one
  induced silence, two independent alarms from two independent paths, healed by a single ping.
- **2026-07** — [The memory moves its thinking to the muscle](2026-07-fleet-memory-gpu.md): the
  local "ask the fleet about its own logs" chat generated its answers slowly, on a GPU-less board.
  This routes only the *writing* of the answer to the summoned basement GPU while retrieval stays on
  the always-on node — 7–8× faster. A benchmark overruled the premise: the bigger model doesn't fit
  the card's 4 GB (it spills to CPU and answers worse), so the win is a fully-GPU-resident *small*
  model, not a bigger one. Written as prefer-then-fall-back so a GPU that won't wake makes the answer
  slower, never failed — which quietly makes "is its work getting done?" monitoring the next thing owed.
- **2026-07** — [One die, many doors](2026-07-dashboard-consolidation.md): dashboard drift, cured
  structurally. The engine's native library panels can't be file-provisioned, so shared panels are
  build-time *stamped* from canonical sources by a tiny committed generator; the topology board
  learned that a sleeping node is not a dead one (blue ZZZ, not red DOWN); dynamic boards were held
  to "no query names a host" so the next node appears with zero edits; and four new boards landed —
  services (instantly surfacing a real failed-unit finding), storage with an SD-wear watch, links
  (born showing a genuine WiFi failover), and the UI-built DNS board exported to safety.
- **2026-07** — [The transcriber in the doorway](2026-07-zeek-flow-visibility.md): the repo's
  oldest open promise — network-layer telemetry on the gateway — lands as Zeek transcribing the LAN
  bridge, while the Suricata half is deliberately descoped (a home LAN needs a record, not a judge).
  Native by necessity, lean by choice: the bare core package under a hand-written non-root systemd
  unit, JSON logs on the durable NVMe with a mount-gate, shipped through the existing log pipeline
  with the log type as a queryable label. The first hours paid out: the un-telemetried Apple base
  station finally has a voice, and the kiosk's browser was caught phoning a Google optimization
  service dozens of times an hour.
- **2026-07** — [The old man in the basement](2026-07-morel-wake-work-sleep.md): the fleet's first
  non-Pi, non-ARM node — an aging amd64 desktop that joins as *summoned muscle*, sleeping in
  suspend-to-RAM and woken by a Wake-on-LAN magic packet from the AI node (~6 s, RAM preserved).
  Onboarding it as the Pi-only runbook's first stranger surfaced latent assumptions (a missing
  baseline tool, a Windows-inherited local-time clock) and left the runbook better. The real lesson
  is monitoring: a node *designed* to be off looks identical to a dead one, so it's excused from the
  liveness alarm — a trade named out loud (a real crash won't page either; outcome-based monitoring
  is the deferred right answer).
- **2026-07** — [The road looks back](2026-07-registry-retrofit.md): reversing the themes
  mechanism's "no retroactive sweep" call — deliberately, with the original reasoning preserved
  under a dated supersede note. The work registry now reaches back to the repo's first commit
  (three epics, fifty-four features, three process eras marked, nothing fabricated), and grew the
  piece the original design lacked: **roadside warnings** — one-line lessons pinned to the exact
  work that earned them, wrong verdicts preserved as wrong, each pointing at the full story. A
  forensics index that can't see the formative mistakes indexes the wrong era.
- **2026-07** — [Watching the cache](2026-07-cache-observability.md): a package-cache + registry
  dashboard, built *before* a rolling upgrade so the cache can be watched warming (hit-ratio climbing,
  bandwidth saved) as the fleet pulls. The registry had native metrics (a config flag); the apt cache
  had none, so a tiny exporter parses its HTML status page into the metrics agent's textfile drop-box.
  A clinic in effect-vs-artifact: three times the thing *looked* installed (wrong tag, an owner-only
  file the reader couldn't open, a dashboard missing from the deploy list) while doing nothing — each
  caught only by checking the far end, not the near end.
- **2026-07** — [Retiring read-only root](2026-07-readonly-root-retired.md): removing a guard that
  cost more than it saved. The kiosk's read-only root spared a cheap SD card from wear but taxed
  *every* change (disarm → apply → reboot → change → re-arm → reboot), silently ate config updates
  into its RAM overlay, and once wedged the clock-less node in a reboot loop. Since a dead card is a
  20-minute reflash, the guard protected a cheap failure at constant cost — so it's gone, with **no**
  lighter replacement (that'd be the same anticipatory instinct, and a RAM disk would tax the fleet's
  most memory-starved node). Includes the trap of deleting a stateful role: it must un-change the
  machine *before* you delete the code.
- **2026-07** — [The trust that wasn't](2026-07-internal-tls-trust.md): a "gather into a TLS
  revisit" note turned into the discovery that **half the fleet couldn't complete a TLS handshake**
  to its own services — CA file perfectly in place, active trust bundle silently missing it, and the
  change-triggered rebuild constitutionally unable to fix a system broken *at rest*. The fix is four
  small tasks around one idea — assert the *effect* every run, heal from scratch, re-assert — and the
  re-assert earned its keep immediately: the bundle tool's incremental mode "healed" with a success
  code while repairing nothing, and only the effect-check caught the lie. Plus a loud refusal on the
  read-only kiosk node, where a "successful" heal would evaporate at the nightly reboot.
- **2026-07** — [Themes: a second axis](2026-07-workflow-themes.md): the feature pipeline gains a
  third noun, and a cleaner hierarchy of intent: **themes are the top-level objectives** (standing
  concerns like "security" that never finish), **epics are the top-level deliverables** (bounded,
  chartered, they end), features are the changes. Themes ride orthogonal to the hierarchy, inherit
  from epic to child, and live in a curated dictionary plus a machine-queryable registry so two
  questions are one-liners: *what open work is there toward X?* and *what was already done under X
  when something breaks?* Renamed from "tag" mid-review — that word was already claimed twice in
  this stack.
- **2026-06** — [Breaking the fleet on purpose](2026-06-chaos-stack.md): the fleet's first multi-part
  *epic* — a chaos-engineering harness that injects known, self-reverting faults into the two leaf nodes
  *only* (the gateway and AI node are never targets) to prove alerts fire and nodes recover, treating
  blind spots ("broke X, nothing paged") as first-class output. Six pieces, each shipped inert until the
  next gave it purpose: a locked-down **access gate** (a robot key that can run exactly one program, with
  a victim-local dead-man); an **incident store** with a vector column; a **controller** that measures the
  real alert via the dashboard API and recovers; a **stand-down guard** (won't poke an already-hurting
  fleet) plus dual-sink harness-health (so chaos is distinguishable from real failure); a **retrieval
  memory** that narrates each incident with an on-device model and answers "has this happened before?"
  semantically; and a **dashboard**. Shipped manual-first; the daily cadence is now switched on. The
  throughline: build the dangerous capability inert + behind a gate, and treat observability *of the
  experiment itself* as first-class.
- **2026-06** — [A database for the fleet](2026-06-postgres-data-layer.md): standing up a
  Postgres + pgvector data layer on the 16 GB node — rootless Podman, a named volume (to dodge
  the rootless permission fight), the official multi-arch pgvector image, a read-only backup
  role, and a nightly `pg_dump` *pulled* by the NAS. Built deliberately empty: the schema waits
  for the first consumer so it's shaped by a real need, not a guess. The microSD risk is owned,
  not avoided — Postgres holds only derived data, and the nightly dump bounds loss to a day.
- **2026-06** — [A daily report that comes to you](2026-06-daily-report.md): a morning
  retrospective digest — 24h uptime, outages, heat peaks, memory stalls, error volume — posted to
  its **own** chat channel (separate from real-time alerting, so a bulky summary never buries a
  page). It earned its keep on day one, flagging the display node peaking ~74 °C under the new
  kiosk. The fight: the chat service's CDN 403'd the script's default HTTP User-Agent — `curl`
  worked, so it was a header, not a credential. This is the baseline a future telemetry-RAG unit
  will learn "normal" from.
- **2026-06** — [Re-onboarding a reflashed node](2026-06-reflash-onboarding.md): wiping the
  display node to the lean OS was routine for the *node* — three pieces of the fleet around it bit
  instead. A package-cache proxy with an empty upstream served error pages the new OS read as
  "signature manipulated"; the WiFi-failover role cut its own connection when run over WiFi (now
  guarded); and the clockless boards needed a "is the clock synced?" onboarding check. Keeper: a
  "new node" failure is usually the fleet around it, and you rule out the dramatic explanation last.
- **2026-06** — [The kiosk, as a real service](2026-06-kiosk.md): rebuilding the little
  touchscreen dashboard as a managed **systemd service** on the now-lite display node —
  restart-on-crash, logs to the central store, start-after-network, and its own up/down alert —
  instead of a hand-opened browser. Chose the service over an autologin shell (more seat/session
  plumbing, but resilient + observable; on-box debug buys nothing on a node that's useless
  offline). The login wall is solved (anonymous read-only access, plus a full-URL fix so kiosk
  mode survives the slug redirect); the small-screen scale lever — which shrank the whole window
  instead of densifying content — is still parked.
- **2026-06** — [Moving the watchtower](2026-06-observability-relocation.md): relocating the
  observability stack (metrics DB + dashboards) off the strained 1 GB node onto the always-on
  gateway, built portable (assigned by inventory group, endpoints via stable proxy names) so it can
  move again with a one-line change. The detours carried the lessons: I blamed the kiosk browser but
  a baseline showed the *dashboard server* was the real RAM hog; "roomiest host" lost to "most
  reliable host" because the alerter inherits its host's uptime; the perishable before-state had to
  be captured before the move erased it; and a dry-run "failure" was just check-mode's install-then-
  start blind spot.
- **2026-06** — [Building features in stages](2026-06-feature-workflow.md): formalizing a
  repeatable feature pipeline — why → what → how → proof → build → validate → land, with a
  small written digest handed between stages — and proving it by shipping a dashboard refresh
  (nodes shown by name, not address). The pipeline's worth showed up in what it caught early: a
  confident plan that was wrong about the present, a community dashboard that wasn't what its
  number promised, two cosmetic go-back-one-step loops, and a fresh-context helper that returned
  confident wrong answers — caught only because its verdict got re-checked.
- **2026-06** — [Durable storage: enclosure-or-drive debug (parked)](2026-06-storage-enclosure-debug.md):
  a new NVMe SSD won't enumerate through its USB enclosure — bridge appears, drive reads as
  zero bytes. Carrying the *same* enclosure to a second host gave the identical result, which
  eliminated the entire host as a variable in one replug. Drive-type mismatch ruled out too;
  what's left (bad cable / dead drive / dead enclosure) needs a spare part that isn't on hand,
  so it's shelved. The keeper is the method: host before part, one variable at a time, don't
  buy a theory you can't test.
- **2026-06** — [Alerts that come find you](2026-06-alerting-discord.md): real fleet
  alerting — node heat (before it throttles) and a node going dark — pushed to a phone via
  a chat-channel webhook, no mail server and nothing new on the WAN. Lessons: keep alerts
  at the data-source layer so they survive a change in collection, don't page on *absence*
  the way you page on *badness*, and treat a webhook URL as the bearer secret it is.
- **2026-06** — [A web search bolt-on, and the local-agentic question answered](2026-06-local-web-search.md):
  giving the local chat a web-search capability — a self-hosted metasearch that CAPTCHA-blocked
  under any load (and *not* because of the VPN — checked), then a keyed API whose free tier had
  quietly gone metered since I last knew it. Search fires, but grounding hits the same CPU-prefill
  wall as the coding agent. Two failures from two directions settle it: the local node isn't an
  agent runtime on this hardware — and that's fine, it was never the job.
- **2026-06** — [Can the local node drive the coding agent too?](2026-06-local-coding-agent.md):
  pointing a cloud agentic coding CLI at the node's local models. The wiring is native (no
  shim) and the integration is tidy — but CPU prefill of a large agent prompt is a hard wall
  (an ~8k-token prompt didn't finish in five minutes). Three surprises, and a clean lesson on
  matching the workload to the hardware.
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
