# React Native — tips, gotchas & reference notes

Curated from real debugging sessions on a data-heavy RN app (New
Architecture, Hermes, FlashList, a JSI/Rust native bridge). Platform-agnostic
RN knowledge only — for Expo-specific material (expo-router, `@expo/ui`,
TurboModule registration, EAS, Metro) see `expo.CLAUDE.md`.

## Contents

1. [Lists](#lists)
   - [Recycle anything that can grow](#recycle-anything-that-can-grow)
   - [Spacing recycled cells](#spacing-recycled-cells)
   - [Sectioned data](#sectioned-data)
2. [Scrolling](#scrolling)
3. [Dependencies that patch globals](#dependencies-that-patch-globals)
4. [JS/TS syntax traps](#jsts-syntax-traps)

---

## Lists

### Recycle anything that can grow

Anything backed by remote data and not a fixed handful of rows — orders,
trades, positions, transactions, journal entries, logs — renders through a
recycling list (FlashList), never `.map()` inside a `ScrollView`. The `.map()`
version is fine with the 12 rows you have in dev and janks hard at the 400
rows a real account has.

**The recycling list must be the *sole* scroller on the screen.** Nesting it
inside another `ScrollView` breaks inner scrolling on Android and defeats
recycling entirely (an outer scroller gives the inner list unbounded height,
so it renders every row — you now pay for the virtualization machinery and
get none of it).

That means static screen chrome — hero, search field, filter chips, banners —
goes in `ListHeaderComponent`/`ListFooterComponent`, **not** above/below the
list, so exactly one scroller exists.

### Spacing recycled cells

Space rows with `ItemSeparatorComponent`, **not**
`contentContainerStyle.gap`. FlashList doesn't reliably honor `gap` between
recycled cells — a real spacing bug traced to exactly this, and it presents as
intermittent/wrong spacing that looks like a style precedence problem rather
than a recycling one.

**Generalizes**: recycled cells are not laid out as a stable sibling list, so
any style that describes a *relationship between siblings* (`gap`,
`:first-child`-ish logic, index-based margins) is unreliable by construction.
Express inter-row spacing through the API the list gives you for it.

### Sectioned data

For grouped/sectioned lists (transactions by date, say), flatten to a single
`{ kind: 'header' | 'row', ... }[]` array and pass `getItemType` so each shape
recycles into its own pool. Don't nest a `.map()` of sub-lists inside
`renderItem` — that reintroduces the un-recycled rendering you flattened to
avoid, one level deeper where it's harder to see.

---

## Scrolling

### A nested `ScrollView` silently makes the footer untappable

If a shared `Screen`/layout wrapper scrolls by default and a route adds its
*own* `ScrollView` inside it, the tail of the inner scroller stops receiving
taps. The symptom is the worst kind: **the button is visible, correctly
styled, and does nothing.** Nothing errors, nothing logs.

Check whether the wrapper already scrolls before adding a `ScrollView` —
opt the wrapper out (`scroll={false}`) rather than nesting. Same root cause as
the list rule above: **one scroller per screen.**

Worth auditing repo-wide rather than fixing one screen at a time — where one
route nested a scroller, dozens usually did, and each one has a dead patch of
UI nobody has reported yet.

---

## Dependencies that patch globals

Some native packages (`react-native-quick-crypto` being the usual one) call
`install()` at **module load**, patching `globalThis.crypto` and `Buffer`. If
the app already installs its own crypto polyfills, both race for the same
globals and the winner depends on module evaluation order.

**Fix**: `import()` them lazily at the point of use, never as a static import
from anything on the boot graph.

Full treatment, including the Hermes/WASM sibling problem (`hash-wasm`) and
the Metro resolver fix, is in `expo.CLAUDE.md` → *Metro bundler* → "A
dependency that patches globals at module load must not sit on the boot
graph". The mechanism is Metro's, but the property belongs to the package.

---

## JS/TS syntax traps

### `??` and `||` cannot be mixed without parentheses

`a ?? b || c` is a hard error — `SyntaxError` in Babel, `TS5076` in
TypeScript. It recurred several times in one session writing fallback-
timestamp expressions:

```ts
closedAt ?? openedAt || Date.now()      // ✗ SyntaxError / TS5076
closedAt ?? (openedAt || Date.now())    // ✓
```

Same rule for `&&` mixed with `??`, in either order. The toolchain catches it
instantly, so it costs seconds — but it's pure friction, and the fix is to
just always parenthesize the mixed case.

More consequential is the *semantic* sibling of this trap — `??` silently
swallowing a legitimate `null` from an authoritative source. That one doesn't
error, and it's written up in `offline-sync.CLAUDE.md` → *The push hash* →
"`??` silently masks a legitimate `null`".
