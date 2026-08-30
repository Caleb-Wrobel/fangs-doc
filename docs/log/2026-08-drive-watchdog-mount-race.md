# The watchdog that watched the wrong door

**2026-08-27** · infrastructure · reliability

A dependency-free boot watchdog exists specifically so it still works when everything
else has failed — no reliance on the observability stack, no reliance on anything
fancy, just a boot-time check that a critical disk is actually mounted before the rest
of the system trusts it. This one was quietly checking the wrong disk on one node the
whole time, and the reason is a small, easy mistake worth naming so it doesn't happen
again.

## One script, copied to a second node

The watchdog was written first for the node with the fleet's original durable-storage
work, and its boot-ordering rule hardcoded the exact mount point that node uses. When
the same watchdog pattern was reused for a second node's own external drive, the
dependency stayed hardcoded to the *first* node's mount path — a plain copy-paste
carryover, not a deliberate choice, and not something a syntax check or a dry run
would ever catch, because the unit is syntactically valid either way. It just races
its own mount at boot on the node where the path doesn't match, sometimes losing.

## The fix is to stop hardcoding the thing that varies

The dependency now derives itself from the same variable that already names the
node's actual mount path, rather than a second, disconnected hardcoded string that
has to be kept in sync by hand. One template now serves both nodes correctly, and a
third node adopting the same watchdog in the future gets the right dependency for
free, because there's no longer a second place to remember to update.

**The keeper:** a value that appears once in configuration and a second time,
hand-typed, somewhere else entirely, will drift the moment the two are updated on
different days — or, as here, never updated on the second occasion at all because
nobody remembered the second occasion existed.
