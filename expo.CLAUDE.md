# Expo — tips, gotchas & reference notes

Curated from real debugging sessions (Astrolab2/mobile2, an Expo Router +
New Architecture RN app using `@expo/ui`, custom TurboModules, and a
Rust/JSI native bridge). Organized by subsystem so a specific problem class
is easy to jump to.

## Contents

1. [expo-router](#expo-router)
2. [@expo/ui](#expoui)
   - [Universal BottomSheet](#universal-bottomsheet)
   - [Universal List](#universal-list)
   - [ListItem](#listitem)
   - [Host sizing](#host-sizing)
   - [Button](#button)
   - [SegmentedControl](#segmentedcontrol)
   - [swift-ui/modifiers vs jetpack-compose/modifiers](#swift-uimodifiers-vs-jetpack-composemodifiers)
3. [Native modules / TurboModules](#native-modules--turbomodules)
   - [iOS registration](#ios-registration)
   - [Android registration](#android-registration)
4. [EAS Build](#eas-build)
5. [Metro bundler](#metro-bundler)

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

### Button

**Native `Button`'s `variant` fights a custom `backgroundColor`.**
`variant="filled"`/`"outlined"` paint native chrome (their own
background/shape/insets) *underneath* whatever custom
`style.backgroundColor` you set, producing a mismatched halo/double-chrome
around your custom pill. Use `variant="text"` (`.plain` — no native
chrome) instead, and force the label color explicitly, since `.plain` has
no automatic contrast handling of its own.

### SegmentedControl

`@expo/ui/community/segmented-control` only forwards a single `tintColor`
accent — it doesn't also forward a content/label color. iOS's
`UISegmentedControl` already renders a legible active label against any
tint automatically; Android's Material `SegmentedButton` does **not**, so
a custom `tintColor` risks a dark-on-dark unreadable active label on
Android specifically, even though iOS looks fine with the exact same prop.

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
