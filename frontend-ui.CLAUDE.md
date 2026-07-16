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
4. [Honest data](#honest-data)
5. [Routes are containers](#routes-are-containers)
6. [Legible indicators](#legible-indicators)
7. [Adapt with props, not parallel screens](#adapt-with-props-not-parallel-screens)

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

## Adapt with props, not parallel screens

Two-state variants of the same screen — "has node" vs "no node", "empty" vs
"filled" — belong in **one component with a prop**, not sibling components.

Forked screens drift. Not immediately, which is what makes it insidious: they
start identical, then one gets a spacing fix, then the other gets a new
field, and six months later they're two designs that nobody decided on.
