# Offline-first sync — tips, gotchas & reference notes

Curated from real debugging sessions building an offline-first mobile app: a
zustand `persist` store per collection, a sync engine pushing/pulling
encrypted document blobs to a server that stores opaque ciphertext and knows
nothing about the schema. Organized by the layer each problem lives in.

The recurring theme: **a sync bug almost never looks like a sync bug**. It
looks like data quietly disappearing, and the mechanism is usually an
ordering assumption nobody wrote down.

## Contents

1. [When sync does nothing at all](#when-sync-does-nothing-at-all)
   - [A circular early-return deadlock hides every bug behind it](#a-circular-early-return-deadlock-hides-every-bug-behind-it)
2. [Hydration ordering](#hydration-ordering)
3. [Local writes vs remote writes](#local-writes-vs-remote-writes)
4. [Merging](#merging)
   - [The merge rules](#the-merge-rules)
   - [Absence is not a deletion](#absence-is-not-a-deletion)
   - [Writes that arrive during the pull](#writes-that-arrive-during-the-pull)
5. [Tombstones](#tombstones)
6. [The push hash](#the-push-hash)
7. [Wiping](#wiping)

---

## When sync does nothing at all

### A circular early-return deadlock hides every bug behind it

Sharing had never worked once, in any build. Not "worked and broke" — never
ran. The cause was two guards pointing at each other:

```ts
invite()       // if (!session || !spaceId) return;   ← spaceId only set by activateSync
activateSync() // if (!bulle.spaceId) return;         ← never reached, so never sets it
```

Nothing threw. Nothing logged. The button worked, the spinner stopped, and no
request was ever sent. The tell is what it *masked*: the configured sync host
did not resolve (NXDOMAIN) and nobody had noticed **in months**, because sync
never got far enough to fail. A dead network is invisible behind code that
never reaches the network.

**Fix**: whoever needs the precondition establishes it, rather than waiting for
someone else to. Provisioning became explicit and idempotent, and the caller
derives its own session instead of reading a singleton that may be unset.

`Generalizes:` a silent `return` is the worst failure mode a feature can have,
because it produces *no* evidence — a throw gets a stack, a rejection gets a
log, a `return` gets nothing, and the UI cheerfully reports success. So:

- **When something "does nothing", look for a guard before you look at the
  network.** "Does nothing" and "fails" have completely disjoint suspect lists,
  and it is always cheaper to check for the first.
- Two early-returns each waiting on state the *other* sets is a deadlock that
  no test catches, because each function is individually correct.
- A guard that silently returns on missing state is claiming that state is
  someone else's job. If nobody's code path establishes it, the feature is
  dead from the first commit and looks merely unused.
- Corollary: a downstream component can be broken for months with zero signal
  while an upstream no-op shields it. Fixing the no-op reveals a queue of bugs
  that were always there — expect them, and don't read them as regressions.

## Hydration ordering

### Any write issued right after store creation lands *after* hydration and clobbers disk

A persisted store's hydration is asynchronous: `persist` issues a `getItem`
and applies the result when it resolves. Any store method called
synchronously after creation — `setOnline()`, `restore()`, `pull()`, or any
plain `set()` — queues its own `setItem` write. That write lands **after**
hydration's `getItem` completes, so the empty just-created state overwrites
what was on disk.

The symptom is maddening because in-memory state looks perfect for the whole
session. Only the *next* app start reveals it: the store comes up empty, and
nothing in the current run's logs points at the cause.

**Fix**: gate every piece of post-creation init behind a `whenHydrated(store,
cb)` helper: run immediately if `persist.hasHydrated()`, else register on
`persist.onFinishHydration(cb)`, else (no persist middleware at all) run
immediately.

Give the same treatment to every online-transition trigger (unlock, boot,
changing sync target) via one shared entry point that defers via
`whenHydrated`, drains pending local writes, *then* pulls — rather than
letting each call site remember the ordering.

**Generalizes**: async hydration turns "initialize the store" into a race
against the store's own disk read. Any code path that can run before
hydration resolves must be deferred, not just the obviously-network ones —
the write is what clobbers, and every method that touches state writes.

---

## Local writes vs remote writes

### The dirty flag is a claim about *provenance*, not about change

Two mutation paths are mandatory, and conflating them breaks sync in both
directions:

- **`restore(data)`** — server-pulled data. Writes to storage, does **not**
  set `dirty`.
- **`set(modifier)`** — local writes. Sets `dirty`, schedules a flush.

The rule that keeps it straight: **user did it → `set()`. Server sent it →
`restore()`.**

Get it backwards and you either push the server's own data back at it in an
endless loop (`restore` marking dirty), or silently drop the user's work
(`set`-shaped data applied via `restore`, never flushed).

---

## Merging

### The merge rules

For a document merge of `(remote, local)`:

1. **Arrays of `{id}` objects** — union by id. On a duplicate id, the side
   with the greater `max(deletedAt ?? 0, editedAt ?? 0)` wins. Tie, or
   neither side timestamped → **local wins**. Remote order is preserved;
   local-only items append.
2. **Plain objects** — recursive merge, local leaf wins.
3. **Primitives, null, primitive arrays** — local wins if defined, else
   remote.

Defaulting to local on ties is deliberate: the local device is the only one
with a user who might be watching.

### Absence is not a deletion

The bug this exists to prevent: local has live items, the pull returns
`{items: []}` because the *server* was wiped, and the dirty flag is clean
because the user changed nothing. Every rule above says "remote applied
cleanly" — so the local items are silently destroyed.

**Fix**: alongside re-sampling `dirty` after the pull, compute a
`hasMissingIds(preSnapshot, postPull)` signal — any id present in the
pre-pull local snapshot and absent post-pull. Trigger the merge if
`wasDirty || postDirty || hasMissingIds`. The merge re-instates the items and
marks dirty, so the next flush re-pushes them to the wiped server.

**Rule**: **server deletions propagate via tombstones, never via absence.**
An item that just isn't there anymore is indistinguishable from data loss,
so treat it as data loss. This is the single most important line in this
file — every "where did my data go" incident traces back to some layer
reading absence as intent.

### Writes that arrive during the pull

A pull's network RTT is a wide-open window. A write applied during it is
based on pre-pull state and gets overwritten by the merge result.

**Fix**: gate the store's `set()` while the underlying pull is awaited —
queue those writes instead of applying them. After the merge completes,
replay the queue in order against the merged state. They land in the next
flush; nothing is lost.

Also re-sample `dirty` *after* the pull resolves, not just before: a write
arriving mid-pull is exactly the case a pre-pull-only check misses.

---

## Tombstones

Soft-delete (`deletedAt`) plus a last-edit timestamp (`editedAt`) is what
lets the merge layer tell "the user deleted this on another device" from
"the server lost it". Without them, the two are the same event and you must
guess.

**Where this lives matters**: if the server stores opaque encrypted blobs and
the sync client is byte-level, neither can reason about schema-level
`deletedAt` — so the tombstone contract belongs in the app layer that already
knows the schema, next to the merge rules. Don't try to push it down into a
client that is deliberately schema-blind.

### When a collection needs them

All three must hold:

- The document has an `items: T[]` where `T` has an `id: string`.
- Local code can mutate those items (add / edit / delete). **Pull-only,
  server-driven collections don't need tombstones** — there's no local delete
  to propagate.
- The collection is actually synced (not a local-only store).

### The contract

1. **Schema** — add `deletedAt?: number` and `editedAt?: number` to the item
   type. A generic merge layer reads these by name, regardless of collection.
2. **Mutations**:
   - **Delete** → soft-delete: set `deletedAt`, clear `editedAt`, and
     **preserve every other field** — resurrection needs them.
   - **Edit** (user intent) → apply the patch, bump `editedAt`, clear any
     prior tombstone.
   - **Add** → no timestamps. A brand-new item is live with no edit history.
   - **System patches** (sync-fetched data, heartbeats, background refresh)
     → plain map, and **do not bump `editedAt`**. These aren't user intent;
     bumping would let a stale background refresh outrank a real edit in a
     merge tie. This is the subtle one — it looks like an inconsistency until
     you remember `editedAt` means "the user meant this", not "this changed".
3. **Reads** — every consumer filters through a `liveItems(items)` helper so
   tombstoned items are invisible to the UI. Miss one imperative reader and
   deleted data reappears in exactly one place.
4. **Cross-references** — when a primitive field references an item id: clear
   the reference on soft-delete if it points at the deleted id, and validate
   against `liveItems(...)` in any setter. A reference to a peer-tombstoned
   item is a dead pointer that the UI will try to resolve.
5. **Boot resurrection of self-references** — if local code deterministically
   re-creates an entry at boot with a known id (registering the current
   device, say), check for an existing tombstone and go through the *edit*
   path (which bumps `editedAt` past the tombstone) rather than plain
   patching. Otherwise the entry exists locally but stays dead in every
   merge.

### Conflict resolution

Two items with the same id, greater `max(deletedAt ?? 0, editedAt ?? 0)`
wins:

| Local | Remote | Result |
|---|---|---|
| edit `editedAt=100` | tombstone `deletedAt=50` | local wins → resurrect |
| edit `editedAt=50` | tombstone `deletedAt=100` | tombstone wins → propagate |
| tombstone | tombstone | newer tombstone wins |
| no timestamps | no timestamps | local wins (pre-tombstone semantics) |

### Garbage collection

A generic `gcDocumentTombstones(doc, cutoffMs)` recursively walks any
document and purges items whose `deletedAt < cutoff` — no per-collection
knowledge needed. Run it at each online-transition cycle *before* the flush,
so the GC mutation rides the next push and prunes the server too.

Pick the TTL against your device-count assumption. A 30-day TTL on a
single-device-per-account app is safe; a device offline longer than the TTL,
whose peers already GC'd a tombstone, will resurrect the deleted item on its
next pull. That's the tradeoff, and it's inherent — tombstones can't be kept
forever, and a device can't distinguish "GC'd tombstone" from "never knew".

---

## The push hash

### Persist the last server hash next to the data, or eat a 409 on every restart

The sync manager tracks the last known server hash to send as `baseHash` on
push. If that hash lives only in memory, the first push after any restart /
lock / unlock carries no base, the server rejects it as a conflict, and you
pay a spurious 409 + recovery roundtrip before every session's first write.

**Fix**: persist it in the same JSON as the data, and restore it into the
sync manager during rehydration, *before* any pull or push runs:

```json
{ "state": { "data": { "items": [] }, "dirty": false, "hash": "<server-hash>" },
  "version": 0 }
```

No consumer-side hash machinery beyond that — clearing storage wipes the JSON
and the hash dies with the data, which is exactly right.

### `hash: ""` for an empty collection must be normalized to `null`

A server may return `hash: ""` (not `null`) when a collection is empty — e.g.
right after the user wipes their data. Push it back as `baseHash=""` and the
server, which expects `null` for "no prior version", 409s. Forever. A wiped
server becomes permanently unwritable.

**Fix**: normalize `"" → null` at the wrapper boundary — in `getHash`,
`setHash`, and `clear` alike, so no path can leak the empty string onward.

### `??` silently masks a legitimate `null`

Same module, better lesson. This looks obviously correct:

```ts
getHash() { return inner?.getHash() ?? pendingHash }
```

`inner` is the authority when it exists; `pendingHash` is a cache for when it
doesn't. But `??` can't tell "`inner` is absent" from "`inner` authoritatively
returned `null`". After pulling an empty document, `inner` correctly reports
`null` — and `??` helpfully replaces that truth with the stale
`pendingHash`. The client keeps its old hash forever after a server wipe, and
every push 409s.

**Fix**: branch on the *presence of the authority*, not on the falsiness of
its answer:

```ts
getHash() { return inner ? inner.getHash() : pendingHash }
```

**Generalizes**: `??`/`||` fallbacks are for "no answer available", but they
fire on "the answer is null/empty" too. Whenever `null` is a **meaningful
value** in a domain and not just an absence, a `??` chain will eventually eat
it — and the bug surfaces as stale data, far from the operator that caused
it. Ask "can the left side legitimately *be* this value?" before reaching for
`??`.

---

## Wiping

### Order the teardown so an in-flight push can't resurrect the data

Clearing all storage (sign-out, account wipe) races any push already in
flight: it completes after `clearStorage()` and re-persists the very data you
just cleared.

**Fix** — strict order:

1. `setOnline(false)` on every mutable store.
2. Mark every sync manager wiped — an internal flag checked **both** before
   calling the inner push **and** after the inner push resolves. If wiped,
   throw; the store's flush then skips its `restore()`, so nothing gets
   re-written.
3. Only then `clearStorage()`.

Checking the flag on *both* sides of the await is the part that's easy to get
wrong — a check only on entry leaves the whole network RTT unguarded, which
is precisely the window you're defending against.

A wiped manager must stay wiped: any later push throws. If a manager needs to
be reusable after a clear (lock → unlock, say), that's a *different*
operation — a plain `clear()` that releases the inner manager so the next
resolve starts fresh — not the wipe path.
