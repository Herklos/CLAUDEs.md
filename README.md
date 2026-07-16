# CLAUDEs.MD

A cross-project knowledge base for coding agents. Each file collects the
non-obvious things one subsystem cost real debugging time to learn, written
so that a session on *any* codebase can use them.

The bar for an entry is deliberately high:

> Non-obvious, cost real debugging time, and would **not** be rediscovered by
> reading the library's own documentation.

If the official docs already say it plainly, it does not belong here. This is
not a docs mirror and not a tutorial collection.

## What is in it

One file per topic, named `<topic>.CLAUDE.md`, flat at the repo root:

```bash
ls *.CLAUDE.md
```

That listing is the index, on purpose. There is no index file, because it
would be a second place to forget to update. Each topic file carries its own
`## Contents`.

Headings are written as symptoms, not as noun phrases ("Plain RN content is
not reliably tappable on either native platform", not "RN content
tappability"), so that grepping the exact string you are staring at tends to
land on the entry you need:

```bash
grep -rin "the error text you are debugging" *.CLAUDE.md
```

Entries carry a `**Fix**:` line, and usually a `**Generalizes**:` line that
lifts the specific bug into a reusable rule. The `**Generalizes**:` line is
often the most valuable part, since it can apply even when your symptom is
not quite the one described. Entries also record the hypotheses that were
ruled out and the negative results ("tried X, it did not help, which proves
the cause was not Y"), because that is the expensive half of a debugging
session and the half no documentation ever carries.

## Using it with Claude Code

The repo doubles as a Claude Code plugin marketplace. In any session:

```
/plugin marketplace add Herklos/CLAUDEs.MD
/plugin install herklaude-skills@herklos
```

The notes ship with the plugin, so there is nothing else to clone. Pull
later updates with `/plugin update herklaude-skills`, and remove it with
`/plugin uninstall herklaude-skills`.

Once installed, Claude pulls the relevant file in on its own when a task
touches a covered subsystem, and you can also invoke it directly with
`/herklaude-skills`.

### Installing from a local clone instead

If the knowledge base is yours and you edit it, install from a clone so that
your edits apply immediately rather than at the next `/plugin update`:

```bash
git clone https://github.com/Herklos/CLAUDEs.MD.git
cd CLAUDEs.MD
./install.sh     # ./uninstall.sh to remove
```

This symlinks `skills/herklaude-skills/` into `~/.claude/skills/`. Because
it is a symlink and not a copy, the clone can live anywhere, but it should
stay where you put it. Move the clone and you rerun the installer. Pick one
route or the other, not both, or the skill is registered twice.

Nothing here depends on the skill either way. The files are plain markdown,
so pointing any agent or any human at the directory works too.

## Contributing

`CLAUDE.md` holds the conventions: the bar for an entry, the file format, the
entry style, and the de-projectify rule that strips product names, internal
component names, and `src/...` paths while keeping the mechanism and the
symptom chain intact. Read it before adding anything.

Extend an existing topic file when one fits. Create a new
`<topic>.CLAUDE.md` only for a genuinely new subsystem, and keep that file's
`## Contents` in sync with its headings. One strong entry beats three weak
ones. A file people trust is one where every entry earned its place.
