# CLAUDEs.MD — how this repo works

A cross-project knowledge base. Each file collects the non-obvious things one
subsystem cost real time to learn, de-projectified so a session on *any*
codebase can use them.

This is not a docs mirror and not a tutorial collection. The bar for an entry:

> Non-obvious, cost real debugging time, and would **not** be rediscovered by
> reading the library's own documentation.

If the official docs already say it plainly, it doesn't belong here.

## Layout

Flat. One file per topic, named `<topic>.CLAUDE.md` at the repo root. The
category lives in the filename prefix, not in a folder tree.

There is no index file, and there should not be one — it would be a second
place to forget to update. Each file carries its own `## Contents`.

The exception to the flat layout is the packaging that makes this base
reachable from a session on any codebase, as a Claude Code plugin:

- `skills/herklaude-skills/SKILL.md` — the skill itself.
- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — the repo
  is its own single-plugin marketplace (`/plugin marketplace add
  Herklos/CLAUDEs.md`).
- `install.sh` / `uninstall.sh` — the alternative route, symlinking
  `skills/herklaude-skills` into `~/.claude/skills/` so local edits apply
  with no `/plugin update`.

`SKILL.md` lists no topics on purpose — it globs `*.CLAUDE.md`, which keeps
it from becoming the index this repo refuses to have. It finds the notes two
directories above its own, which holds under both routes; keep that depth if
you ever move things. Adding a topic file therefore needs no change there.
Only the `description` needs a keyword added when a new topic introduces a
genuinely new subsystem, since that description is what makes the skill fire.
Bump `version` in *both* `.claude-plugin` files together when the skill
changes, or marketplace users will not be offered the update.

## File format

- **H1**: `# <Topic> — tips, gotchas & reference notes`
- **Provenance paragraph** (3-5 lines) right under the H1: "Curated from real
  debugging sessions (...)". Name the *shape* of the source project (e.g. "an
  Expo Router + New Architecture RN app with custom TurboModules"), not its
  business domain. State the organizing principle. This paragraph is the one
  place a product name is allowed to appear.
- **`## Contents`**: numbered list of the H2 sections as markdown anchors, with
  nested bullets for H3s.
- **`---`** between each H2 section.
- **H2** = a subsystem (`expo-router`, `Metro bundler`, `Tombstones`).
- **H3** = *one* gotcha, titled as a **symptom or an assertion** — not a noun
  phrase. Write "Plain RN content is not reliably tappable on either native
  platform", not "RN content tappability". The title is what makes an entry
  findable when someone greps their exact symptom.
- Prose hard-wrapped at ~76 columns. Code fences always language-tagged.

## Entry style

The shape that works:

1. **The symptom chain** — what you saw, and what the failure actually was
   underneath. Include the misleading part: which layer's error message pointed
   at the wrong cause.
2. **`**Fix**:`** — the prescription, with code where code is clearer.
3. **`Generalizes:`** — lift the specific bug into a reusable rule. This is the
   move that turns one debugging session into transferable knowledge, and it is
   the reason this repo exists rather than a pile of bug reports.

Bolded `**Rule**:` / `**Fix**:` / `**Generalizes**:` lead-ins. Italics on the
pivotal word.

**Record the ruled-out hypotheses and the negative results.** "Tried X first, it
didn't help, which proves the cause wasn't Y" is the expensive half of the
session and the half no documentation ever carries. Deleting it as noise means
the next person re-buys it.

## The de-projectify rule

Strip product names, internal component names, and `src/...` paths. Keep the
mechanism and the symptom chain — those are what make an entry findable and
actionable.

Name the **shape** of a thing over its internal identifier: "a store factory
wrapping zustand `persist`", not the vendor package's name; "a relative-time
formatting helper", not `useFormatRelativeTime()`. Keep third-party names that a
reader would grep for (`@expo/ui`, Hermes, FlashList, noble) — those are the
index, not the leak.

Vendor file paths and line numbers *inside `node_modules`* are worth keeping when
they're the evidence for a claim: they let the next reader re-verify against a
newer version instead of trusting a stale assertion.

## Adding knowledge

- Extend an existing topic file if one fits. Create a new `<topic>.CLAUDE.md`
  only for a genuinely new subsystem.
- Keep the file's `## Contents` in sync with its headings. That's the only
  invariant a reader can't recover by just reading the file, so it's the one
  worth being strict about.
- Prefer one strong entry over three weak ones. A file people trust is one where
  every entry earned its place.
