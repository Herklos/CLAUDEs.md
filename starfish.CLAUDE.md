# starfish / dk-spaces — tips, gotchas & reference notes

Curated from migrating an offline-first RN + web client between starfish
sync namespaces and onto the `dk-spaces-sdk` family. Scoped to this SDK
family's own contracts — the push/dirty model, space layouts and scopes,
platform shims. The vendor-neutral theory (hydration ordering, merge rules,
tombstones, push hashes) lives in `offline-sync.CLAUDE.md`; this file is only
the things that are true because of *these* packages.

## Contents

1. [The push contract](#the-push-contract)
   - [Pushing with `restore()` never reaches the server](#pushing-with-restore-never-reaches-the-server)
2. [Space layouts & scopes](#space-layouts--scopes)
   - [A layout minting `collections:["*"]` 403s every op on a scope-checking namespace](#a-layout-minting-collections--403s-every-op-on-a-scope-checking-namespace)
   - [Build the layout lazily, or a partial mock in an unrelated test crashes](#build-the-layout-lazily-or-a-partial-mock-in-an-unrelated-test-crashes)
3. [Namespace migration](#namespace-migration)
   - [Re-provisioning beats writing a data migration](#re-provisioning-beats-writing-a-data-migration)
4. [Platform shims](#platform-shims)
   - [A generic pure-JS Argon2id shim is a 100× regression on Hermes](#a-generic-pure-js-argon2id-shim-is-a-100-regression-on-hermes)

---

## The push contract

### Pushing with `restore()` never reaches the server

The two write APIs look interchangeable and are not. Only `store.set(() =>
doc)` marks the document **dirty**, and dirty is what triggers `flush()` →
`syncManager.push()` → client-side encryption of the payload.
`store.restore(doc)` updates local state **only** — it never marks dirty, so
`flush()` never runs and **nothing is ever sent**. Local state looks
perfectly correct, sync is simply silently absent; there is no error to
notice.

**Fix**: any notify-sync path must use `set()`. Guard the resulting store
subscription with an `isRestoring` flag around the write so the subscription
doesn't turn your own outgoing data around into a restore-from-backup call:

```ts
isRestoring = true
store.set(() => doc)   // dirty → flush → push → encrypt
isRestoring = false
```

Related contract worth stating once: with client-side AES-256-GCM, the server
stores an opaque `{ "_encrypted": "<base64>" }` blob and every server
collection is configured `encryption: "none"` — that string means *server
pass-through*, not "no encryption", and reads like a misconfiguration during
review.

`Generalizes:` in any sync SDK with both a "set" and a "restore/hydrate"
write, find out which one sets the dirty bit before using either. The one
that doesn't will pass every local test.

---

## Space layouts & scopes

### A layout minting `collections:["*"]` 403s every op on a scope-checking namespace

Symptom after repointing a client from a permissive server app to a namespace
with an explicit capability model: every `_spaces` / `_devices` operation
403s, while ordinary collection sync works fine.

The chain: the old server granted spaces/devices access via a synthesized
`self` role. The new one requires explicit `cap:read/write:spaces` /
`cap:read/write:devices` scopes. `defaultSpaceLayout`'s
`accountScope`/`linkedDeviceScope` mint `collections:["*"]`, from which the
server synthesizes `cap:read:*` — and `cap:read:*` **never matches**
`cap:read:spaces`. A wildcard that reads like "everything" is a *different
token*, not a superset.

**Fix**: install a custom `SpaceLayout` that spreads the default and
overrides **only** the two scopes with the SDK's explicit-collection
versions, then pass it via `configureSpaces({ layout })` at configure time.

`Generalizes:` a repoint to a "same shape, different namespace" backend is
not a string swap. Diff the *authorization* model first — collections, paths
and encryption can be identical while the cap model isn't, and the 403 points
at the endpoint, not at the layout that minted the scope.

### Build the layout lazily, or a partial mock in an unrelated test crashes

The obvious way to write the above is a module-scope const spreading
`defaultSpaceLayout`. That spread then evaluates **on every import of the
package barrel** — including in tests that partially mock the spaces package
without providing `defaultSpaceLayout`, and that never call the configure
function at all. Those tests crash on an import they don't even know they
have.

**Fix**: build the layout **inside the function** that installs it, so the
default is only touched when someone actually configures.

`Generalizes:` anything that reads a vendor export at module scope becomes a
hard dependency of every consumer of your barrel, transitively. Defer it into
the call that needs it.

---

## Namespace migration

### Re-provisioning beats writing a data migration

A space provisioned under an old namespace is meaningless under the new one:
different registry, different KV credential prefix, different cap model. The
instinct is a relocate/decrypt/re-upload migration. Don't build it — in an
offline-first app **local state is already the source of truth**, so there is
nothing to migrate over the wire.

**Fix**: stamp the namespace onto each registry entry at provisioning time,
flag a mismatch against the currently-configured namespace, and make the
recovery action clear the stale `spaceId`/node id/namespace and **re-run the
exact first-sync path a brand-new entry takes** (re-provision → push
snapshot). No bespoke logic; the new-entry path is already tested.

The real cost to surface in the UI, since it *is* irreversible: any existing
share/invite links are invalidated (new node ids under a new space) and must
be regenerated.

`Generalizes:` when local data is authoritative, a backend migration is
usually a re-provision. Look for the existing first-run path before writing a
migration path that only ever runs once.

---

## Platform shims

### A generic pure-JS Argon2id shim is a 100× regression on Hermes

Adopting a platform SDK's own shims is normally a simplification. One
exception found the hard way: its generic Argon2id shim is pure-JS
(`@noble/hashes`), which costs **~15–45s on Hermes**, versus **~150ms** for a
native binding through quick-crypto's OpenSSL. Keep the app's own native
shim; take the SDK's for everything else.

Ruled-out work that turned out unnecessary in the same pass, worth recording
so it isn't re-added: the manual `configurePlatform({ crypto })` +
`globalThis.crypto = QuickCrypto` assignment. The platform SDK is
platform-split (`index.js` / `index.native.js`) so the bundler resolves the
right one, and the native file's top-level `install()` already exposes
`globalThis.crypto.subtle` — which is exactly what the protocol's
`getCrypto()` fallback checks. The manual assignment was load-bearing only
until that shim existed.

`Generalizes:` when swapping hand-rolled wiring for a vendor's equivalent,
check each replaced piece for a **performance** contract, not just a
behavioral one. "Behavior-neutral swap" is only true if you measured the part
that had a native fast path.
