# App store optimization — tips, gotchas & reference notes

Curated from a store-listing optimization pass on a French-first,
privacy-positioned consumer app shipping to both the Apple App Store and
Google Play. Organized by the mechanism that constrains the copy, not by the
copy itself: the two stores index metadata in opposite ways, and almost every
mistake here comes from carrying an Apple habit onto Play or vice versa.
Entries anchored to Apple/Google documentation where possible; vendor
benchmark numbers are marked practitioner-measured and are directional only.

## Contents

1. [Apple indexing](#apple-indexing)
   - [The Description is not in Apple's keyword index](#the-description-is-not-in-apples-keyword-index)
   - [Words combine within a locale, so a repeated word is a wasted slot](#words-combine-within-a-locale-so-a-repeated-word-is-a-wasted-slot)
   - [The keyword field's syntax rules each cost characters silently](#the-keyword-fields-syntax-rules-each-cost-characters-silently)
   - [Title > Subtitle > Keywords is consensus, not an Apple statement](#title--subtitle--keywords-is-consensus-not-an-apple-statement)
2. [Cross-localization stacking](#cross-localization-stacking)
   - [A storefront indexes secondary locales you never intended to ship](#a-storefront-indexes-secondary-locales-you-never-intended-to-ship)
3. [Play flips the strategy](#play-flips-the-strategy)
   - [Every Apple keyword habit is wrong on Play](#every-apple-keyword-habit-is-wrong-on-play)
   - [Accented and unaccented are one token on Play and two on Apple](#accented-and-unaccented-are-one-token-on-play-and-two-on-apple)
4. [Behavioral gates](#behavioral-gates)
   - [Android Vitals demotes you regardless of metadata](#android-vitals-demotes-you-regardless-of-metadata)
   - [Ratings and reviews are a ranking factor, not just a conversion signal](#ratings-and-reviews-are-a-ranking-factor-not-just-a-conversion-signal)
5. [Creative & advanced surfaces](#creative--advanced-surfaces)
   - [One icon file cannot ship to both stores](#one-icon-file-cannot-ship-to-both-stores)
   - [Event metadata is indexed search real estate; the long description is not](#event-metadata-is-indexed-search-real-estate-the-long-description-is-not)
   - [Apple's alternate pages don't rank, Play's do](#apples-alternate-pages-dont-rank-plays-do)
6. [Research method](#research-method)
   - [Competitor metadata cannot be byte-verified from a build environment](#competitor-metadata-cannot-be-byte-verified-from-a-build-environment)
   - [An open-source Agent Skills package exists for this exact loop](#an-open-source-agent-skills-package-exists-for-this-exact-loop)

---

## Apple indexing

### The Description is not in Apple's keyword index

The single most expensive assumption to carry over from web SEO (or from
Play). Apple's classic keyword index covers **App Name (30) + Subtitle (30) +
the hidden Keywords field (100)** — 160 indexable characters total. The
**4000-char Description is not indexed for search**; its job is conversion,
and only the first ~170 chars show before "more", so that hook is the
highest-leverage copy on the page. Keyword-stuffing it buys nothing and reads
badly.

The 2025 caveat that does *not* overturn this: Apple's AI-generated App Store
Tags and semantic/natural-language search read the description **and the
screenshots**, so the description has *indirect* discovery value. Write it in
natural scenario phrasing ("organize X without an account") rather than as a
keyword list — you influence the Tags, you don't set them.

`Generalizes:` before optimizing any field, establish whether it is indexed,
converting, or both. The three fields deserve completely different prose, and
a store that indexes one field is not evidence about another store.

### Words combine within a locale, so a repeated word is a wasted slot

Apple indexes **individual words** and combines them across Name + Subtitle +
Keywords **inside one localization** to form searchable phrases: a word in
the subtitle plus another word elsewhere in the same locale can rank for the
two-word phrase. Consequences that are easy to get backwards:

- **Don't write whole phrases redundantly** — spread the component words.
- **Never duplicate a word** across Name/Subtitle/Keywords: each word is
  indexed once, so a repeat just burns part of your 160 chars. After any copy
  edit, re-run a dedup check across the three fields of that locale.
- **Words never combine across locales.** Each localization must carry
  complete, self-sufficient phrases. This is what makes the "no duplication"
  rule locale-scoped rather than absolute: repeating a word *inside* one
  locale is legitimate when you need it to form a phrase there.
- **Never put in the keyword field**: the brand/app name, the category name,
  or `app`/`free`/stop-words. All are indexed for free or ignored outright.

### The keyword field's syntax rules each cost characters silently

- **Comma-separated, no space after commas** — a space is a wasted character
  out of 100, not a separator.
- **Singular by default**: Apple stems plurals, so shipping both is usually a
  duplicate. Not absolutely — singular and plural *can* rank differently, so
  testing both is legitimate when you have spare chars and both have real
  volume.
- **`-` and `@` are treated as blank spaces.** A hyphenated term indexes as
  its two tokens; it still ranks for the two-word query, it just isn't one
  atomic token.
- **Accents are distinct tokens on Apple** (`rétroplanning` ≠
  `retroplanning`), and mobile users often type the unaccented form. Tactic:
  accented forms in the visible Title/Subtitle (credibility), unaccented
  high-volume variants in the hidden keyword field — without duplicating a
  word already visible. This is volume capture, not either/or: apps targeting
  the accented form often also rank for the unaccented one.

### Title > Subtitle > Keywords is consensus, not an Apple statement

Worth knowing precisely because it is repeated everywhere as fact. Apple
confirms only that all three fields are indexed for "text relevance" and
publishes **no weights**. The ordering is ASO-practitioner consensus derived
from testing. Practically it still drives the same allocation — most valuable
keyword in the Title, second tier in the Subtitle, long tail in the Keywords
field — but treat any advice that leans hard on the exact weighting as
unverified.

Same category of claim: the keyword field is **100 chars** today; WWDC25
demos showed 107. Treat 100 as the hard limit until it isn't.

---

## Cross-localization stacking

### A storefront indexes secondary locales you never intended to ship

Free extra keyword reach that most listings leave on the table. Each Apple
storefront indexes its primary locale **plus a fixed set of secondary
"backend" locales**. Every one of those is a **second keyword bank that ranks
in that storefront** — filling its keyword field with additional terms
expands your indexable footprint well past 160 chars, without translating the
app or serving those users a different listing.

The sets are not symmetric or intuitive: one European storefront indexed
three secondaries (including an English locale and two unrelated European
ones), while the US storefront indexed nine. **Verify the set against Apple's
official App Store localizations reference for your specific storefront** —
don't infer it from another storefront's behavior.

Two rules once you use this:
- Never duplicate a word between a primary and its secondaries (same
  indexed-once rule).
- Include the *other-language loanwords your users actually type* in these
  banks — a locale bank is useful for terms your primary-locale users search
  in a foreign language, not only for foreign-language users.

`Generalizes:` **Play has no equivalent.** Each Play locale is
self-contained; don't expect English terms to leak into a non-English store.

---

## Play flips the strategy

### Every Apple keyword habit is wrong on Play

This table is the reason this file exists. Do not copy an App Store keyword
strategy to Play:

| | App Store | Google Play |
|---|---|---|
| Hidden keyword field | 100 chars | **none, doesn't exist** |
| Long description indexed? | **no** (conversion only) | **yes, fully** |
| Where keywords go | Title + Subtitle + keyword field | **Title + Short description + Full description** |
| Keyword repetition | wasteful (indexed once) | **helpful in moderation** (~3–5× each, natural prose) |
| Cross-locale stacking | yes (backend locales) | **no**, each locale self-contained |
| Accents | **distinct tokens**, index both | **normalized**, never double them |
| Keyword-list ("comma salad") copy | harmless in desc (not indexed) | **rejection risk** (metadata policy) |
| Title A/B testable? | n/a (text isn't testable at all) | **no** — Title is excluded from Store Listing Experiments |

Play field limits: Title **30**, Short description **80**, Full description
**4000**, all three indexed, weight Title > Short > Full. First ~167 chars of
the full description show before "read more".

The trap is the last row of the middle column: on Play the long description
is a **ranking asset**, so a term must be woven ~3–5× in natural prose
(≈2–3% density) — but Google's NLP penalizes stuffing and the metadata
policy **rejects** repetitive keyword lists outright. The same paragraph that ranks
on Play would be pointless on Apple, and the keyword-list style that's
harmless on Apple gets you rejected on Play.

Play metadata policy also rejects, in Title / Short description / icon /
developer name: **emojis, ALL-CAPS** (unless it's the real brand), **promo
words** ("#1", "Best", "Top", "New", "Free", "Sale"), prices, and
"download now" CTAs in graphics. Emoji/✓ bullets are fine in the long
description *body*.

### Accented and unaccented are one token on Play and two on Apple

Called out separately because it produces a real, silent regression when copy
is shared between the two stores. **Play normalizes accents** — the accented
form ranks for the unaccented query for free, so shipping both forms is
duplication that reads as stuffing (see the rejection trigger above). **Apple
does not** — both forms are separate tokens and you deliberately place the
unaccented variants in the hidden keyword field.

**Fix**: keep the FR copy correctly accented everywhere on Play; keep the
accented/unaccented split Apple-only. Never let a "share the metadata across
stores" refactor collapse the two.

---

## Behavioral gates

### Android Vitals demotes you regardless of metadata

Ranking weight on both stores has shifted from raw downloads toward
install **velocity** (recent rate, category-relative), **conversion rate**
(high impressions with low CVR actively *hurts*), **retention**, and
uninstalls. Play goes further and makes it a hard gate: user-perceived
**crash rate ≥1.09%** or **ANR ≥0.47%** overall (8% per-device) → demoted.
**No amount of keyword work overcomes a Vitals demotion**, so check Vitals
before concluding a rank drop is a metadata problem. Excessive partial wake
locks join the list from March 1 2026 — audit any background sync path.

`Generalizes:` when store rank moves and metadata didn't, look at the quality
gates before rewriting copy. Also: an offline-first, no-account onboarding is
a *retention asset* under this model — protect it rather than trading it for
a signup funnel.

### Ratings and reviews are a ranking factor, not just a conversion signal

**Don't scope review-prompt UX as a pure conversion concern** — treating star
rating and review velocity as only a trust signal for users undersells them:
both stores also weight them directly in ranking, in the same gate category
as the Vitals thresholds above. A stalled review velocity can suppress rank
the same way a crash-rate breach does, independent of metadata quality.

**Fix**: never trigger the native review prompt (`SKStoreReviewController` /
Play's in-app review API) on first launch or immediately after install —
both platforms throttle how often the prompt can fire at all, so an early
prompt to a user who hasn't formed an opinion yet burns one of a limited
number of yearly attempts for nothing. Fire it right after a user completes
a meaningful success (a save, a completed flow), when they're likeliest to
rate positively.

`Generalizes:` a "ranking factors" mental model that stops at metadata and
crash/ANR gates is incomplete. Check review velocity before concluding a
rank drop is purely a metadata problem, same as Vitals.

---

## Creative & advanced surfaces

### One icon file cannot ship to both stores

Not a preference — the two systems compose the icon differently, so a single
exported file is wrong on at least one store:

- **Apple**: square **full-bleed**, layered for iOS 26 Liquid Glass. Do not
  bake in rounded corners, shadows, or glass; the system applies them, and a
  pre-baked one double-applies.
- **Play**: 512² **adaptive** icon (foreground + background layers), art kept
  inside the center safe zone (72 of 108 dp) because the launcher masks the
  rest.

Practitioner-measured lift, directional: icon ≈ +30%, screenshots ≈ +22%;
icon A/B winners ≈ +3–6% (iOS) / +8–12% (Play).

Related, and the reason to sequence work this way: **~100% of visitors see
the first 1–3 screenshots and only ~9% reach the end.** Front-load, keep
captions to 3–5 benefit-led words at the *top* of the frame — and note that
since WWDC25 Apple's AI extracts screenshot text for Tags + natural-language
search, so those captions are conversion *and* discovery from the same words.

### Event metadata is indexed search real estate; the long description is not

Apple **In-App Events**: the event **name (30) + short description (50) are
indexed**; the 120-char long description is not. That's **~80 extra indexed
chars per event**, on a page whose base index is only 160 — the highest-ratio
indexing lever Apple offers. Max 10 live / 15 staged, ≤31 days each, requires
a Universal Link and independent review, and must be genuinely new/timed
content (no daily, awareness-only, or price-only events).

### Apple's alternate pages don't rank, Play's do

Symmetric-looking features with opposite mechanics:

- **Apple Custom Product Pages** (up to 70): alternate screenshots/preview/
  promo text, each with its own URL. The July 2025 "Search Visibility"
  binding lets you assign **already-ranking** keywords to a CPP. **CPPs do
  NOT expand your keyword index** — they change *which page* appears for a
  term you already rank for.
- **Play Custom Store Listings** (up to 50): targetable by country,
  install-state, deep-link URL, and — since 2025 — **search keyword**.
  **Keyword-targeted CSLs DO rank in Play search**: a searcher for the term
  sees the tailored page.

`Generalizes:` don't reason by analogy between the two stores' alternate-page
features. Apple's are a conversion tool bound to existing rank; Play's are a
discovery tool.

Two more Apple surfaces worth knowing because of their edit cost:
**Promotional Text (170)** is **not indexed** but is **editable without app
review** — the only fast lever on the page, usable as a crude A/B tool.
**Product Page Optimization** tests icon/screenshots/video only (no text), 3
treatments, ≤90 days, and **icon variants must ship inside the binary**.

---

## Research method

### Competitor metadata cannot be byte-verified from a build environment

A practical constraint on any agent-run ASO research: Apple and Google
domains, and most ASO-vendor blogs, return **403 from a build/CI
environment**. Competitor titles, 30-char subtitles, and 80-char short
descriptions therefore **cannot be verified** that way, and any number
sourced from a vendor blog is a benchmark, not a store-published fact.

**Fix**: mark unverifiable claims inline where they're stated, not in a
footnote — "practitioner-measured", "could not be byte-verified". Confirm
competitor specifics via an ASO tool (AppTweak / Sensor Tower / Mobile
Action) or a device set to the target storefront before acting on them.

Also worth carrying: keyword volume proxies are directional. Apple Search
Ads "Popularity" is the classic free-ish iOS proxy, but since Oct 2025 the
API **returns nothing below ~35** — no data ≠ zero volume. Cross-check
against store search autocomplete (free, real queries) and, for Play +
seasonality, Google Trends.

`Generalizes:` an ASO change needs a measurement window longer than the
instinct to iterate. Apple metadata settles in ~3–4 weeks (change ~every 4
weeks), Play ~6–8. Snapshot ranks, change **one variable**, read at 7–14
days for first signal and 4–8 weeks for confidence. Promotional Text is the
exception — free to change anytime.

### An open-source Agent Skills package exists for this exact loop

Check [ASO Skills](https://github.com/Eronred/aso-skills) before hand-rolling
this file's research loop from scratch in an agent session — it packages a
chained `aso-audit → keyword-research → metadata-optimization` workflow as
Claude Code/Cursor/Codex Agent Skills, each aware of the others' output, so
an audit's findings feed keyword research and keyword research feeds
metadata generation without manual hand-off.

`Generalizes:` it's a third-party package, not vetted here for accuracy or
maintenance — and whatever "live" App Store data it returns is still subject
to the byte-verification constraint above. Cross-check its output the same
way you'd cross-check a vendor blog number before acting on it.
