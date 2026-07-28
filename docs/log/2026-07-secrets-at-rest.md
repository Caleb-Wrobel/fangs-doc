# 2026-07 — The locked door beside the open one

**Goal:** two live third-party API keys were sitting in plaintext inside a nightly
database backup, and that backup was reachable from the network. Encrypt the backups,
close the path, rotate the keys. The plan was written down before any of it was
measured — and measuring it changed the plan twice.

## Shape of it

Four layers, applied in order, each useful on its own: narrow what the file shares
actually serve, encrypt the dumps to a key the backup machine does not possess, prove
a restore actually works, then rotate the exposed keys and destroy the old backups.

The last step is last on purpose, and that ordering turned out to be the most
important decision in the whole exercise. More on that below.

What made this worth writing up isn't the encryption. It's that the plan named the
wrong door.

## Surprise 1: the door I meant to lock was the stronger one

The application in question stores its configuration — including API keys — as
plaintext rows in its database. Nothing exotic; it simply doesn't encrypt config
values, and it says so. The nightly backup dumps that database to the storage node.
Dump files in a custom binary format *look* opaque, which is a trap: that format is
compression, not encryption, and the standard restore tool reads it straight out.

The written plan said: the backup directory sits inside the file share, and the share
password is the only thing between a network client and every retained copy of both
keys. Move the directory out of the share. Done.

Then I actually looked. The storage node shares that drive **two ways** — one
password-protected, one not. The second export served the *same tree*, read-write, to
the whole local network, with the client asserting its own user identity and only the
root account being squashed. Which means: any machine on the LAN whose operator has
administrator rights on their own box could mount it, claim the right user id, and
read every backup. **No password. No credential of any kind.**

The share I was planning to fix was the *stronger* of the two doors. Fixing only it
would have shipped a change that closed nothing, while producing a satisfying commit
and a sense of completion. That is a much worse outcome than not doing the work at
all, because afterwards nobody looks again.

The lesson isn't "check the other protocol." It's that **an exposure audit has to
enumerate every protocol serving a path, not the one that happened to be in the
sentence you wrote.** The password on the front door is what draws the eye. The
opening beside it doesn't announce itself, because there's no lock on it to notice.

## Surprise 2: nothing needed to move

The original fix was "relocate the backup directory." The better fix turned out to be
"narrow what the shares serve," and it was *cheaper* — because when I listed what was
actually on that drive, every single directory was a service's private state:
the backups, the log archive, the container registry, the package cache, the fleet's
own git origin. **There was no user data in the file share at all.** Not one file
anybody had put there on purpose.

So the shares got pointed at a new, empty subdirectory instead of the drive root.
Nothing moved on disk. Every service kept its path. One variable, two template lines,
and the whole class of exposure closed at once instead of one directory at a time.

There's a small, sharp warning attached. The obvious way to do this is to change the
variable holding the drive's location — and that variable is embedded in the URL of
the fleet's authoritative git origin, which another node reads across hosts. Editing
it to "fix a share" would have silently repointed the git remote. The fix has to be a
*new* variable that the shares consume; the old one is load-bearing in ways that
aren't visible from the file you're editing.

## The trap I nearly built

The backup script keeps the newest N dumps and deletes the rest, by listing files
matching a filename pattern. Encrypted dumps get a new extension. So the pattern has
to change too.

Miss that, and here's what happens: the pattern matches **nothing**, the delete list
is empty, and retention silently stops. No error. No alert. Nothing to notice, because
"deleted zero files" and "there was nothing to delete" are indistinguishable from the
outside. The directory just grows forever until a disk fills up months later.

The fix is boring — one variable derives the extension, and the write, the retention
pattern, and the failure message all read *that*, so they cannot drift apart. The
interesting part is how I checked it. Verifying retention "properly" would mean
waiting two weeks for the first real deletion, which is exactly the night nobody is
watching. But the failure mode is a pattern matching nothing — and that's observable
immediately. Build a directory containing every state a run can be in (a finished
encrypted file, a half-written one, an old plaintext one), run the pattern, and see
what it selects. It caught exactly the file it should and left the other three alone.

**A check you have to wait two weeks for is not a check.** Find the version of it that
fails today.

## Encrypting to a key the machine doesn't have

The obvious implementation is to encrypt the backups with a key stored on the backup
machine. This satisfies a checkbox and protects nothing: anyone who can reach the
backups can reach the key sitting beside them.

So the dumps are encrypted to a public key whose **private half is deliberately absent
from the storage node**. The node can write backups it cannot read. That asymmetry is
the entire feature — everything else is plumbing.

It also creates a genuinely new failure mode, and it deserves to be stated plainly
rather than buried: **an encrypted backup is a backup you can fail to restore.** The
escrowed private key is now a single point of total loss. Losing it doesn't degrade
the backups, it destroys them, retroactively, all of them at once.

Which is why the acceptance criteria included an actual restore.

## "It decrypted" is not "it restores"

I wrote the check as: decrypt a real backup and restore it into a scratch database,
then **count the rows**.

That last clause is doing all the work. It would have been easy to accept "the
decryption command exited zero" or "the restore ran without errors" as proof. Both
can be true of an empty database. The check that means something is the one that
compares the restored data against the live original — same table count, same row
count — because that's the claim actually being made. Not "the file was readable."
"The backup restores."

The matching negative check is just as important: attempt the decryption **on the
storage node** and require it to *fail*. An unhelpful error message there is the
feature working. I also grepped that machine for any stray copy of a private key —
which turned up a false positive worth knowing about, in the form of an unrelated
program that has the key format's text prefix compiled into its binary. Investigating
that took a while and found nothing, which is the correct outcome for that kind of
check and still felt like a waste of time until I remembered what it was proving.

## Rotate last, and be honest about the scrub

Nothing in any of this un-exposes what has already been written. The retained backups
had been sitting there for weeks. Encryption protects the *next* dump.

So the order was: close the network path, land the encryption, prove the restore,
*then* rotate both keys at their sources, *then* destroy the old plaintext backups.
Rotating first would have leaked the new keys into the very next unencrypted nightly
run. Rotating last means the new keys never touch a readable backup.

And the "secure deletion" step is just `rm`, which I want to be honest about. On a
journalling filesystem on a spinning disk, unlinking a file leaves recoverable blocks;
overwriting tools make promises that layer cannot keep. Writing hundreds of megabytes
of overwrite passes would have bought a *feeling* rather than a guarantee.

The real revocation is that the keys are dead at the provider. Once that's true, the
plaintext in those old files is inert, and the deletion is hygiene rather than
security. **That's exactly why rotation comes before the scrub** — the ordering is
what makes the weak deletion acceptable.

One practical note for anyone rotating a key that lives in three places: verify all
three, and verify *validity*, not presence. Comparing the three copies' hashes proves
they agree; it doesn't prove they work. Pointing the key at the provider with a
deliberately wrong model name — and getting "not found" rather than "unauthorized" —
proves the credential authenticated. Two different failures that look identical if
you're only checking that a value is non-empty.

## What I'd tell past me

- **Enumerate every path to the thing, not the one you already wrote down.** The plan
  named a password-protected share. The unprotected export beside it served the same
  data and had been there the whole time. A fix aimed at the wrong door is worse than
  no fix, because it ends the investigation.
- **Measure before planning, not after.** Two of this feature's design decisions
  reversed on contact with the actual system — the fix got broader *and* cheaper, and
  neither would have been discovered by thinking harder about it.
- **Encrypting with a key stored next to the ciphertext is theatre.** The property
  worth designing for is "this machine can write backups it cannot read." If the key
  is on the box, you've encrypted nothing that matters.
- **Prove the restore, with a row count.** An encrypted backup nobody has decrypted
  isn't a backup, it's a hostage. Exit codes are not evidence; restored data compared
  against the original is.
- **When a check requires waiting, find the version that fails now.** Silent-stop
  failure modes — a pattern that matches nothing, a loop that iterates zero times —
  never announce themselves. Synthesize the states and watch what gets selected.
- **Say which step is the real one.** Encryption, path-narrowing and deletion all felt
  like the fix. The actual revocation was rotating the keys at their source. Knowing
  that shaped the ordering of everything else — and made it fine that the last step is
  a plain `rm`.
