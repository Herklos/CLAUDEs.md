# Maestro — tips, gotchas & reference notes

Curated from writing and debugging a mobile E2E suite with Maestro. Short by
design: these are the syntax and selector rules that cost time because
Maestro's YAML fails in ways that don't point at the mistake.

## Contents

1. [Selectors](#selectors)
2. [Flow file syntax](#flow-file-syntax)

---

## Selectors

**Prefer `id:` (testID) over `text:` for every interaction.** A `text:`
selector couples the test to copy, which means it breaks on any wording
change and — worse — on any locale change. A suite written against `text:`
can only ever run in the source locale.

---

## Flow file syntax

Each of these is a real rule that a plausible-looking flow gets wrong:

- **`onFlowStart:` / `onFlowComplete:` hooks belong in the config section,
  *before* the `---` separator** — not among the steps after it. Placed after,
  they're read as steps and don't run as hooks.
- **`scrollUntilVisible` requires an `element:` wrapper.** `tapOn` and
  `assertVisible` do **not** take one. The inconsistency is the trap: the
  selector shape you just used on the line above is wrong on this line.
- **`assertVisible` / `assertNotVisible` do not support a `timeout:`
  property.** Adding one looks reasonable and silently doesn't do what you
  want.
- **`runFlow` paths are relative to the *current file*, not the workspace
  root.** Don't start them with your test directory's own name — that path
  only resolves from the root you're imagining, not from where the file
  actually sits.

**Generalizes**: Maestro's YAML has per-command shape rules rather than one
uniform selector grammar, and an unknown/misplaced key tends to be ignored
rather than rejected. So a wrong flow reads as a *failing test* (element not
found, assertion passed vacuously), not as a syntax error — check the command
reference for the specific command before assuming its shape matches the one
next to it.
