# Web3 signing — tips, gotchas & reference notes

Curated from a real debugging session wiring EIP-191 (`personal_sign`)
request authentication between a JS/TS client using `@noble/curves` v2 and a
Python server using `eth_account`/`web3.py`. Organized by side of the wire.

Every bug in this file produced the same symptom — **the server recovers a
valid-looking but wrong address** — from four different causes. Signature
verification failures are uninformative by construction: you get "wrong
address", never "you hashed it twice".

## Contents

1. [@noble/curves v2](#noblecurves-v2)
   - [prehash: false](#prehash-false)
   - [v1 → v2 API changes](#v1--v2-api-changes)
2. [The Python side](#the-python-side)
3. [Identity derivation](#identity-derivation)

---

## @noble/curves v2

### `prehash: false`

**noble v2's `secp256k1.sign` SHA256-hashes its input by default** (the
Bitcoin convention). When you pass an already-`keccak256`'d EIP-191 hash — as
every Ethereum flow does — you silently sign
`SHA256(keccak256(EIP191_prefix + message))`, and the server recovers a
completely wrong address from a signature that is otherwise perfectly valid.

```ts
secp256k1.sign(eip191Hash, privateKey, {
  format: 'recovered',
  lowS: true,
  prehash: false,   // ← required; without it noble double-hashes
})
```

The same applies to the verification direction:
`recoverPublicKey(sig, hash, { prehash: false })`.

**Generalizes**: a crypto library's *default* encodes the ecosystem it was
written for. secp256k1 is shared between Bitcoin and Ethereum, which prehash
differently — so the default is right for one of them and silently wrong for
the other. When a primitive spans ecosystems, read the defaults instead of
accepting them; the failure is a wrong-but-valid output, which no type
signature and no exception will ever flag.

### v1 → v2 API changes

Every one of these is a silent behavior change, not a compile error, if you
port code by memory:

- **`sign()` returns a `Uint8Array`**, not a `Signature` object — `.r`, `.s`,
  `.recovery` are gone.
- **`format: 'recovered'` layout is `recovery(1) ‖ r(32) ‖ s(32)`** — the
  recovery bit comes **first**, it is not appended. Ethereum wants
  `r(32) ‖ s(32) ‖ v(1)` with `v = recovery + 27`, so you must reorder
  manually. Getting this wrong yields a 65-byte signature of exactly the
  right length that recovers garbage.
- **`recoverPublicKey()` returns a *compressed* 33-byte key** by default.
  Decompress before deriving an address:
  ```ts
  const uncompressed = secp256k1.Point.fromBytes(compressed).toBytes(false) // 65 bytes
  const address = keccak256(uncompressed.slice(1)).slice(12)                // last 20 bytes
  ```
- **`secp256k1.CURVE.n` was removed.** Hardcode it if you need it:
  `0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141n`
- **Subpath imports need the `.js` extension** under
  `moduleResolution: "bundler"`: `'@noble/curves/secp256k1.js'`,
  `'@noble/hashes/sha3.js'`.

---

## The Python side

### `eth_account`'s EIP-191 version byte is `b'E'`, not `b'\x19'`

`web3.Account.recover_message(signable_message, signature=...)` hashes
`b'\x19' + version + header + body`. The `\x19` is added *for* you.

Hand-rolling a `SignableMessage(version=b'\x19', ...)` therefore
double-prefixes the payload and recovers a wrong address — and it's an easy
mistake, because `\x19` is the byte everyone associates with EIP-191. The
version byte for `personal_sign` is `b'E'` (`0x45`), the "E" in
`"\x19Ethereum Signed Message:\n"`.

**Fix**: don't hand-roll it.

```python
from eth_account.messages import encode_defunct

signable = encode_defunct(text=canonical_string)
recovered = web3.Account.recover_message(signable, signature=sig)
```

`encode_defunct` emits the correct `version=b'E'`, matching a client that
hashed `\x19Ethereum Signed Message:\n{len}{body}`.

**Generalizes**: when both sides of a protocol build the same byte string
from parts, the framing bytes are the seam that breaks — each side may
consider a given prefix "theirs" to add. Write the exact expected byte layout
down once, and use each library's own canonical encoder rather than
reassembling the layout by hand on either side.

---

## Identity derivation

The address used as an identity is derived, not chosen:

**BIP44 derivation → secp256k1 private key → public key → `keccak256(pub[1:])`
→ last 20 bytes → EIP-55 checksum.**

The result must be byte-identical to whatever the signed request headers
carry as the signer's pubkey — a server-side role/permission resolver will
validate that the identity embedded in a path matches the recovered signer.

**Never hardcode a placeholder identity** (`'local-user'` and friends) in a
path that a signature covers, not even during bring-up. It works right up
until the signature check is switched on, at which point the failure surfaces
as an authorization error with no obvious link to the placeholder.

**Timing note**: a wallet is not unlocked at module load, so a sync/auth
manager that needs the derived address cannot resolve it in its constructor.
Defer construction to first use (a lazy wrapper that resolves the address on
the first `pull`/`push`), and cache the derived key — key derivation is
deliberately expensive.

If the wallet address can change during a session, the lazy wrapper must
compare the current address to the one its inner instance was built with and
rebuild on mismatch. Caching identity is correct; assuming it's immutable for
the process lifetime is not.
