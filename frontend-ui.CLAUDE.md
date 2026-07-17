# Frontend UI house rules — tips, gotchas & reference notes

Curated from one design-system-driven app (React Native + NativeWind, a
token-based theme, a shared primitive layer). Unlike the other files here,
this is **not** a set of platform bugs — it's a house-rule set, offered as a
starting position to adopt or argue with, not as universal law.

Each rule earned its place by being violated first. Where the violation's
symptom is known, it's recorded — that's the part that makes a rule
defensible rather than arbitrary.

## Contents

1. [Tokens only](#tokens-only)
2. [Reuse first](#reuse-first)
3. [Hierarchy](#hierarchy)
4. [Critiquing AI-generated UI with a design vocabulary](#critiquing-ai-generated-ui-with-a-design-vocabulary)
   - [Beware of utilitarian AI design](#beware-of-utilitarian-ai-design)
5. [Honest data](#honest-data)
6. [Routes are containers](#routes-are-containers)
7. [Legible indicators](#legible-indicators)
8. [Rendering the same thing twice](#rendering-the-same-thing-twice)
   - [The same gradient stops draw a quarter-turn apart in Skia and in CSS](#the-same-gradient-stops-draw-a-quarter-turn-apart-in-skia-and-in-css)
9. [Verifying themes](#verifying-themes)
   - [Forcing `prefers-color-scheme` over CDP manufactures a contrast bug that isn't there](#forcing-prefers-color-scheme-over-cdp-manufactures-a-contrast-bug-that-isnt-there)
10. [Adapt with props, not parallel screens](#adapt-with-props-not-parallel-screens)
11. [Typography primitives](#typography-primitives)

---

## Tokens only

All visual values come from the theme's tokens — colors, typography, radii,
spacing, shadows. **No raw hex, no px radii, no font-family strings** in
component code.

Static styles go through the styling system (`className` for NativeWind);
inline `style` is reserved for values genuinely derived from tokens at
runtime.

The point isn't tidiness. A raw hex is a value that can never participate in
a theme change, and it's invisible in review — it looks like every other
literal. One escape hatch per file is how a design system stops being one.

---

## Reuse first

Before writing UI, check the shared layers in order: pure presentation
primitives, then minimal-domain shared components, then the domain-yet-
reusable ones. Most "new" components are an existing one plus a prop.

**Extract when a pattern appears in 2+ places** — into the pure-presentation
layer if it has no domain knowledge, the minimal-domain layer otherwise.

**Prefer slot props (`ReactNode`) over rigid sub-structures.** A component
that takes `leading`/`trailing`/`children` slots survives the next design; one
that takes `iconName`/`badgeCount`/`subtitleText` acquires a new prop every
sprint and eventually encodes every caller.

---

## Hierarchy

**Card variants encode hierarchy — use them to say what matters, not to
decorate.**

- `hero` (heaviest treatment): **one per screen**, top datum only.
- `strong`: secondary feature cards (allocation, KPIs).
- default, unpadded: list containers.

Two heroes on a screen means neither is a hero. The variant is a claim about
importance, and claims compete.

---

## Critiquing AI-generated UI with a design vocabulary

**Don't ask for "make it look nicer" — critique a screenshot against a
named checklist instead.** An agent assembling a layout has no eyes: it
can't judge whether the *result* reads as harmonious, and a static
`visual-design.md` skill file doesn't fix that either, because "looks
harmonious" isn't checkable from source. Take a screenshot of the actual
render, critique it against the eight axes below one at a time, and ask for
a revision — naming the specific axis that's off, not a general impression.

The eight axes, as vocabulary to critique with:

- **Contrast** — differences in size/color/weight/shape create hierarchy;
  without it everything competes equally and nothing stands out.
- **Hierarchy** — size, position, color, and weight signal "look here
  first," in the order that matters (distinct from the [Hierarchy](#hierarchy)
  house rule above, which is one specific application of this).
- **Alignment** — shared edges/axes read as related and intentional; its
  absence looks sloppy immediately.
- **Proximity** — white space between groups signals what belongs together,
  no borders or boxes needed.
- **Repetition** — reused colors/fonts/shapes/spacing patterns read as one
  system instead of several independent decisions.
- **Balance** — visual weight distributed across the composition
  (symmetric or asymmetric, either works); an unbalanced layout feels off
  even when nothing is individually wrong.
- **White space** — negative space is active, not empty; it's what
  determines whether a design feels premium, calm, or cluttered.
- **Unity** — the sense that every element belongs. It isn't a separate
  technique — it's what emerges when the other seven are already agreeing
  with each other.

**Generalizes**: an agent given a screenshot plus this checklist revises
substantially better than one given a vague aesthetic prompt, because each
axis is independently falsifiable against the image. Naming the axis you're
unhappy with (not just "polish this") is what turns the critique into
something an agent can act on.

### Beware of utilitarian AI design

**Never treat your own first pass as the deliverable.** A first pass is a
feature-complete skeleton, not a finished screen — every requirement met,
every control present, every state rendered, nothing *wrong* — which is
exactly why it's tempting to stop there. It is optimized for "satisfies the
spec," not "creates a feeling," and it will read as flat and forgettable
even though nothing on it is broken. Run it through the eight-axis critique
above, then go back and add the nuance the spec never asked for.

Concretely: don't reset context between steps of a flow. A checkout that
shows only the current step, with no recap of price/dates/selection already
chosen, is functionally correct and still uninviting — carry that context
forward at each step instead.

**Generalizes**: an unrevised AI-first draft is recognizable as one
immediately, and at scale it makes an app indistinguishable from every other
AI-assisted app shipped this cycle. Budget an explicit second pass for
nuance — don't fold it into the first pass's spec, and don't skip it because
the first pass technically works.

Source: [Expo — How to apply professional design principles in AI app
development](https://expo.dev/blog/how-to-apply-professional-design-principles-in-ai-app-development)

---

## Honest data

**Never render `+0.00%`, `$0.00`, or a fake sparkline for a source that isn't
wired up.** It doesn't read as "empty" — it reads as *broken*, or worse, as a
real value that happens to be zero. A user cannot distinguish "no data yet"
from "your balance is zero" and will act on the difference.

- Show `—` for a genuinely absent value (a delta component should do this at
  `value === 0` by default).
- Hide sparklines/charts until real data exists rather than drawing a
  plausible fake.
- On data-rich dashboards, **keep the panel structure and gray out the
  missing values.** Replacing rich panels with a thin stat strip while data
  is unwired reads as a regression — the screen appears to have *lost*
  features rather than to be loading.

**Generalizes**: placeholder UI is a statement about reality, and users read
it as one. The question isn't "does this look finished", it's "what does this
claim, and is the claim true".

---

## Routes are containers

Route files wire **data, state, and navigation only**.

- Extract any JSX fragment over ~15 lines, or used in 2+ places.
- Target under ~150 lines per route.

A route that renders is a route that can't be reasoned about at a glance, and
route files are exactly where merge conflicts and one-off drift concentrate.

---

## Legible indicators

**Pair any iconographic rank with a short text label adjacent to it** — dots,
bars, status pips, lock/clock glyphs. `●●○ Intermediate`, `🔒 Premium`,
`⏱ Soon`.

A naked indicator is inscrutable on first read (the reader has to infer the
scale from a single sample) and invisible to assistive tech.

**Don't repeat the same label in two slots** — title row *and* trailing
column. Pick the slot adjacent to the indicator; the redundancy is noise that
crowds out the datum.

---

## Rendering the same thing twice

### The same gradient stops draw a quarter-turn apart in Skia and in CSS

A signature shape implemented once for native (Skia) and once for web (CSS) can
share its maths, its colours, and its stops exactly — and still be visibly
different, with no error and nothing to grep.

Sweep/conic gradients disagree on where zero is:

- Skia `SweepGradient` with `start={0}` begins at **3 o'clock** (the positive
  x-axis).
- CSS `conic-gradient` with no `from` begins at **12 o'clock**.

Identical stops therefore land 90° apart. The colour that should sit left sits at
the bottom, so the object appears lit from a different direction on each platform.
Both look plausible alone; only side by side is it obvious, and the two rarely
appear side by side.

**Fix**: `conic-gradient(from 90deg, ...)` to move CSS's origin to Skia's.

Two adjacent notes from the same component, both cheap and both easy to get wrong:

- **A closed stop list has no seam.** `[a, b, a]` wraps cleanly at any origin
  because the wrap point is `a` meeting `a`. If the first and last stop differ, a
  hard radial seam cuts the shape at whatever angle zero happens to be — which is
  a different angle per renderer, per the above.
- **A fixed-pixel detail makes a primitive non-scale-invariant.** A 4px curve is
  2.2% of a 180px shape and 1.5% of a 260px one, so the shape flattens as it
  grows and the largest instance carries the weakest version of the detail — worst
  exactly where it is most looked at. Express such details as a FRACTION of the
  size, pinned by a test that normalises the path by size and asserts the ratios
  agree across sizes.

**Generalizes**: sharing the maths between two renderers does not make them agree.
Every renderer has its own conventions for origin, winding direction, and units,
and they are silent — nothing throws, both outputs are individually reasonable.
When one artefact has two implementations, pin the AGREEMENT in a test on the
shared layer (normalised ratios, closed stop lists), because the drift is a design
regression that no type checker or unit test of either side will catch.

## Verifying themes

### Forcing `prefers-color-scheme` over CDP manufactures a contrast bug that isn't there

Driving a running app and flipping the emulated colour scheme after load shows
invisible text, washed-out headings, "unreadable" body copy — a screenful of
convincing accessibility failures that **do not exist** in a real browser.

The emulation repaints what CSS owns (the background) while the JS theme
context keeps the value it read at mount, so foreground colours stay on the
old theme. You are looking at dark text on a dark background that no user can
ever produce, because a real user's preference is known *before* React mounts.

**Fix**: set the colour scheme when launching, or reload after forcing it.
Then reproduce anything you find in a clean browser **before** believing it.

`Generalizes:` an emulated environment change applied *after* load only reaches
the layers that re-read it continuously. Anything cached at startup — a theme
context, a media-query value read once, a locale, a feature flag — silently
keeps the old value, and the resulting half-updated state is an artefact of
your tooling. Cost a full cycle chasing a contrast bug that was never in the
app. Suspect the harness before the app when a failure is *too* dramatic to
have gone unnoticed.

## Adapt with props, not parallel screens

Two-state variants of the same screen — "has node" vs "no node", "empty" vs
"filled" — belong in **one component with a prop**, not sibling components.

Forked screens drift. Not immediately, which is what makes it insidious: they
start identical, then one gets a spacing fix, then the other gets a new
field, and six months later they're two designs that nobody decided on.

---

## Typography primitives

### A digit renders as "U" — the glyph is vertically clipped by a stale lineHeight, not a broken font

A stats counter showed "U" where "0" should be. Two wrong theories cost the
session real time: (1) iOS substituting a fallback face when a loaded custom
font is asked for a synthesized weight, (2) the font lacking `tnum` support
for `fontVariant: ['tabular-nums']`. Both were ruled out when a second,
differently-styled numeral broke the same way.

The actual cause: the shared `Heading`/`H2` text primitives hardcoded
`lineHeight` **derived from their default fontSize** (`fontSize * 1.05`).
Callers overrode `fontSize` upward through the style prop; the default
lineHeight stayed, and RN clips a text node to its lineHeight — the top arc
of the "0" was cut off, leaving a "U". Letters mostly survive (ascenders
clip subtly); round digits are where it becomes legible as the wrong glyph.

**Fix**: in the primitive, scale the default lineHeight with the overridden
fontSize instead of freezing it:

```tsx
function scaledLineHeight(style: TextStyle | undefined, ratio: number, fallback: number) {
  return typeof style?.fontSize === 'number' ? style.fontSize * ratio : fallback;
}
// lineHeight: scaledLineHeight(style, 1.15, DEFAULT_SIZE * 1.05)
```

Callers passing an explicit lineHeight still win (style merges after).

**Generalizes**: any text primitive that sets BOTH fontSize and lineHeight
defaults invites this bug the moment a caller overrides only one of them.
When a glyph looks "wrong" only at certain sizes, suspect clipping before
suspecting the font: compare fontSize against the effective lineHeight
first — it is a one-line check, and font-substitution theories are a
rabbit hole.
