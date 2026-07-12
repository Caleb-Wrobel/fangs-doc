# One die, many doors

**2026-07-12** · observability · learning

An evening of hands-on time with the dashboards turned into a feature. Three itches: boards with
hand-built per-node panels had quietly rotted (the topology board didn't know the newest node
existed, and still labelled the kiosk node with a role it lost weeks ago); repeated panels were
copy-paste drift waiting to happen; and a board built in the UI that evening lived only in the
dashboard engine's database — one card reflash away from vanishing.

## The library that wasn't

The obvious mechanism for define-once-reuse-everywhere panels is the engine's native library
panels. Research killed it cleanly: they cannot be file-provisioned in the current version —
they're database entities managed only through an authenticated API, and a provisioned board
referencing a missing one renders a broken panel. The fleet's dashboards are git-provisioned
files precisely so a reflash rebuilds everything; adopting a mechanism that reintroduces
database state and API ordering would trade away the property the whole role is built on.

So: **build-time stamping** instead. Canonical panel definitions live in a small library
directory; boards that use them are written as *sources* containing stamp directives; a
forty-line generator expands directives into full panels and writes the deployable boards,
which are committed. Editing flows through git, regeneration is deterministic, and a one-line
check — regenerate, then `git diff --exit-code` — proves the committed output matches its
sources. The panels lose the "edit once in the UI, update everywhere live" trick, and that's
fine: nothing here is supposed to be edited in the UI.

## Sleep is not death, a label is not a location

The topology board got rebuilt from stamped cards, and the shared card design forced the right
question: what should the newest node — which spends its life suspended, woken on demand —
look like? Not DOWN. The card's query composes liveness with a sleep-intent metric so the
sleeping node renders as a calm blue ZZZ, and any node without that metric falls through to
plain up/down. Every card also switched from hardcoded scrape addresses to hostname labels,
and the new boards were held to a rule: **no query names a host**. Membership comes from
labels, so the next node onboarded appears on every dynamic board with zero dashboard edits —
proven not by onboarding a node but by grepping the boards for addresses and finding none.

## Four new walls

Services (failed units fleet-wide — which immediately surfaced a real finding: an IPMI daemon
failing on three single-board computers that have no IPMI), storage (capacity plus a dedicated
SD-write wear panel, the consumer the earlier wear analysis never had), links (carrier and
failover state — born showing the kiosk node genuinely failed-over to WiFi after the basement
move), and the UI-built DNS board, exported, renamed to what it was always meant to be called,
and made reflash-proof. Deployment collapsed from fourteen copy-paste tasks to one file-glob
loop: adding a board is now just adding a file.

Two API facts earned their place in the notes: this engine reports *every* file-provisioned
board as "not provisioned" when UI-editing is allowed (the real provenance marker is the
provisioning external-id), and UI-built boards survive reboots in the engine's database — only
a deliberate delete or a reflash removes them. Assumptions about cleanup-by-restart die hard.
