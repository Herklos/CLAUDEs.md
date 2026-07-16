# In-app purchases — tips, gotchas & reference notes

Curated from shipping a lifetime non-consumable unlock through RevenueCat on
iOS, Android and web. Organized by where the failure surfaces: the SDK side
(resolving a package to the right store product), the sandbox (mismatches
that look like bugs but aren't), and the two store consoles (the setup steps
whose consequences are irreversible or silently break the RC import).

## Contents

1. [Resolving products](#resolving-products)
   - [One package can carry four store products, so offering order proves nothing](#one-package-can-carry-four-store-products-so-offering-order-proves-nothing)
   - [The price string comes from a different field on every platform](#the-price-string-comes-from-a-different-field-on-every-platform)
2. [Sandbox](#sandbox)
   - [A price mismatch between your UI and the purchase sheet is storefront skew, not a bug](#a-price-mismatch-between-your-ui-and-the-purchase-sheet-is-storefront-skew-not-a-bug)
3. [Store console setup](#store-console-setup)
   - [A product ID is burned forever the moment it's created](#a-product-id-is-burned-forever-the-moment-its-created)
   - [Play's one-time product hides the price behind a purchase option](#plays-one-time-product-hides-the-price-behind-a-purchase-option)
   - [The App Store IAP review screenshot is reviewer-only and must be real](#the-app-store-iap-review-screenshot-is-reviewer-only-and-must-be-real)
   - [Console click paths](#console-click-paths)

---

## Resolving products

### One package can carry four store products, so offering order proves nothing

A RevenueCat offering looks like it maps 1:1 to a thing you sell. It doesn't.
A single package (e.g. `$rc_lifetime`) commonly has **several store products
attached at once**: the RevenueCat Test Store product (dev-only), the RC
Billing/Stripe product (real, web), the Apple App Store SKU, and the Google
Play SKU. Code that grabs `offerings.current.availablePackages[0]`, or that
assumes the first/only package is the one it wants, is reading whichever
product the dashboard happens to hand back.

The failure is quiet and platform-specific: a production build resolves the
**Test Store** product and renders its placeholder price, or an RC
Billing/Stripe price shows on native. Nothing throws.

**Fix**: match the package by **product id against an explicit allowlist**,
never by position:

```ts
const PREMIUM_PRODUCT_IDS = [STORE_SKU, RC_BILLING_ID, TEST_STORE_ID]
// pick the package whose product.identifier is in the allowlist
```

and make the allowlist **narrower outside `__DEV__`**: accept only the real
store SKU in production, so the bare Test Store id and any "sole package"
fallback are dev-only. A mis-keyed or misconfigured production build then
fails loud (no package → price renders as a placeholder dash) instead of
silently charging-page-ing a wrong price.

`Generalizes:` when a vendor SDK returns a list whose contents depend on
dashboard state, never index into it — filter it against an id you control,
and tighten the filter in production so misconfiguration surfaces as a hard
failure rather than a plausible-looking wrong value. Log the resolved product
id + price + currency in dev; that log is what turns "the price is wrong"
into a one-minute diagnosis.

### The price string comes from a different field on every platform

Same SDK, same package, different accessor — and the wrong one is `undefined`
rather than an error:

- **Native** (StoreKit / Play Billing): `pkg.product.priceString` — already
  localized by the store.
- **Web** (RC Billing / Stripe): `pkg.rcBillingProduct.currentPrice?.formattedPrice`.

A platform-split module (`revenuecat.ts` / `revenuecat.web.ts`) is the clean
place for this, since the whole resolution path differs anyway.

---

## Sandbox

### A price mismatch between your UI and the purchase sheet is storefront skew, not a bug

Symptom: your own paywall/settings hero shows `$44.99` while the StoreKit
purchase sheet on the *same TestFlight build, same device* shows `49,99 €`.
This reads as a currency/formatting bug in your code and burns an afternoon
if you chase it there.

It's neither. The two strings come from **two different accounts**:

- `Purchases.getOfferings()`'s `priceString` localizes to the device's
  signed-in **App Store account region**.
- The StoreKit purchase sheet localizes to the **sandbox tester Apple ID**
  used at buy time.

On a test device those are routinely different accounts in different
countries. Production has one Apple ID driving both, so they always match.

**Fix**: check device Settings → Media & Purchases → account country against
the sandbox tester's country **first**, before touching any code.

`Generalizes:` before debugging a value that two layers disagree about, ask
whether the two layers are reading the same *identity*. Sandbox environments
routinely split an identity that production merges — and the split is
invisible from inside the app.

---

## Store console setup

### A product ID is burned forever the moment it's created

On **both** stores, a product ID can never be reused once created, **even if
you delete the product**. There is no undo and no support path. The ID must
match exactly across RevenueCat, App Store Connect and Play Console, so a
typo caught after Create means living with the typo in all three or
abandoning the identifier permanently.

**Fix**: paste the ID from a single source of truth (the RC dashboard entry,
or the constant in code), and re-read it before clicking Create. This is the
one irreversible step in the whole setup.

### Play's one-time product hides the price behind a purchase option

Google's one-time-product model doesn't put the price on the product; it
splits price/entitlement into a **purchase option**, and the dialog for it is
where the RevenueCat integration silently breaks.

- **Check "backwards compatible"** on the purchase option. RevenueCat only
  **auto-imports backwards-compatible** one-time products; a
  non-backwards-compatible one needs manual re-mapping in RC's dashboard
  later. This checkbox — not any ID field — is what makes auto-import work.
- The **"Purchase option ID"** is a *separate*, free-typed field from the
  Product ID, with its own charset rule: must start with a digit or lowercase
  letter, then only digits, lowercase letters, or hyphens. **No dots**, so it
  literally cannot equal a reverse-DNS product ID — which looks like a
  mismatch you need to fix. It isn't; its text is irrelevant to the import.
  Something like `lifetime` is fine.
- The product must be **Activated**, not left Draft, to be purchasable at all.

### The App Store IAP review screenshot is reviewer-only and must be real

The "Review Information → Choose File" screenshot on an IAP is **never shown
on the App Store** — it's distinct from the optional 1024×1024 promotional
image, and it exists so the reviewer can confirm the in-app purchase screen
matches the Product ID, price and description you entered. No exact pixel
size is enforced, but it must be a **real capture of the actual purchase
screen** (simulator or device), not a mockup, or the IAP gets rejected while
the binary passes.

### RevenueCat test-store prices can be created via API and never changed

Setting a test-store product's price from an agent/API works exactly once. The
second time:

```
409  {"type": "resource_already_exists",
      "message": "The price already exists for this product."}
```

The 409 is keyed on the **product**, not on `(product, currency)`. That is the decisive
test and it is worth running before theorising: retrying with a SINGLE currency returns the
same 409, so there is no per-currency upsert and no partial-write path. An empty
`{"prices": []}` body is not a clearing operation either — it 400s on validation before the
conflict check is even reached.

The surface is create-only. There is no update-price and no delete-price:

- `create-product-prices` — the only price WRITE for a test_store product, and it
  409s the moment prices exist.
- `set-product-store-state` — takes `store: app_store | play_store` only, so it
  does not apply to a test-store product at all.
- `equalize-subscription-prices` — App Store subscriptions only.

The store-state subsystem does not silently no-op on a test-store product, which is what
proving this negative actually rests on: it refuses EXPLICITLY, on both the read and the
write side, with `store_state operations currently support only app_store and play_store`.
The enum admits no `test_store` value, so nothing is hiding behind the schema.

Check the app's `type` before concluding anything; the same product id behaves
differently per app type, and `create-product-prices` errors on a NON-test_store
product for a completely different reason. `type: test_store` plus existing prices
is a dead end: the dashboard is the only path.

**Fix**: change it in the console. Do not route around it by archiving the product
and recreating it at the new price — that orphans the offering and any purchase
history to save a UI click.

**What does NOT need changing** once the console price moves: a client reading
`priceString` off the live product follows the store automatically, per storefront
and currency. What DOES need changing is every price the SDK never touches, and
they are easy to miss because nothing fails:

- structured data (`schema.org` `Offer.price` in the page head), which is the
  number a search engine can print beside the result;
- the paywall's fallback string, shown only in the window before the store
  answers — which is exactly when a wrong number is most convincing.

**Generalizes**: whenever a price lives in a store, assume it ALSO lives in two or
three places the store cannot reach, and grep for the digits rather than trusting
"it comes from the SDK". A stale price in marketing metadata is invisible to every
test and visible to every customer.

### Console click paths

Compact, because the surrounding UI moves but the sequence doesn't.

**App Store Connect** (needs Account Holder / Admin / App Manager /
Developer / Marketing; the app record for the bundle ID must already exist):

1. Apps → your app → **Monetization → In-App Purchases** → **+**.
2. Pick the type (**Non-Consumable** for a one-time lifetime unlock — *not* a
   subscription).
3. Reference Name (internal only, ≤64 chars) + **Product ID** (see the burned-
   forever entry above) → Create.
4. Availability, Price Schedule (pick the tier; Apple auto-converts other
   currencies), and an **App Store Localization** per locale — display name +
   description are shown in the purchase sheet.
5. Attach the review screenshot → Save → submit with the next binary, or
   standalone via "Submit for Review" if the app is already live.

**Play Console** (needs "Manage orders and subscriptions" / "Manage store
presence"; the app must exist with ≥1 internal-testing release uploaded):

1. **Monetize with Play → Products → One-time products** → Create.
2. **Product ID** (immutable), Name/Description, plus a translation per locale
   from the product's detail page.
3. Purchase option: **backwards compatible** + a purchase-option ID (see
   above).
4. Price, availability (match iOS), then **Activate**.

**After both are live**, no further RevenueCat dashboard work is needed if
the product/entitlement/offering wiring already exists — RC auto-detects and
syncs the store side **within a few hours**, and each product's `state` flips
from pending to ready. Don't debug a "missing product" during that window.
