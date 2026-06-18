# NAS & caching

`cream` is the fleet's storage and self-sufficiency node. It holds the shared
files, caches what the other nodes download from the internet, mirrors container
images locally, and keeps a nightly copy of the logs. The theme tying all of that
together: **the fleet shouldn't have to phone the internet to rebuild itself, and
shouldn't lose its memory because one node's SD card died.**

It's the most modest hardware in the fleet — a 1 GB Pi 3B+ — which is exactly why
it's interesting. Several of its design choices are downstream of *not having much
RAM* and *not wanting to wear out an SD card*.

> **An arm64 node now.** This node was originally 32-bit, which ruled out
> arm64-only software (the image registry below had no 32-bit build). It was
> **reflashed to 64-bit (arm64)**, which is what unlocked running the registry
> here at all. A reminder that "what this node can run" is a property you can
> change with a reflash, not a fixed fact.

## The external drive, and refusing to nuke the wrong disk

Bulk storage is an external USB hard drive, not the SD card. Two reasons: capacity,
and keeping heavy or frequent writes off the SD card, which wears out. The drive is:

- **Mounted by filesystem label**, not by device node. `/dev/sda` depends on USB
  enumeration order and can move; a label is stable, so the mount always finds the
  right filesystem.
- **Pinned by stable device path** for the one dangerous operation — formatting.
  Disk prep targets the drive by its by-id path, never `/dev/sda`, so it can only
  ever act on *that physical drive*.
- **`nofail`**, so the node still boots if the drive is unplugged rather than
  hanging on a missing mount.

The disk-prep logic is deliberately paranoid, because formatting is irreversible:

1. **Refuse the system disk.** A guard asserts the target isn't the SD card before
   anything runs.
2. **Refuse a missing drive.** If the drive isn't present as a block device, stop —
   because "the labelled filesystem wasn't found" must never fall through into
   "so format whatever's at this path."
3. **Format only when the labelled filesystem doesn't already exist.** On every
   subsequent run the label is found, prep is skipped, and the role is
   non-destructive. The wipe happens once, on a blank drive, and never again.

> The shape of the lesson: a destructive, run-anytime automation needs its safety
> to come from *positive existence checks*, not from "it probably won't match." The
> drive present and labelled is the only state in which it's safe to do nothing;
> every other state should refuse, not improvise.

## File sharing

The drive is shared back to the LAN two ways, so any client can use whichever is
convenient:

- **Samba** for the cross-platform/Windows-friendly path.
- **NFS** for the Unix-native path.

Both are scoped to the **LAN only** — exports and host-allow rules are limited to
the local subnet plus loopback. cream sits behind the gateway and is never
WAN-facing, so sharing is an inside-the-house convenience, not an exposure.

## Package cache

Every node's apt traffic can be pointed at an **apt-cacher-ng** proxy running here.
The first node to need a package fetches it from the internet; every node after
that gets it from cream at LAN speed. Rebuilds stop hammering the upstream mirrors,
and the fleet keeps installing software through brief internet hiccups.

Two deliberate details:

- **The cache lives on the HDD**, not the SD card — a package cache is exactly the
  kind of bulky, churning write load you want off the card.
- **It binds the LAN and loopback only.** Like the file shares, it's an internal
  service that never listens on the WAN edge.

Nodes built *after* cream opt in to the cache; the ordering in the
[build sequence](overview.md#build-order) exists partly so the cache is ready
before the nodes that would benefit from it come online.

## Local image registry

cream runs **Zot**, an OCI container-image registry, so the fleet can pull
container images from inside the network instead of from the public internet every
time. It's reachable through the reverse proxy at `https://zot.fangs.internal`
(see [TLS & reverse proxy](tls-proxy.md)).

How it's run is itself a small statement of the fleet's container conventions:

- **Rootless Podman.** The registry runs as an ordinary user's container, not as
  root — no daemon running as root, no root-owned container runtime.
- **Managed as a Quadlet.** Rather than a hand-written unit or a `podman run`
  script, the container is declared as a Quadlet and systemd generates and
  supervises the service. The user's services are set to **linger** so they survive
  logout and start at boot.
- **Blobs on the HDD.** Image layers go to the external drive, not the SD card —
  same reasoning as everything else here.

> **Honest status:** the registry currently runs **open on the trusted LAN** — no
> authentication yet. That's consistent with the fleet's inside-the-LAN posture
> (visibility over isolation), but it's flagged on the [roadmap](../roadmap.md) to
> get credentials before it carries anything that matters.

## Nightly log backup

cream is also the **backup target for the logs**. The gateway aggregates the whole
fleet's logs ([Observability](observability.md)); cream keeps a nightly copy so a
gateway SD-card failure or reflash doesn't erase the log history.

The notable design choice is the **direction**: it's a **pull**, run from cream, not
a push from the gateway. A scheduled job here reaches over to the gateway nightly
and mirrors its log data store to the HDD.

- **The backup host owns the backup.** Because cream initiates, the gateway needs
  no outbound keys, no backup script, no knowledge that it's being backed up. The
  responsibility lives with the node that holds the copy.
- **A dedicated, least-scope key.** The pull uses its own SSH key, generated for
  this one job, rather than reusing a general-access credential.
- **A mirror, not an archive.** It reflects the current log store for
  disaster-recovery, deleting what the source deleted — it's "get the gateway back
  to now after a rebuild," not long-term retention.

## Surviving on 1 GB

Two small things keep the smallest node honest under load:

- **zram** gives it a block of **compressed swap in RAM**, so memory pressure is
  absorbed by compressing cold pages instead of falling back to painfully slow
  swap on the SD card or HDD. Headroom for Podman, the registry, and the file
  services to coexist on 1 GB.
- **PSI** (pressure-stall information) is enabled here first of all, because this
  is the node most likely to actually feel a memory squeeze — see the
  [PSI build log](../log/2026-06-psi-fleetwide.md). zram usage and pressure are
  both visible in the fleet metrics, so "is cream struggling?" is a dashboard
  question, not a guess.

## The thread running through all of it

Almost every choice on this node points the same two directions: **keep bulky,
churning writes off the SD card** (the drive, the package cache, the image blobs,
the log backup all live on the HDD), and **let the fleet lean on local copies**
(packages, images, and log history are all available from inside the network). The
node's whole job is to make the cluster a little less dependent on the outside
world — and a little more able to rebuild itself from within.
