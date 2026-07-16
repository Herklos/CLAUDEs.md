---
name: herklaude-skills
description: Personal cross-project knowledge base of non-obvious gotchas, each one costing real debugging time and none of them written in the official docs. Consult BEFORE debugging or implementing anything touching Expo (expo-router, @expo/ui, Metro, EAS, config plugins), React Native (New Architecture, TurboModules, Hermes, JSI, native bridges), i18n, in-app purchases (RevenueCat, StoreKit, Play Billing), ASO and store listings, Maestro E2E flows, offline sync and local-first storage, web3 transaction signing, or frontend UI patterns. Also use when a symptom crosses layers, when an error message seems to point at the wrong cause, or when observed behavior contradicts what the library documents. Use it again at the end of such a session to record what was learned.
---

# herklaude-skills

A knowledge base of gotchas that survived a real debugging session. Every
entry is something the library's own docs do not say. Reach for it *before*
guessing, and *after* learning.

## Find the notes

The notes are the `*.CLAUDE.md` files two directories above this skill's own
directory, whether this was installed as a plugin or symlinked by hand.
Resolve it once per session, substituting the base directory given to you
when this skill was invoked:

```bash
KB="$(cd -P "<this skill's base directory>" && cd ../.. && pwd)"
ls "$KB"/*.CLAUDE.md
```

The `cd -P` matters: under a hand symlink the base directory is a link, and
only the physical path has the notes as its grandparent.

That `ls` is the index. There is deliberately no hardcoded list of topics
here, because a list would be a second place to forget to update.

## Read it symptom-first

1. **Grep the exact string you are staring at** — the error text, the API
   name, the symptom. H3 headings are written as symptoms or assertions
   precisely so this hits:
   ```bash
   grep -rin "<exact error or symptom>" "$KB"/*.CLAUDE.md
   ```
2. **Hit** → open that file's `## Contents`, then read *only* the matching
   section.
3. **No hit** → read the `## Contents` of the topic file that covers the
   subsystem, and scan the H3 titles. A miss is a normal outcome; the base
   is small and opinionated, not exhaustive. Go back to debugging.
4. **Never read a whole topic file blind.** `expo.CLAUDE.md` alone is ~900
   lines. `## Contents` first, always.

## Read the Generalizes line

Entries carry `**Fix**:` and often `**Generalizes**:`. The `**Generalizes**:`
line lifts the specific bug into a reusable rule — it can apply even when
your symptom does not match the entry's. It is usually the most valuable
line in the entry.

Entries also record ruled-out hypotheses and negative results ("tried X,
it did not help, which proves the cause was not Y"). Do not skip those:
they are the expensive half, and they save you from re-buying it.

## When you learn something new

If this session cost real time on something non-obvious, and the official
docs would not have told you, add it. Read `$KB/CLAUDE.md` first — it holds
the bar for an entry, the file format, the entry style, and the
de-projectify rule (strip product names, internal component names, and
`src/...` paths; keep the mechanism and the symptom chain). Extend an
existing topic file when one fits; a new `<topic>.CLAUDE.md` is only for a
genuinely new subsystem. Keep that file's `## Contents` in sync.
