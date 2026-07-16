# Expo — tips, gotchas & reference notes

Curated from real debugging sessions (Astrolab2/mobile2, an Expo Router +
New Architecture RN app using `@expo/ui`, custom TurboModules, and a
Rust/JSI native bridge). Organized by subsystem so a specific problem class
is easy to jump to.

## Contents

1. [expo-router](#expo-router)
2. [@expo/ui](#expoui)
   - [Universal BottomSheet](#universal-bottomsheet)
   - [Community BottomSheet](#community-bottomsheet)
   - [Universal List](#universal-list)
   - [ListItem](#listitem)
   - [Host sizing](#host-sizing)
   - [Button](#button)
   - [SegmentedControl](#segmentedcontrol)
   - [DateTimePicker](#datetimepicker)
   - [swift-ui/modifiers vs jetpack-compose/modifiers](#swift-uimodifiers-vs-jetpack-composemodifiers)
3. [Widgets (expo-widgets)](#widgets-expo-widgets)
4. [Native modules / TurboModules](#native-modules--turbomodules)
   - [iOS registration](#ios-registration)
   - [Android registration](#android-registration)
5. [EAS Build](#eas-build)
6. [Metro bundler](#metro-bundler)
7. [Expo CLI & dev-client builds](#expo-cli--dev-client-builds)
8. [expo-audio](#expo-audio)

---

## expo-router

### `AppBar`/header components target the *nearest* Stack, not the root

Any header component built on `useNavigation().setOptions(...)` configures
whichever `Stack` is nearest in the tree — not necessarily the root one you
expect.

- Inner `Stack` with `headerShown: false` → your header options are
  invisible (no title, no back button) — you configured a hidden stack.
- Root Stack *also* has `headerShown: true` for the same route → double
  header (root's + the nested one's).

**Rule**: one Stack should own the header per screen. Prefer the root
Stack; reach for a nested `_layout.tsx` only when a route needs its own
Stack-level behavior (e.g. a modal presentation for a sibling route).

### Root Stack opt-out pattern for sub-layouts

If the root `_layout.tsx` defaults every screen to `headerShown: true`
(e.g. via a shared `defaultHeaderOptions()`), every directory that owns its
*own* sub-layout must explicitly opt out at the root:

```tsx
<Stack.Screen name="some-group" options={{ headerShown: false }} />
```

The sub-layout's own `Stack` then manages `headerShown: true` for its
screens. Forgetting this opt-out is the most common cause of the
double-header symptom above.

### When *not* to reach for a nested sub-layout

If a directory only needs a modal sibling (e.g. `index.tsx` + `menu.tsx`),
configure the modal directly in the parent layout via
`<Stack.Screen presentation="modal" />` instead of giving the directory its
own `_layout.tsx`. `index.tsx` then stays a plain root-Stack screen — the
header targets root, and the back button works automatically without any
extra wiring.

### Back button only appears with a previous screen in the *same* Stack

React Navigation only shows a back button when there's a previous entry in
**the same Stack instance**. Pushing a route directly from a tab root (with
no intermediate screen) leaves nothing to go back to — no back button
appears, even though the route "feels" like it should have one.

Fix: either navigate through an intermediate screen so a real Stack entry
exists first, or use modal presentation with an explicit close button
instead of relying on the back chevron.

### `<Stack.Screen options>` nested inside a scroll container never reaches the navigator

The header silently stays bare. No warning, no error: the element renders, its
props are simply never read, so this reads as "options don't work" rather than
"options are in the wrong place".

`<Stack.Screen>` is not a rendered component; it is a **declaration** the
navigator collects from the screen's element tree. Put it inside a
`ScrollView`'s content container (or any wrapper that renders `children` into
one) and it is no longer somewhere the navigator looks.

**Fix**: make it a *sibling* of the scroll container, not a child.

```tsx
// Silently does nothing — Screen renders children inside a ScrollView.
<Screen>
  <Stack.Screen options={{ headerRight: ... }} />
  ...
</Screen>

// Works.
<>
  <Stack.Screen options={{ headerRight: ... }} />
  <Screen>...</Screen>
</>
```

This bites hardest with a house `<Screen>` wrapper, because the fact that
there is a `ScrollView` in the middle is exactly what the wrapper hides.

`Generalizes:` a declarative-config element (`Stack.Screen`, `Head`, anything
collected into a parent registry) is picked up by its *position in the tree*,
not by being rendered. Any wrapper between it and its collector can break it
while still rendering it — so "it's right there in the JSX" is not evidence
it is wired.

### `Screen`/safe-area padding double-counts with native headers

A shared `Screen` wrapper that adds `paddingTop: insets.top` needs to
detect whether a native Stack header is already visible for that route —
if it is, the header already absorbs the safe-area inset, and adding your
own padding on top double-pads the content. Detect via
`HeaderHeightContext` from `@react-navigation/elements` (it's non-null when
a native header is present) and skip the manual padding in that case,
rather than requiring every call site to remember a `padTop={false}` flag.

---

## @expo/ui

### Universal BottomSheet

`@expo/ui`'s **universal** `BottomSheet` (imported from the `@expo/ui`
root, *not* `@expo/ui/swift-ui` or `@expo/ui/jetpack-compose` directly)
resolves per platform: SwiftUI `.sheet` on iOS, Jetpack Compose
`ModalBottomSheet` on Android, `vaul`'s `Drawer` on web. It is a different
API from `@expo/ui/community/bottom-sheet` (an `@gorhom/bottom-sheet`
drop-in with a much simpler prop surface, e.g. a direct `backgroundStyle`
prop and `enableDynamicSizing`) — **don't mix the two APIs up**; the
universal one only exposes `snapPoints`/`showDragIndicator`/`modifiers`,
nothing else.

#### Plain RN content is not reliably tappable on either native platform

This is the single biggest gotcha with the universal `BottomSheet`. Naively
putting RN `Pressable`/`Button`/`View` content inside it looks fine —
renders, even shows a press animation on tap — but `onPress` silently never
fires. The mechanism differs by platform, but the failure mode is
identical:

- **iOS**: `@expo/ui` hosts arbitrary RN content inside the SwiftUI sheet
  via an `RNHostView` bridge whose native touch handler attaches **once**,
  on first appear, with no retry. Any resize of the sheet's detent *after*
  it's presented (e.g. a height that gets re-measured, or `fitToContents`
  re-laying-out) re-parents that hosted view and desyncs the handler
  permanently for that mount.
- **Android**: every `@expo/ui/jetpack-compose` container (`Column`, the
  `ModalBottomSheet`'s own content slot, ...) walks its children via
  `ExpoComposeView.Children()` — found in
  `node_modules/expo-modules-core/android/src/compose/expo/modules/kotlin/views/ExpoComposeView.kt`:

  ```kotlin
  fun Children(composableScope: ComposableScope?, filter: (child: ExpoComposeView<*>) -> Boolean) {
    for (index in 0..<this.size) {
      val child = getChildAt(index) as? ExpoComposeView<*> ?: continue  // <-- skips plain RN children
      ...
    }
  }
  ```

  Any child that isn't itself an `ExpoComposeView` (i.e. not another
  `@expo/ui/jetpack-compose`-native component) is **skipped from the
  Compose render/hit-test tree entirely**. A plain RN `Pressable` inside a
  `Column` still visually *paints* (React Native lays it out via its own
  overlapping Android View layer) but is never composed into Compose's
  layout/hit-testing, so taps land nowhere.

  Per `@expo/ui`'s own jetpack-compose `ModalBottomSheet` docs, the
  **supported** way to embed interactive RN content in Compose is wrapping
  it in `RNHostView` — a real, deliberate bridging component, not
  automatic. A bare RN child with no `RNHostView` wrapper is exactly what
  `Children()` drops.

**Fix pattern**: build sheet content entirely from `@expo/ui`'s own
components (`Column`, `ListItem`, `Text`, `Divider`, ...) for **both iOS
and Android** — not just iOS, which is the mistake that's easy to make
since the iOS bug is the one most commonly documented online. Gate on
`Platform.OS !== 'web'` (native content) vs. `=== 'web'` (plain RN
content), not `=== 'ios'`.

Two non-obvious rules once you're building fully-native sheet content:

1. **`@expo/ui`'s native tree is reconciled separately from React
   Native's.** The instant a plain RN element (`View`, `Pressable`, or any
   styled wrapper around them) appears as an ancestor anywhere in that
   tree, every `@expo/ui`-native element nested inside it silently renders
   as an unrecognized RN component instead of real native UI — typically
   **blank**, not an error. The whole subtree from the sheet's content
   root down must be `@expo/ui`-native if anything inside needs to render
   or respond to touch.
2. **The one supported exception**: `ListItem`'s `leading`/`trailing` slot
   props. `@expo/ui`'s own implementation explicitly wraps whatever is
   passed there in `RNHostView matchContents` — a deliberate bridge. RN
   content (icon chips, a loading spinner) is safe there. It is **not**
   safe as `ListItem`'s `children` (the label) — that path only
   auto-wraps bare strings, so an RN `Text`-based component passed as
   `children` hits rule 1 and silently fails to render; use `@expo/ui`'s
   own `Text` there instead.

#### `Column` hugs content width — doesn't stretch like an RN `View` with `flex`

On **both** the SwiftUI and Jetpack Compose sides, `Column` sizes itself to
its content by default; it does not stretch to fill its parent. Building a
full-width tappable "pill" (e.g. a confirm/gate sheet's action buttons) out
of native components needs an *explicit* width:

```tsx
const { width: screenWidth } = useWindowDimensions()
const contentWidth = screenWidth - insetsX
// <Column style={{ width: contentWidth }}>...</Column>
```

Without it, a `Column` wrapping a single short `Text` renders as a
small content-sized pill, not the full-width button you expect — even
inside a wider parent `Column`.

Related: `ListItem`'s headline text **left-aligns regardless of**
`textStyle.textAlign` or a `frame({alignment:'center'})` modifier on the
`ListItem` itself — its internal row layout stays leading-aligned no
matter what the outer frame says. For a single centered action button,
skip `ListItem` entirely and use `Column`'s own `onPress` (part of
`UniversalBaseProps`, every universal component supports it) with
`alignment="center"` and an explicit `style.width` — `Column`'s
`alignment` prop actually governs its own children's cross-axis position.
Reserve `ListItem` for genuine multi-row lists, not single centered
buttons.

#### iOS: `fitToContents` can get stuck at a fallback detent

Omitting `snapPoints` (`fitToContents`) measures content via a native
`GeometryReader` — this measurement can get stuck at the `.medium`
fallback detent when it can't resize an already-presented sheet (e.g. if
content height is itself computed post-mount). Prefer an explicit static
`snapPoints={[{ height }]}` on iOS for custom-styled content: compute the
height once, don't update it post-present, and never wrap sheet content in
a two-phase off-screen-measure-then-remount render (that remount also hits
the "reconciled separately" failure mode above). Size the static height to
actually fit the content — too generous shows a gap of screen-behind-
backdrop below the content; too tight clips it.

#### Android: `{ height }`/`{ fraction }` snap points are not honored literally

Per `@expo/ui`'s own docs, Android snaps `{ height }`/`{ fraction }` snap
points to the *nearest* of `'half'`/`'full'` instead of the literal pixel
or fraction value — a static height (needed on iOS, see above) balloons
the sheet on Android well past its real content height. Gate a static
height to iOS only:

```ts
const snapPoints = Platform.OS === 'ios' ? [{ height }] : undefined
```

Android then auto-sizes to content, which is what you actually want there.

#### Android sheet chrome follows the *system* theme, not your app's own palette

If your app has a single fixed theme (e.g. always-dark) with no
light-mode variant, note that the universal `BottomSheet`'s Android
implementation (`node_modules/@expo/ui/src/universal/BottomSheet/index.android.tsx`)
never forwards `containerColor`/`contentColor` to the underlying Material3
`ModalBottomSheet`, even though that component fully supports both. Left
unset, the sheet chrome falls back to `BottomSheetDefaults.ContainerColor`,
which resolves from the **ambient system** Material theme — white on a
light-mode device, dark only by coincidence on a dark-mode device, not
because your app styled it.

Things that look like they should fix this but don't:
- **The `modifiers` escape hatch** (`modifiers={[background(colors.bg)]}`
  from `@expo/ui/jetpack-compose/modifiers`, passed straight through to
  the untouched universal `BottomSheet`) does not visibly repaint the
  chrome in practice, despite being a documented, safe escape hatch for
  other purposes.

**What actually works**: a real `.android.tsx` sibling file that composes
`@expo/ui/jetpack-compose`'s `Host`/`Column`/`ModalBottomSheet` directly
(mirroring the universal wrapper's own internals), so `containerColor`/
`contentColor` can be forced regardless of system theme:

```tsx
// RouteSheet.android.tsx
import { Host, Column, ModalBottomSheet, type ModalBottomSheetRef } from '@expo/ui/jetpack-compose'
import { padding, fillMaxHeight, type ModifierConfig } from '@expo/ui/jetpack-compose/modifiers'

// ...state machine identical to the shared RouteSheet.tsx (isPresented,
// dismiss animation, etc.) — see "why a real .android.tsx file" below...

<Host style={{ position: 'absolute' }} pointerEvents="none">
  <ModalBottomSheet
    ref={sheetRef}
    onDismissRequest={onDismiss}
    showDragHandle={showHandle}
    skipPartiallyExpanded={shouldSkipPartiallyExpanded(snapPoints)}
    containerColor={colors.bg}
    contentColor={colors.ink}
  >
    <Column modifiers={contentModifiers}>{children}</Column>
  </ModalBottomSheet>
</Host>
```

**Why a real `.android.tsx` file, not `Platform.OS` branching inline**:
`@expo/ui/jetpack-compose`'s *component* subpath (`Column`, `Host`,
`ModalBottomSheet` — unlike its `modifiers` subpath, which is pure JS
config construction and safe to import unconditionally) calls
`requireNativeView('ExpoUI', ...)` at module top level for Android-only
native view names. Importing it from a cross-platform shared file bundles
those calls into the iOS/web build too — Metro's `.android.tsx` extension
resolution is what keeps native-view-requiring code out of every other
platform's bundle in the first place (the same protection `@expo/ui`'s own
universal `BottomSheet` gets via its own `index.ios.tsx`/`index.android.tsx`
split). This mirrors the exact same landmine documented below for
`@expo/ui/swift-ui/modifiers` on web.

If an earlier attempt at this exact `.android.tsx` reimplementation
appeared to break button taps, check whether the sheet's *content* was
still plain RN at the time — that's a confound: fully-native content (see
above) plus this reimplementation is safe; RN content plus this
reimplementation reproduces the `Children()`-skip bug regardless of the
sheet shell.

### Community BottomSheet

Not the same component as the universal one above: `@expo/ui/community/bottom-sheet`
is the `@gorhom/bottom-sheet` drop-in, with `enableDynamicSizing`,
`backgroundStyle`, and a much simpler prop surface. Its gotchas — and
crucially its *fixes* — are different, and reading a universal-BottomSheet
finding as if it applied here is the expensive mistake.

#### `enableDynamicSizing={false}` alone makes plain RN content tappable on iOS

Same visible symptom as the universal sheet on iOS: RN `Pressable` rows
inside show a press animation but `onPress` never fires. Same underlying
`RNHostView` bridge whose touch handler attaches once, on first appear, with
no retry. The mechanism, traced through
`node_modules/@expo/ui/src/community/bottom-sheet/BottomSheet.ios.tsx`: with
no explicit `snapPoints`, `enableDynamicSizing` **defaults to `true`** →
`fitToContents` → SwiftUI re-measures and resizes the sheet *after* it is
presented → the hosted view is re-parented → the touch handler desyncs
permanently for that mount. It can also stick at the `.medium` fallback
detent.

**Fix**: on iOS only, pass `enableDynamicSizing={false}`. With no
`snapPoints`, detents fall back to native `['medium','large']` — no
post-present resize, so the bridge never desyncs. Android (Material3) and web
(vaul) were never affected.

Do **not** pass `snapPoints={['medium','large']}` explicitly to express the
same thing: `parseSnapPoint` does not accept those strings, it `parseFloat`s
them to `NaN`.

**The expensive negative result**: this fix is *sufficient on its own*.
Plain RN content — `Pressable`, `TextInput`, `ScrollView` — works reliably
inside the community sheet on iOS once dynamic sizing is off. Rebuilding
sheet content out of `@expo/ui`-native components as a defensive move (the
correct answer for the *universal* sheet) failed three separate ways on
device here — collapsed layout, blank/greedy list, dead buttons — before
being reverted to plain RN. The touch-desync it was defending against had
already been fixed centrally. Give an explicit `snapPoints` (e.g.
`["55%","85%"]`) rather than relying on `fitToContents`, and cap any
scrollable region with `maxHeight`.

`Generalizes:` two components with the same symptom, the same bridge and
different sizing models do not have the same fix. Check which package path
the import came from before applying a remembered remedy.

#### Content shorter than the detent shows the screen through the sheet

A sheet whose native chrome color doesn't match its content shows a
mismatched band around the rounded content card; where a static detent is
taller than the content, the extra gap shows the screen behind through the
**translucent default material** — reading as "washed out" rather than as a
color bug. An all-native content tree with no RN `View` backing has no
content color at all, so the *entire* sheet ghosts.

**Fix**: default `backgroundStyle` to the app's own surface color inside a
shared sheet wrapper, so every sheet's chrome matches content by
construction and callers only override. Then keep inner cards on that same
surface color — an inner card painted a different shade (stark white against
a warm surface, say) reintroduces the band the wrapper just removed. And
size a fixed detent percentage to actually fit: too generous reopens the
gap, too tight clips.

### Universal List

#### The same native-children trap as `BottomSheet` — with a worse failure mode

The universal `List` (SwiftUI `List` on iOS, Compose `LazyColumn` +
`PullToRefreshBox` on Android, a plain scrollable `View` on web) exposes an
`onRefresh: () => Promise<void>` prop that looks like the obvious way to add
pull-to-refresh to an existing screen. It is **not** a safe drop-in
replacement for a `ScrollView` wrapping ordinary RN components — it hits the
same `Children()` rule documented above for `BottomSheet`.

Confirmed by reading the source, not inferred: Android's implementation
(`node_modules/@expo/ui/android/src/main/java/expo/modules/ui/LazyColumnView.kt:84`)
builds each `LazyColumn` `item {}` from the identical
`getChildAt(index) as? ExpoComposeView<*> ?: continue` skip.

The failure is *worse* here than in a `Column`. A `Column` is an
overlapping-layer container, so a skipped RN child still paints (it's merely
untappable). `LazyColumn` is **virtualized** — a skipped child is never
composed at all, so it is silently **dropped from the list entirely**.
Meanwhile iOS's `ListView.swift` hosts children through the same shared
`RNHostView`-bridging `Children()` helper `BottomSheet` uses, so plain RN
children render there normally.

**Net effect**: the screen looks correct on iOS and silently loses its
content on Android — the worst possible split, because iOS-first development
never surfaces it.

**Fix**: don't reach for `List` to bolt a container behavior (pull-to-refresh
or anything else) onto a screen built from ordinary RN components. Use RN's
own `<RefreshControl>` wired to a `ScrollView`'s `refreshControl` prop: no
native-tree constraints, native look and feel on both platforms, no rewrite
of existing screen content.

Rewriting a screen's rows as native `ListItem`s just to satisfy Android would
also mean abandoning your design system for that screen — a bad trade for a
refresh gesture.

**Generalizes**: before adopting an `@expo/ui` *container* for one
convenient prop, check what its Android implementation does with non-
`ExpoComposeView` children. If it's the `?: continue` pattern, the container
only accepts a fully-native subtree, and the prop isn't worth the rewrite.
The cost of the container is never the container — it's everything it forces
its children to become.

### A native container also imposes its VISUAL idiom, not just its children rule

`FieldGroup` is the right control on paper: SwiftUI `Form` on iOS, Material 3
grouped list on Android, and `FieldGroup.Section` gives real native section
headers. Reaching for it to group a flat settings screen is a defensible call and
the reasoning is seductive — a settings screen IS a form, and both platforms ship
`Form` for exactly this.

On Android it renders the M3 **connected list**: a filled rounded container per
section, with *another* rounded card per row inside it. Boxes inside boxes.

That is not a bug. It is Material Design working correctly. But if the design
system it lands in forbids cards, borders, or alternating section backgrounds —
and says hierarchy comes from space and type — then adopting the container quietly
adopts a visual language that contradicts the brief. The screen becomes more
native and less *itself*, and it does so on the one screen where "looks like the
OS" is the most tempting argument.

**Fix**: group with your own primitives (a section header, a row, a 1px rule).
Keep the native control only for LEAF widgets — a Switch, a picker, a date
control — inside your own row. A leaf imposes nothing on its neighbours; a
container imposes on everything it holds.

Dropping the container also drops its constraints, which are easy to forget were
the container's and not the screen's:

- the screen scrolls again (a Compose lazy container needs a BOUNDED height, so
  the screen had `scroll={false}` and the Host could not `matchContents` — get it
  wrong and it is a hard native crash, not a layout glitch);
- anything below the container no longer fights it for height, so a footer line
  is last because it belongs last rather than to survive the fight.

**Generalizes**: this is the same rule as the `Children()` trap above, on a second
axis. That one says the container dictates what its children may BE; this one says
it dictates what they LOOK LIKE. Both collapse to: *the cost of the container is
never the container.* Before adopting one, ask what its platform's design language
will impose — and if your design system has an opinion the platform disagrees
with, the platform will win every argument you did not have on purpose.

Corollary worth its own line: "it's more native" is not automatically "it's
better". Native is a means to feeling right. When a brief has its own identity,
the native default can be the thing that erases it.

### ListItem

#### Rows with no `leading` slot can render broken, even in a fully-native tree

Distinct from the `Children()` rule above — this reproduces with **no** plain
RN ancestor anywhere in the tree, so the usual explanation doesn't apply.

Symptoms, all on iOS, all on rows that omit `leading`:

- The enclosing `Column`'s card `borderRadius`/`borderWidth`/`borderColor`/
  `backgroundColor` simply don't render.
- A `Column` divider between two such rows doesn't render either.
- Adjacent rows' label text shows a stray overlapping glyph at the leading
  edge.

**Fix**: give **every** row a `leading` element, even rows that are purely
informational or icon-less by design (an empty-state notice gets an
`information-circle-outline`; a settings row gets `options-outline`).
Reference sheets that always pass a `leading` icon into every row never
exhibit this; the ones that omit it do.

**Ruled out first**: recalibrating the sheet's static `snapPoints` height.
Raising it made the sheet taller with more dead space and changed nothing
else — which is the useful part, since it proves the bug is not the detent
being too tight to fit content. Don't re-buy that experiment.

**Verification note worth internalizing**: a sheet legitimately sits over
whatever screen is behind it, and that background screen's elements
*correctly* still appear in the accessibility tree at their original
coordinates. That alone is **not** evidence of a z-index or overlap bug —
`describe`-style accessibility output will happily look like two things
overlap when they don't. Confirm a visual glitch with an actual screenshot
before theorizing about layering.

### Host sizing

Every `@expo/ui` universal leaf (`Button`, `TextInput`, `Switch`,
`Checkbox`, ...) renders inside a `Host`, and `Host.matchContents` defaults
to `false` on all axes. With no explicit width/height style on the leaf,
its RN-side view gets an ambiguous size from plain flex layout. Symptoms
are silent, not errors:

- A size-less `TextInput` effectively doesn't render/work.
- A size-less `Switch`/`Checkbox` stretches to fill its row.
- A size-less `Button` doesn't reliably fill its parent even with a "fill"
  style — device-confirmed as a small overflowing pill whose hit-test area
  doesn't match what's drawn (i.e. unclickable, not just ugly).

Pass an explicit `matchContents` hint (or an explicit width/height style)
on the first use of any `@expo/ui` universal leaf, don't assume it "just
fills its parent" the way an RN `View` with `flex: 1` would.

#### The hint has to be chosen per leaf, so it can't live in a shared wrapper

The tempting fix once several primitives wrap `Host` is to set
`matchContents` once, in the shared wrapper. It can't work: **different
leaves need opposite hints**, and the sizing of a `Host` is fixed at mount,
so a hint is ignored entirely when a leaf collapses into an ancestor's
existing `Host`.

What each leaf actually needs, all device-confirmed:

- **`TextInput`** — `matchContents={{ vertical: true }}`: hug height to
  content, still fill the row's width.
- **`Switch`/`Checkbox`** (both wrap SwiftUI `Toggle`) — `matchContents={true}`
  **plus** `style={{ alignSelf: 'center' }}`. They're typically the trailing
  child after a `flex-1` label, so the un-hinted Host stretches and the
  native control overflows; and a `matchContents` Host does *not* reliably
  inherit the parent row's cross-axis centering, so without the explicit
  `alignSelf` the control sits visibly off-center against its label.
- **`Button`** — see below; stretch and hug are different call sites.

**Fix**: give the shared wrapper an optional pass-through
(`useHostWrap(node, hostProps?)`) and set the hint at each primitive, not
once centrally.

`Generalizes:` a wrapper can centralize a *policy* but not a *measurement
contract*. When each consumer's correct value differs, hoisting the setting
into the wrapper just picks a default that's wrong for most of them —
silently, since every failure here is a layout artifact rather than an error.

### Button

**Native `Button`'s `variant` fights a custom `backgroundColor`.**
`variant="filled"`/`"outlined"` paint native chrome (their own
background/shape/insets) *underneath* whatever custom
`style.backgroundColor` you set, producing a mismatched halo/double-chrome
around your custom pill. Use `variant="text"` (`.plain` — no native
chrome) instead, and force the label color explicitly, since `.plain` has
no automatic contrast handling of its own.

A long label on a narrowed custom button (a half-width Confirm/Cancel pair)
then overflows rather than shrinking: add `modifiers={[minimumScaleFactor(0.75)]}`
so SwiftUI shrinks to fit instead of clipping.

#### `width: '100%'` is a silent no-op; "fill" needs a modifier

Two separate traps for the same intent:

- `UniversalStyle.width` **casts straight to `number`** (see
  `transformStyle.ios.ts`), so a percentage string is silently dropped. It
  doesn't warn, it just doesn't apply.
- A size-less `Host` does **not** reliably fill its RN parent in practice,
  whatever the docs imply.

**Fix**: the mechanism that works is the SwiftUI `frame({ maxWidth: Infinity })`
modifier on the `Button`, plus `matchContents: { vertical: true }` on its
Host — the same "fill available width" pattern `@expo/ui`'s own
ScrollView/BottomSheet use internally. Use it for stacked or `flex-1`-half
buttons; omit it (hug, `matchContents: true`) for nav-bar/inline buttons,
which is the canonical `<Host matchContents><Button/></Host>` from the docs.

#### `foregroundStyle` colors the label on iOS and leaves Android invisible

`foregroundStyle` — like everything in `@expo/ui/swift-ui/modifiers` — is a
**SwiftUI modifier with no Jetpack Compose equivalent**. On Android it is a
silent no-op (a platform-split modifier shim resolves the real modifier on
both, but Compose ignores this one), and the universal `Button` never
forwards a content color to Compose either. Net effect: a colored-fill
button whose label is correct on iOS and stays at Material's **dark default
content color on Android** — invisible against a saturated fill. Nothing
errors; iOS review passes.

**Fix**: don't pass the raw modifier from call sites. Expose a `labelColor`
prop on your shared Button that branches — iOS applies
`foregroundStyle(labelColor)`; Android renders the label as a colored
`@expo/ui` `Text` **child** (`textStyle={{ color }}` → native Compose
`Text.color`), since the universal Button uses `children` as its content;
web is unaffected (the modifier is a no-op stub there anyway).

`Generalizes:` **the same missing-content-color-passthrough bug appears
wherever `@expo/ui` forwards one color and not the other** — see
SegmentedControl below, where a `tintColor` paints the active segment but the
label stays Material-dark. Whenever a native prop takes an accent color, ask
what colors the *content* on the other platform, and verify on Android
specifically: iOS's automatic contrast handling hides the bug there.

### SegmentedControl

`@expo/ui/community/segmented-control` only forwards a single `tintColor`
accent — it doesn't also forward a content/label color. iOS's
`UISegmentedControl` already renders a legible active label against any
tint automatically; Android's Material `SegmentedButton` does **not**, so
a custom `tintColor` risks a dark-on-dark unreadable active label on
Android specifically, even though iOS looks fine with the exact same prop.

There is no prop to fix this with. **Fix**: keep the native control on iOS
(its active label is already legible against any tint) and render a plain-RN
pill toggle on Android — a platform-split file, not a runtime branch, since
the two implementations share no props.

### DateTimePicker

`@expo/ui/community/datetime-picker` is self-hosting — no `Host`/wrapper
needed, like `community/bottom-sheet` and `community/segmented-control`.

#### `display` defaults to a compact chip, not the picker you expected

Left unset, the picker renders as a small tappable date/time **chip** rather
than the always-visible control most designs assume. Set it explicitly:
`display="inline"` for `mode="date"`, `display="spinner"` for `mode="time"`
(the classic always-visible wheel).

**`mode="time"` must not auto-commit.** Its continuous scroll fires
`onValueChange` on **every tick**, so a handler that writes straight to the
store on change (fine in date mode) commits dozens of intermediate values as
the wheel spins. Buffer in local state, commit on an explicit Confirm.

`Generalizes:` on iOS a native date/time picker doesn't need a sheet at all —
expanding it inline under the row it edits is fewer moving parts than a
modal, and sidesteps every sheet gotcha above. Keep the sheet path for the
platforms that need it.

#### `mode="datetime"` silently degrades to a date-only picker on Android

No warning, no error: the time half simply is not there. The prop is accepted
and the component renders, so it reads as a layout or styling bug rather than
an unsupported mode.

**Fix**: don't use `mode="datetime"`. Split it into an explicit stepped flow
(`mode="date"`, then `mode="time"`) — also better UX than a compound control
on a phone.

#### An inline picker ignores height and swallows vertical drags

It sizes itself (`matchContents`) and eats the vertical pan, so any scroll
container stops scrolling in the region it occupies.

**Fix**: a screen containing an inline picker must not depend on scrolling to
reach anything. Put the primary action in the **header**, not below the fold.

`Generalizes:` a native control hosted inside RN is a gesture *sink*, not a
gesture participant. Assume it wins every pan inside its bounds, and design
the screen so nothing important sits behind a scroll that crosses it.

### `swift-ui/modifiers` vs `jetpack-compose/modifiers`

**`@expo/ui/swift-ui/modifiers` crashes the web bundle at load if imported
unconditionally.** That subpath calls `requireNativeModule('ExpoUI')` at
module top level with no `.web` fallback — any file that statically
imports from it (`padding`, `frame`, `foregroundStyle`, ...) makes the web
bundle evaluate and throw at runtime the moment that file loads.
`expo export`/a production web build won't catch this at build time —
only actually loading the page will surface it. If a file with this
import is ever reachable on the web build (even indirectly, via another
component importing it), it will throw.

**Fix**: a platform-split shim module — `modifiers.ts` re-exporting the
real thing, `modifiers.web.ts` with no-op stubs of the same functions —
that every call site imports from instead of `@expo/ui/swift-ui/modifiers`
directly. Add new modifiers to the shim as needed rather than reaching for
the crash-prone subpath from a new file.

**`@expo/ui/jetpack-compose/modifiers` does *not* have this problem** —
it's pure JS modifier-config object construction (`createModifier(type,
params)`), no `requireNativeModule`/`requireNativeView` call at import
time. Safe to import unconditionally cross-platform. The risk is
specifically in `@expo/ui/jetpack-compose`'s *component* subpath (actual
native views like `Column`/`Host`/`ModalBottomSheet`), not its modifiers
subpath — see the `.android.tsx` note above for why that distinction
matters.

---

## Widgets (expo-widgets)

An iOS home-screen widget written in JS/TSX looks like an ordinary component
and is not one. Four rules, none of which the shape of the code hints at.

### The `'widget'` directive stringifies your function, so nothing outside it exists

`babel-preset-expo`'s widgets plugin replaces the `createWidget('Name', fn)`
component with **a string of `fn`'s own source**, stored in the App Group and
evaluated natively inside the widget extension. The widget function therefore
runs in a scope that contains only the injected `@expo/ui/swift-ui`
components/modifiers and JS globals.

Everything else is `undefined` at native eval time — **imported theme
constants, outer-scope consts, shared helper functions, design tokens**. It
compiles, it type-checks, and it fails on device.

**Fix**: keep the widget function fully self-contained. Every color and size
is an inline literal; no imports are referenced from inside it.

`Generalizes:` any "directive" that a compiler uses to relocate code to
another runtime (`'use server'`, `'widget'`, worklets) silently voids the
lexical scope you can see. Closures over module scope are the first thing to
break and the last thing you suspect, because the editor shows a valid
reference.

### Never import the widget from cross-platform code

It imports `@expo/ui/swift-ui`, which crashes the web bundle at load (see the
`ExpoUI` entry above). Reach it only through a platform-split bridge:
`widget.ts` a **no-op stub** for web/Android, `widget.ios.ts` importing the
widget and its data builder. App code imports the bridge, never the widget.
That indirection is what keeps `grep -c ExpoUI dist/.../entry-*.js` at `0`.

### Data must be pre-localized in JS

The native widget can't call the i18n runtime. A data-builder function on the
JS side must return **ready-to-render strings** (with icons as SF Symbol
names) rather than keys — which means it duplicates the screen's own
thresholds and selectors, and has to be kept in lockstep with them.

### Refresh is push-based

Nothing pulls. Update the snapshot from a debounced subscription to the
stores the widget mirrors, plus on app foreground. If the widget goes stale,
look for the missing subscription, not for a refresh interval.

---

## Native modules / TurboModules

### iOS registration

For any package with an iOS TurboModule under New Architecture
(`newArchEnabled: true`), **three layers** must all be in place — missing
any one produces a confusing, only-partially-broken state:

1. **Pod autolinking** — `react-native.config.js` at the package root with
   `dependency.platforms.ios.podspecPath`. Makes `use_native_modules!`
   include the pod and generates `autolinking.json`.

2. **Codegen spec** — `codegenConfig` in `package.json` with `name`,
   `type: "modules"`, `jsSrcsDir` pointing at the `Native*.ts` spec file.
   Codegen generates `RNNativeModuleSpec.h` / `-generated.mm`.

3. **`RCTModuleProviders.mm` entry — the non-obvious missing piece.** The
   generator (`node_modules/react-native/scripts/codegen/generate-artifacts-executor/generateRCTModuleProviders.js`)
   requires `codegenConfig.ios.modulesProvider`:

   ```json
   "codegenConfig": {
     "name": "RNNativeModuleSpec",
     "type": "modules",
     "jsSrcsDir": "src",
     "ios": {
       "modulesProvider": {
         "<JS module name>": "<ObjC class name>"
       }
     }
   }
   ```

   Without this, the generator **silently skips the package** (both its
   `modulesProvider` gate and its `parseiOSAnnotations` gate require
   `codegenConfig.ios`). The module still compiles and
   `RCT_EXPORT_MODULE()` still registers it with the Obj-C runtime, but
   `TurboModuleRegistry.getEnforcing(name)` still throws "could not be
   found" at runtime — `RCTAppDependencyProvider.moduleProviders` is built
   from `RCTModuleProviders.mm`, and the entry is simply absent from it.

   - JS module name = the string passed to `TurboModuleRegistry.getEnforcing(...)`
     (`kModuleName` in the generated spec).
   - ObjC class name = the `@implementation` class name (equals the class
     name itself when `RCT_EXPORT_MODULE()` takes no argument).

After any `codegenConfig` change, clean before rebuilding:
```bash
rm -rf ios/build/generated ios/Pods ios/Podfile.lock
```

**Static verification** (worth scripting into CI): after `pod install`,
check `ios/build/generated/ios/ReactCodegen/RCTModuleProviders.mm` — the
module's entry must be present before shipping a build. A missing entry
here is the exact symptom described above and is easy to miss since
everything else compiles cleanly.

### Android registration

`expo-modules-autolinking` **ignores workspace packages that lack an
`expo-module.config.json`** — a monorepo-internal native package can be
completely invisible to it, so `TurboModuleRegistry.getEnforcing(...)`
throws at startup even though the module compiles fine in isolation.

If you can't/don't want to add `expo-module.config.json`, an Expo config
plugin (`app.plugin.js`, run at prebuild time) can inject the required
wiring manually. The pieces a Kotlin/native-module package typically needs:

1. **`settings.gradle`** — `include ':<module>'` with the path to the
   package's `android/` directory.
2. **`app/build.gradle`** — `implementation project(':<module>')` (so the
   compiled AAR + any bundled `.so` lands in the APK), plus
   `externalNativeBuild { cmake { path "..." } }` if the module ships a
   CMake-built native library.
3. **`MainApplication.kt`** — register the package inside
   `PackageList(this).packages.apply { add(YourModulePackage()) }`.
4. **A custom `CMakeLists.txt`** (only if there's a JSI/C++ side) that
   links the codegen'd module spec into `appmodules` and sets a compile
   macro (e.g. `-DREACT_NATIVE_APP_MODULE_PROVIDER=...`) so the default
   `OnLoad.cpp`'s module-provider chain actually calls into your generated
   provider. The stock `OnLoad.cpp` has an `#ifdef` guard for exactly this
   — no custom `OnLoad.cpp` is needed, just the compile-time macro.

All required pieces matter independently: missing the `build.gradle` step
drops the compiled artifact from the APK; missing the `MainApplication.kt`
step means the Java/Kotlin package is never registered; missing the CMake
macro means the C++ side never calls your provider even though the Java
side works fine — each failure mode looks different, so don't assume
fixing one means the others are also fixed.

After any change to a config plugin that does this kind of wiring:
```bash
npx expo prebuild --clean -p android
```
(regenerate the native project from scratch, since prebuild output is
otherwise stale relative to the plugin).

### `expo run:android` does not re-run prebuild when `android/` is checked in

Add a native dependency, run `expo run:android`, and the JS side resolves the
package fine while the native module is **null at runtime**:

```
TypeError: Cannot read property 'setLogLevel' of null
```

which reads as "the SDK is broken" or "the API changed", not "autolinking
never saw it". With a committed `android/` directory, `run:android` treats the
native project as the source of truth and goes straight to Gradle: the new
module is never linked, and nothing says so.

**Fix**: run `npx expo prebuild` explicitly after adding any native dep, then
**verify the autolinking count actually moved** in the build log:

```
Autolinking: 17 modules   ← was 16. Unchanged means prebuild did not run.
```

That count is the cheapest true signal available. A successful build proves
nothing here, because the build succeeds either way.

`Generalizes:` a null native module is almost never a broken SDK — it is a
module that was never registered, so check linkage before debugging the API.
More broadly: in any tool with a generate step and a build step, committing
the generated output silently converts the generate step into a manual one.

**Static verification** — grep the regenerated native project for every
piece the plugin was supposed to inject, e.g.:
```bash
grep "implementation project(':yourmodule')" android/app/build.gradle
grep "externalNativeBuild" android/app/build.gradle
grep "YourModulePackage" $(find android/app/src/main/java -name MainApplication.kt)
grep "include ':yourmodule'" android/settings.gradle
```
`MainApplication.kt` often lives under a variant-suffixed path in Expo
projects — use `find`, don't hardcode the path.

---

## EAS Build

**`eas build --local` (and remote EAS builds) pack the workspace into a
tarball filtered by `.easignore` at the repo root.** The commonly-seen
default `.easignore` excludes all `ios/`/`android/` directories outright,
re-including only `**/modules/**/ios` and `**/modules/**/android` — i.e.
it assumes native code only lives inside Expo config-plugin `modules/`
folders.

**If a workspace package ships its own native source directly** (e.g. an
Objective-C/Swift pod under `packages/some-native-lib/ios/`), that
directory is silently excluded and doesn't exist in the EAS build's temp
directory. Symptoms: `pod install`'s file globs (`ios/**/*.{h,m,mm,swift}`)
match zero files, the pod compiles only its auto-generated dummy source,
and at runtime `NSClassFromString("YourModule")` returns `nil` →
`TurboModuleRegistry.getEnforcing(...)` throws "module provider cannot be
found" — even though a direct `xcodebuild`/local `expo run:ios` from the
actual checkout works perfectly, since the real directory is on disk
there.

**Fix** — explicitly re-include native source under workspace packages in
`.easignore`:
```
# Don't ignore native code shipped by workspace packages
!**/packages/**/android
!**/packages/**/ios
```
(You can still exclude bulky generated subfolders like
`**/ios/Frameworks/**/*` on top of this.)

Generalizes: **any workspace/monorepo package that ships native pod
source directly (not just via a config-plugin `modules/` folder) needs an
explicit `.easignore` re-inclusion**, or EAS builds will pass locally and
fail (or silently produce a broken binary) in CI/cloud builds.

---

## Metro bundler

### A *newly added* export subpath resolves to `dist/` while the old ones resolve to source

A workspace package consumed from source by Metro typically declares an
export map with `source`/`react-native`/`require` → `src/...` and `import` →
`dist/...` (for non-RN consumers). The established subpaths (`.`,
`./components`, `./theme`) resolve from `src` and everything works — so
adding one more per-file subpath looks free. It isn't: the new subpath
resolved to the **unbuilt `dist/` path** on web and broke `expo export
--platform web` with `Unable to resolve module`, while native kept working.

**Fix**: don't add per-file export subpaths for Metro consumers of a
source-resolved workspace package. **Re-export through an existing barrel**
instead.

`Generalizes:` export-map condition resolution is not uniform across a
package's subpaths in practice — a pattern that holds for the entries you
inherited is not evidence it holds for the entry you add. And the platform
that breaks is the one whose conditions you weren't thinking about.

### A platform-extension file importing its own basename resolves to *itself*

`Foo.web.tsx` containing `import { x } from './Foo'` does **not** import
`Foo.tsx`. Platform resolution rewrites `./Foo` to the best match for the
current platform, which on web is `Foo.web.tsx` — the importing file. The
module requires itself.

The symptom points nowhere near the cause:

```
RangeError: Maximum call stack size exceeded
    at Object.get [as someHarmlessExport]
```

The trace names an innocent getter, because that is merely where the cycle
was observed. Nothing mentions platform resolution, and the import looks
obviously correct.

**Fix**: shared types/values for a platform-split component live in a **third,
platform-neutral file**, never in one of the variants.

```
DueDate.tsx        // native variant
DueDate.web.tsx    // web variant
due-date.ts        // shared props/types/defaults — imported by BOTH
```

`Generalizes:` inside a platform-split family, a bare relative import of the
family's own basename is never unambiguous: it means "whichever variant is
resolving right now", which *from* a variant means "me". The `.web`/`.native`
suffix is a resolution **input**, not a filename, so a sibling variant cannot
be addressed by name at all. Anything shared must live outside the family.

### Forcing a specific resolution for a package with problematic dynamic imports

`unstable_enablePackageExports: true` makes Metro follow a package's
`package.json` `exports` map like Node/webpack would. Some packages'
`exports` map points `"import"` at an ESM build that uses patterns Hermes
can't parse — most commonly `import(/* webpackIgnore: true */ '...')` for
conditionally-loaded, environment-specific code (Node-only proxy agents,
optional native fallbacks, etc.). Metro leaves those dynamic `import()`
calls verbatim in the native bundle, and Hermes throws a hard compile-time
error (`Invalid expression encountered`) trying to parse them.

**Fix**: intercept resolution for that specific package in
`metro.config.js`'s `resolveRequest` and force it to the package's CJS
build (which typically has none of these dynamic imports) on native
platforms only, leaving the default (ESM) resolution alone for web:

```js
config.resolver.resolveRequest = (context, moduleName, platform, ...) => {
  if (moduleName === 'problematic-package' && platform !== 'web') {
    return { type: 'sourceFile', filePath: pathToItsCjsBuild }
  }
  return context.resolveRequest(context, moduleName, platform)
}
```

After upgrading a package fixed this way, re-verify the assumption still
holds (e.g. `grep -c "webpackIgnore" node_modules/pkg/dist/cjs/pkg.js`
should still return `0`) — a new release could reintroduce the same
dynamic-import pattern into the CJS build too.

### A custom sync/build script must cover every dist root Metro might resolve to

If a project vendors a WASM (or any other multi-target) build with a
custom "sync artifacts to N dist roots" script, and Metro's actual runtime
`import()` resolves relative to a *specific* one of those roots, missing
that root from the sync script's target list makes Metro silently fall
back to a *different*, stale root — often one still containing
build-tool-specific syntax (e.g. `import.meta.url` from a `wasm-pack`
output) that Hermes can't execute (`Cannot use 'import.meta' outside a
module`). The error message points at the *symptom* (the unsupported
syntax), not the actual cause (the sync script's target list being
incomplete) — check every dist root Metro could plausibly resolve to
against what the sync script actually writes, not just the one you expect
it to use.

Also: don't wrap a native/WASM module's dynamic loader in a silent
`try/catch` "just in case" — it hides the fact that a required
initialization step (e.g. installing a polyfill that depends on the WASM
module) never ran at all, which surfaces as a much more confusing failure
much later (some unrelated built-in — `crypto`, `Buffer`, etc. — is
simply missing, with no indication why).

### A dependency that patches globals at *module load* must not sit on the boot graph

Some native-crypto packages (`react-native-quick-crypto` is the common one)
call their own `install()` at module top level, which patches
`globalThis.crypto` and `Buffer`. If your app already installs its own
crypto polyfills (a Rust/JSI bridge, a WASM module, a JS shim), you now have
two things racing to own the same globals, and which one wins depends on
module evaluation order — i.e. on import graph details nobody is tracking.

**Fix**: `import()` such a package **lazily, at the point of use** (behind
the first user action that actually needs it), never as a static top-level
import from anything reachable at boot. Keep it off the boot graph entirely
and the race can't happen.

The reverse direction matters too: after adding a globals-patching package,
re-verify the features that depend on *your* polyfills (crypto-backed
unlock, signing, hashing) still work with it present, on a real device
build. Both polyfill sets can be individually correct and still break each
other.

Related, same package class: a dep that requires **WebAssembly** (e.g.
`hash-wasm`) cannot run on Hermes, which has no WASM. If a library pulls one
in transitively, alias it to a pure-JS equivalent for native only in
`metro.config.js`'s resolver, leaving web on the real (fast) WASM build.

**Generalizes**: treat "patches globals at import time" and "needs WASM" as
**properties of the import graph**, not of the call site. Both are invisible
in the code that consumes the library, and both are fixed in the resolver or
by moving the import — not by anything you can write at the point of use.

### A redbox about a module you don't even depend on means you loaded another app's bundle

Two RN repos on one machine, both with plain debug builds: every debug
build bakes `localhost:8081` as its Metro origin. Whichever project's
Metro owns 8081 serves *its* bundle to *any* debug app that connects. The
symptom is disorienting: the app redboxes about native modules that are
not in your `package.json` at all (`react-native-quick-crypto`, Skia
components from the other product). Nothing is wrong with your code — you
are executing someone else's JS.

Ruled out first, expensively: reinstalling pods, wiping DerivedData,
reinstalling the app. None of it can help, because the build is fine; the
*port* is the identity.

**Fix**: either give each project its own Metro port (and rebuild, since
the port is baked in at build time), or install `expo-dev-client`, which
adds a launcher UI that can point at any Metro URL at runtime without
rebuilding.

**Generalizes**: when an error names code you don't own and can't find in
your lockfile, stop debugging your app and ask *whose bundle you are
actually running*. On a shared machine, `lsof -nP -iTCP:8081` before
anything else.

---

## Expo CLI & dev-client builds

### expo-dev-client link failure on prebuilt RN core: RCTPackagerConnection / ShadowNode::getDebugName not found

On an SDK that ships React Native as a prebuilt XCFramework (SDK 57 era,
`RCT_USE_PREBUILT_RNCORE=1` default), adding `expo-dev-client` breaks the
iOS link step:

```text
ld: symbol(s) not found for architecture arm64
  RCTPackagerConnection, RCTReconnectingWebSocket,
  facebook::react::Sealable, ShadowNode::getDebugName
```

The prebuilt core is a *release-flavored* artifact: it omits the
dev-support symbols that dev-client (and anything else touching the
packager connection or debug shadow-tree APIs) links against.

Negative result worth keeping: a full clean rebuild + DerivedData wipe
does **not** fix it — this is not stale-artifact corruption, the symbols
genuinely are not in the prebuilt binary.

**Fix**: build RN from source for this app:

```bash
RCT_USE_PREBUILT_RNCORE=0 pod install
RCT_USE_PREBUILT_RNCORE=0 npx expo run:ios --scheme <Scheme>
```

Both steps need the env var — pod install decides the dependency graph,
the build decides what actually compiles.

**Generalizes**: prebuilt vendor binaries are built with *one* flavor's
feature set. Any missing-symbol error whose names smell like dev tooling
(`*Packager*`, `*Inspector*`, `*Debug*`) on an otherwise-correct setup
means the prebuilt artifact excluded that flavor — switch to a source
build rather than hunting a config bug in your own project.

### `npx expo run:ios` without `--scheme` dies silently in non-interactive shells

With more than one Xcode scheme in the workspace, `expo run:ios` prompts
for a scheme. In a non-TTY context (agents, CI, anything piped) it
instead exits with `Input is required, but 'npx expo' is in
non-interactive mode` — and if the command is piped through `| tail`, the
pipeline's exit code masks the failure and it looks like a successful
no-op build.

**Fix**: always pass `--scheme <Scheme>` explicitly, and never pipe a
build command's output through anything that eats its exit status (use
`set -o pipefail` or redirect to a file instead).

**Generalizes**: any Expo CLI command that *can* prompt will hard-fail in
non-interactive mode; pass every answer as a flag. And in automation,
`cmd | tail` converts failures into silent successes.

### `npx expo install` run from the monorepo root scaffolds a phantom app

In a pnpm monorepo, running `npx expo install <pkg>` from the *root*
(instead of the app workspace) does not error — it treats the root as an
Expo project: writes a root `app.json` with a wrong bundle id, adds
`expo`/`react`/`react-native` to the root `package.json`, and can leave a
stray root `ios/` scaffold. Everything keeps building, so the pollution
is only noticed later in diffs.

**Fix**: run `expo install` only from the app's own directory. Clean-up
if it happened: revert root `package.json`, delete the root `app.json`
and stray `ios/`, then re-run the workspace install to reconcile the
lockfile.

**Generalizes**: Expo CLI decides "what project am I in" from cwd alone
and will happily *create* the missing pieces. In a monorepo, any
project-mutating CLI belongs in the workspace directory, never the root.

---

## expo-audio

### play() before the player reports isLoaded is silently dropped

`useAudioPlayer()` + an effect that calls `player.play()` on mount plays
nothing — no error, no state change — when the source hasn't finished
loading yet. A ref-based "already started" guard then prevents any retry,
so autoplay never happens at all.

**Fix**: gate autoplay on the player's loaded state
(`status.isLoaded`), and let the effect re-run when it flips:

```ts
useEffect(() => {
  if (!isLoaded || startedRef.current) return;
  startedRef.current = true;
  player.play();
}, [isLoaded]);
```

**Generalizes**: media APIs whose commands are no-ops (rather than
errors) before readiness turn "fire on mount" into a race you lose on
cold cache. Any autoplay path must subscribe to the readiness signal, not
assume it.
