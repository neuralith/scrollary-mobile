# Monetization strategy

> **Historical, dated 2026-08-03. Partly superseded. Not a specification.**
>
> This is research and a recommendation, written before any capability boundary
> existed. Two things have since changed underneath it, and both are flagged
> where they occur:
>
> 1. **§2.2 is no longer true.** It states that nothing in the codebase knows
>    what a "Pro" user is. A capability seam now exists — `lib/capability/`,
>    with entitlement, an internal override, a capability and a user preference.
>    There is still **no billing**: `productionEntitlement()` returns `free`,
>    and nothing charges anybody.
> 2. **§8.3's proposed boundary has been superseded by an explicit product
>    decision.** This document recommended selling *update checking* as the
>    headline Pro feature. **That is no longer the plan, and must not be
>    implemented.** The decision now is:
>
>    > **Update checking is Free. Foreground multitasking — letting a supported
>    > operation keep working while the user goes somewhere else in the app — is
>    > Pro.**
>
>    Free covers the operation itself: a Collection check, the Library-wide
>    check, the Entries either discovers, saving and capture on the ordinary
>    flows, and the whole library and offline reader. Pro covers only the
>    *execution experience* — the operation continuing while the user reads or
>    browses elsewhere in the app instead of holding until they return.
>    Specified in FOREGROUND_MULTITASKING.md §10.0, carried as an invariant in
>    ARCHITECTURE.md §9, and stated as a standing rule in CLAUDE.md.
>
> **Read every "Pro" claim below against that decision.** Where this document
> proposes gating an operation, it is describing an option that was considered
> and rejected, not a requirement. §17's remaining decisions (price, model,
> sequencing) are still open; the *boundary* is not.
>
> Read this for the store-policy findings, the competitor pricing and the
> arithmetic — which are unaffected — and read ARCHITECTURE.md §10 for what the
> app actually is.
>
> A decision document, not an implementation plan and not a commitment. It
> records what the product was on the date above, what the two stores then
> required, what comparable apps charge, and which model fits **this** app — one
> local-first reader, one developer, no server.
>
> **Terminology.** The product is **Scrollary** (STORE_PACKAGE.md §1); "Web
> Reader" is the retired working name and appears only in the pubspec package
> name `web_reader`. The model is Library → **Collection** → **Entry** →
> Page/Section (TERMINOLOGY.md §1).
>
> **All external facts were retrieved on 2026-08-03.** Store policy and
> commercial terms change; §18 lists every source with its URL. Re-verify before
> acting, particularly the two items currently in motion: Google Play's
> service-fee split (effective 2026-06-30) and Apple's US external-link position
> (before the Supreme Court, argument expected October–December 2026).

---

## 1. Executive summary

**Recommendation: ship free, monetize with a single one-time "Pro" unlock at
USD 9.99, no subscription, no login, no backend.**

The reasoning in one paragraph: every feature this codebase can plausibly put
behind a paywall today is a **local** feature — a one-time engineering cost with
no recurring cost attached. Apple requires an auto-renewable subscription to
provide "ongoing value" (guideline 3.1.2(a)), and the only qualifying justification
available to a purely local app is a promise of "consistent, substantive updates"
— a promise a solo developer would have to keep forever, under review scrutiny,
in exchange for roughly USD 0.84 per subscriber per month. At USD 0.99/month, a
subscriber must stay **more than ten months** before they are worth more than a
single USD 9.99 unlock, while generating billing-retry, grace-period, expiry and
restore support the one-time purchase never generates at all. The mismatch between
a recurring price and a one-off cost is what makes low-priced subscriptions feel
unfair, and it is avoidable here.

Secondary conclusions:

| Question | Answer |
|---|---|
| Free, paid, freemium or trial-first? | **Freemium** with a permanently usable free tier. The free tier *is* the trial; no time-limited trial is needed. |
| Subscription or one-time? | **One-time non-consumable.** Revisit only when a real recurring cost exists (cloud sync). |
| Price | **USD 9.99** one-time, with **Türkiye priced manually and well below the auto-converted equivalent**. |
| Does it need Apple or Google login? | **No.** Apple 5.1.1(v) actively *forbids* requiring a login in an app without significant account-based features. |
| Does it need a Scrollary account? | **No**, and not until cloud sync exists — which is Stage 4 at the earliest. |
| Does it need a backend? | **No.** StoreKit 2 and Play Billing both answer the entitlement question on-device. |
| What is free forever? | Browsing, saving (single and bounded multi-entry), every capture mode, unlimited Collections and Entries, offline reading, reading position, archive, storage management, deletion, undo, retry — the whole reader. **Since superseded, and now larger:** update checking, at both granularities, is Free too. |
| What is Pro? | ~~Library **power tools**: update checking, saved rules (taught page hints), per-collection capture preferences, queue depth, reader customisation, diagnostics.~~ **Superseded.** The decision is **foreground multitasking** — a supported operation continuing while the user is elsewhere in the app. Update checking is **Free**. See the header and §8.3 |
| What happens to saved content if entitlement is ever lost? | **Nothing.** Not a byte, not a row, not a reading position. Pro gates *new* operations only. |
| What is out of scope initially? | Accounts, cloud sync, cloud backup, analytics, ads, external payment flows, desktop companions, usage-based pricing, and any "supported-site preset" (forbidden outright — see §8.1). |

The two credible alternatives are in §12: a Panels-style subscription-plus-lifetime
hybrid, and a paid-upfront app.

---

## 2. Current product and implementation findings

Everything in this section was read from the repository on 2026-08-03. It is
inspection, not inference.

### 2.1 What exists

| Area | Finding | Evidence |
|---|---|---|
| Platform targets | **iOS and Android only.** No `macos/`, `windows/`, `linux/` or `web/` directory exists. | repository root |
| Size | 93 Dart files under `lib/` | `find lib -name '*.dart'` |
| Persistence | drift/SQLite, `schemaVersion` **1**, `onCreate` only, **no `onUpgrade`** and no migration system | `lib/storage/database.dart`, ARCHITECTURE.md §8 |
| Tables | `collections` · `entries` · `save_runs` · `user_page_hints` · **`settings`** · `queue_tasks` · `browsing_history` · `saved_sites` · `favicon_cache` | `lib/storage/database.dart` |
| Durable user data | Entry **packages on disk** (`manifest.json` v2 + assets/`document.json`); `lib/storage/recovery.dart` rebuilds library rows from them | ARCHITECTURE.md §8.1 |
| Dependencies | 15 runtime packages. `flutter_inappwebview` (pinned `6.2.0-beta.3`), `drift`, `dio`, `flutter_riverpod`, `go_router`, `path_provider`, `uuid`, `crypto`, `collection`, `wakelock_plus`, `share_plus`, `url_launcher`, `cupertino_icons`, `path`, `drift_flutter` | `pubspec.yaml` |
| Saving | `SaveScope` is `currentPageOnly` \| `selectedEntries` \| `fixedCount`; `SaveLimits.forScope` is the only constructor and cannot produce an unbounded run; `maxEntriesPerRun` = 500 | `lib/core/config.dart` |
| Queue | `TaskQueueController`, `historyLimit` = 50, states include `queued`/`running`/`cancelled`/`failed`; start authorisation is never persisted | `lib/queue/task_queue.dart`, ARCHITECTURE.md §9 |
| Update checking | Foreground, visible, user-started, at most `kUpdateCheckForwardDepth` (2) forward hops; `UpdateCheckConfig` caps pages, entries and duration | `lib/library/update_checker.dart` |
| Cleanup | `CleanupService.removeOffline` (soft, ~6 s undo) and `removeOfflineNow` (bulk, cooperative stop) | `lib/storage/cleanup.dart` |
| Deletion | `CollectionDeletionService.delete` — cancel work, refuse while locked, move files out of `library/`, then rows in one transaction | ARCHITECTURE.md §8.2 |
| Library organisation | `LibrarySort` has exactly **two** values: `lastRead` and `name`. Archive/restore exists. | `lib/library/library_sort.dart`, `lib/features/archived_screen.dart` |
| Settings screen | Appearance · Browsing history · Saved sites · Clear website data · Storage · Saved rules · Activity history · Developer (debug only) | `lib/features/settings_screen.dart` |
| Restricted-site capture policy | `lib/save/capture_policy.dart`, the only file in `lib/` permitted to name a host; enforced at every boundary independently | ARCHITECTURE.md §7.1 |
| Store positioning | Age rating **18+**, "Ads: None", listing name `Scrollary: Offline Web Reader`, bundle `com.mcagricaliskan.scrollary` | STORE_PACKAGE.md §1, §8.4 |

**Two rows have drifted since this inspection.** The Settings screen has gained
a *Keep working while I read* row, which is the Pro-gated control; and the
Developer entry is gated by `kInternalBuild`, not `kDebugMode` alone, so it is
present in a profile or release build compiled with
`--dart-define=SCROLLARY_INTERNAL_BUILD=true`. Neither changes any argument
below. Current state: ARCHITECTURE.md §10.

### 2.2 What does **not** exist

> **⚠ Superseded in part.** As written on 2026-08-03 this section was accurate.
> The second bullet is now **false** and is kept only so the change is visible:
> a capability seam shipped afterwards. Everything else in the list still holds
> — in particular there is still no billing, no account and no backend.

Verified by grep across `lib/`, `test/`, `android/app`, `ios/Runner`, `pubspec.yaml`
and `docs/`:

- **No purchase or billing code.** No `in_app_purchase`, no StoreKit, no Play
  Billing, no RevenueCat or equivalent. The only matches for "subscription" in
  `lib/` are Dart `StreamSubscription`s and paywall *detection* strings in
  `bridge_script.dart` / `stop_conditions.dart`. — *Still true.*
- ~~**No entitlement, tier, feature-flag or remote-config concept.** Nothing in the
  codebase knows what a "Pro" user is.~~ — **No longer true.** `lib/capability/`
  now separates entitlement (`productionEntitlement()`, which returns `free`),
  an internal-build override (`EntitlementOverride`), the capability that
  follows from it (`proCapabilityAvailable()`) and the user's own preference.
  It gates one behaviour — foreground multitasking — and nothing else. There is
  still no remote config and no tier beyond that. See
  FOREGROUND_MULTITASKING.md §10.4.
- **No authentication.** No login screen, no OAuth, no token storage, no keychain
  use for credentials. — *Still true.*
- **No backend of any kind.** `dio` fetches page assets from the sites the user
  visits; there is no developer-owned endpoint anywhere.
- **No analytics, crash reporting or advertising SDK.** This is a standing rule,
  not an omission (CLAUDE.md, PRIVACY.md).
- **No monetization notes, pricing plans or unfinished commerce work** anywhere in
  `docs/`. This document is the first.

### 2.3 What is planned but not built

From ARCHITECTURE.md §10, verbatim status:

| Deferred item | Relevance to monetization |
|---|---|
| Save-scope **review step (UI)** | The domain layer computes the whole preview; only the screen is missing. A multi-entry save is bounded and cancellable today but **not previewed**. |
| First-use and contextual **content-rights disclosures (UI)** | Must precede any paid release; a paywall in front of an app that has not yet made its content-rights position visible is the wrong order. |
| **Privacy / Terms / Content-rights settings pages** | Store submission blockers regardless of monetization (STORE_PACKAGE.md §8.5). |
| Hosted demo site, store assets | External, deferred. |
| ~~**Device runtime verification** — "Not run — simulator launch only"~~ | ~~The app has never been verified on physical hardware.~~ **No longer true.** The app has since run on a cabled iPhone 17, including a real-site save and a soak; Android hardware and the accessibility passes are still outstanding. Current status: ARCHITECTURE.md §10 |

The first four rows still hold. Nothing in this document's arithmetic depends on
the fifth.

### 2.4 What would require new infrastructure, and what can stay local

| Capability | Needs a server? |
|---|---|
| One-time Pro unlock, subscription, restore purchases, entitlement checks, offline entitlement, family sharing | **No.** StoreKit 2 `Transaction.currentEntitlements` and Play Billing `queryPurchasesAsync` both read an on-device cache (§4.6). |
| Receipt *verification against fraud* | Optional server. Not worth building for a USD 9.99 product (§15.4). |
| Every Pro feature proposed in §8 | **No.** All are local computation over the existing SQLite database and file store. |
| Cross-device sync, cloud backup, a Scrollary account, promo-code redemption tracking, telemetry | **Yes** — and each also brings privacy obligations, account-deletion duties and legal exposure (§14, §16). |

### 2.5 Constraints the codebase itself imposes

These are standing rules in CLAUDE.md and ARCHITECTURE.md. They **eliminate**
several otherwise-obvious paid features before any commercial analysis begins:

1. **No hostname, selector, site list or "supported sites" may ship** — in the
   binary, tests, fixtures or docs — except the *refusal* list in
   `capture_policy.dart`. `test/repository_cleanliness_test.dart` fails the build
   otherwise. → **"Supported-site presets" can never be a paid feature.** (§8.1)
2. **Nothing saves in the background.** Queued work waits for an explicit Start
   and that authorisation is never persisted. → **"Background/unattended
   processing" can never be a paid feature.** (§8.1)
3. **The app stops; it never works around.** No retry with different headers, no
   alternate-URL attempt, no cookie manipulation, no rate-limit wait-out. → No
   paid tier may buy a way past a `StopReason`.
4. **Every ceiling is one the user chose and can see.** `SaveLimits.forScope`
   cannot produce an unbounded run. → A tier-dependent cap is permissible only if
   it is visible and explained, never silent.
5. **Removing files ≠ deleting an entry; archiving ≠ deleting a collection.** →
   No entitlement change may touch `content_path`, `byte_size`, `lifecycle`, or
   any reading column.
6. **Reading state is writable only from `lib/reading/`**; `writeEntryReading` is
   the only DAO method that can reach a reading column. → An entitlement system
   physically cannot corrupt reading progress if it stays out of that directory.
7. **The database has version 1 and no migration system.** → Entitlement state
   should live in the existing `settings` key/value table, which needs no schema
   change (§15.2).

---

## 3. Monetization goals and constraints

**Goals, in priority order.**

1. Cover fixed costs first: **USD 99/year** (Apple Developer Program) and
   **USD 25 once** (Google Play registration). Everything above that is progress.
2. Fund ongoing maintenance. This app's maintenance is genuinely ongoing —
   websites change, WebView behaviour changes, OS releases break things — even
   though it has no servers.
3. Do not damage the product's positioning. STORE_POLICY_MAP.md is built around
   "this is a personal reader, not a bulk fetcher". A pricing page can undo that
   in one line of copy (§8.2).
4. Keep the support burden proportional to a solo developer with no support
   infrastructure.

**Hard constraints.**

| Constraint | Source |
|---|---|
| Core reading stays local-first; offline reading never requires an account or a server | Product principles; PRIVACY.md |
| Downloads, Collections, Entry state and reading progress are user-owned; losing paid access never deletes them | Product principles; ARCHITECTURE.md §8.2, §9 |
| No analytics, crash-reporting or advertising SDK; nothing is sent to the developer | CLAUDE.md, PRIVACY.md |
| No new permission without a visible, justified feature | CLAUDE.md |
| No export to Photos, Gallery, Downloads or shared storage | CLAUDE.md |
| The seven codebase constraints in §2.5 | CLAUDE.md, ARCHITECTURE.md |
| 18+ target audience, no ads | STORE_PACKAGE.md §8.4 |

**A consequence worth stating plainly:** the no-analytics rule means conversion,
paywall views and funnel drop-off **will not be measurable in-app**. The only
sanctioned measurement is App Store Connect and Play Console aggregate sales
reporting, which requires no SDK and collects nothing on the developer's behalf.
Pricing decisions here will therefore be made on thin data for a long time. This
is a deliberate trade, but it argues for a *simple* model whose outcome is legible
from a sales report alone — one number, units sold — rather than a multi-tier
funnel that cannot be diagnosed.

---

## 4. Official platform policy findings

All quotations retrieved **2026-08-03**. Full URLs in §18.

### 4.1 In-app purchase is mandatory for unlocking features

> **Apple, guideline 3.1.1:** "If you want to unlock features or functionality
> within your app, (by way of example: subscriptions, in-game currencies, game
> levels, access to premium content, or unlocking a full version), you must use
> in-app purchase. Apps may not use their own mechanisms to unlock content or
> functionality, such as license keys, augmented reality markers, QR codes,
> cryptocurrencies and cryptocurrency wallets, etc."

> **Apple, guideline 3.1.1:** "you should make sure you have a restore mechanism
> for any restorable in-app purchases."

> **Google Play Payments policy:** "Developers charging for app downloads from
> Google Play must use Google Play's billing system as the method of payment for
> those transactions." The policy explicitly covers "app functionality or content
> (such as an ad-free version of an app or new features)".

**For Scrollary:** a Pro unlock must be a StoreKit in-app purchase on iOS and a
Play Billing product on Android. A licence key, a promo code redeemed in-app
against a developer server, or a "buy on our website" flow are all excluded.

### 4.2 The subscription bar — the single most important policy finding

> **Apple, guideline 3.1.2(a):** "If you offer an auto-renewable subscription,
> you must provide **ongoing value** to the customer, and the subscription period
> must last at least seven days and be available across all of the user's devices.
> While the following list is not exhaustive, examples of appropriate
> subscriptions include: new game levels; episodic content; multiplayer support;
> **apps that offer consistent, substantive updates**; access to large collections
> of, or continually updated, media content; software as a service ("SAAS"); and
> cloud support."

Scrollary has no server, no hosted content and no service. Of Apple's examples,
the **only** one it could claim is "apps that offer consistent, substantive
updates". That is a real, permitted basis — several successful local apps rely on
it — but it converts a pricing decision into an open-ended delivery obligation,
and it is the weakest of the listed justifications to defend at review.

Two further clauses matter:

> **3.1.2(a):** "If you are changing your existing app to a subscription-based
> business model, you should not take away the primary functionality existing
> users have already paid for."

> **3.1.2(a):** "Apps that attempt to scam users will be removed from the App
> Store. This includes apps that attempt to trick users into purchasing a
> subscription under false pretenses…"

> **3.1.2(c):** "Before asking a customer to subscribe, you should clearly
> describe what the user will get for the price."

**Google Play** states the same disclosure duty more briefly: "Developers must
clearly and accurately inform users about the terms and pricing of their app or
any in-app features or subscriptions offered for purchase."

### 4.3 Trials and introductory offers

**Apple.** Auto-renewable subscriptions support **free trials**, **introductory
offers** (free trial / pay-as-you-go / pay-up-front; "Customers can redeem one
introductory offer per subscription group"), **promotional offers** for existing
or lapsed subscribers, **offer codes**, and **win-back offers**.

For **non-subscription** apps, Apple permits a distinct mechanism:

> **3.1.1:** "Non-subscription apps may offer a free time-based trial period
> before presenting a full unlock option by setting up a Non-Consumable IAP item
> at Price Tier 0 that follows the naming convention: 'XX-day Trial.' Prior to the
> start of the trial, your app must clearly identify its duration, the content or
> services that will no longer be accessible when the trial ends, and any
> downstream charges the user would need to pay for full functionality."

This is available to the recommended model but **is not recommended** (§11.4): a
permanently usable free tier is a better trial than a countdown, and the Tier-0
trial requires receipt/DeviceCheck plumbing to enforce.

**Apple, new since 2026-04-27:** *monthly subscriptions with a 12-month
commitment* — a lower monthly price in exchange for twelve committed payments,
available worldwide **except the United States and Singapore**, requiring
iOS 26.4+. Relevant only to Alternative A (§12.1).

**Google Play.** Free trials and introductory prices are configured per base plan
or offer. Note the eligibility default: "To allow users multiple free trials …
you must uncheck the 'Allow one free trial per app' box".

### 4.4 Cancellation, billing retry, grace period, account hold

| Behaviour | Apple | Google Play |
|---|---|---|
| Failed renewal | Billing Retry for **up to 60 days** | Grace period, then **account hold** |
| Keeping access during recovery | **Billing Grace Period**, opt-in in App Store Connect, duration **3, 16 or 28 days**; applies to all renewals or paid renewals only | Grace period length configurable per base plan; "During the grace period, you should ensure the user still has access to the subscription entitlements" |
| After recovery fails | Subscription expires | "During account hold, you should ensure the user does **not** have access to the subscription entitlements" |
| Resubscribe | Standard | In Play Store, "users can resubscribe to the same SKU for up to one year after expiration"; this generates a **new purchase token** |

**For Scrollary:** each of these is a state the app must render honestly and a
source of user contact ("why did it stop working?"). A non-consumable has none of
them. This is a concrete, recurring support cost attached to the subscription
model and absent from the one-time model.

### 4.5 Family Sharing

> "Family Sharing allows a subscriber to share access to an auto-renewable
> subscription with up to five family members across their Apple devices."
> Ownership is distinguishable via `ownershipType` in the transaction.

Family Sharing is also supported for non-consumables. Enabling it dilutes revenue
somewhat and reduces support contact; §11.6 recommends enabling it.

### 4.6 Restore purchases without any app account

- **Apple/StoreKit 2:** `Transaction.currentEntitlements` reads a **local
  transaction cache** synced from Apple's servers, so it answers offline once
  populated. **Caveat, and it matters:** if that sync has never completed for the
  current Apple Account on the current device, the streams come back empty even
  though the purchase exists — restoring from backup, a new device, or a Family
  Sharing member's first launch needs `AppStore.sync()`, which is what an explicit
  **Restore Purchases** button triggers. [Sourced from Apple developer forum
  threads and RevenueCat engineering write-ups, not from a single normative Apple
  sentence — see §18; treat the *caveat* as [Likely] rather than certain and
  verify during implementation.]
- **Google Play:** `queryPurchasesAsync` returns purchases owned by the signed-in
  Google account; obfuscated account IDs are optional linkage, "an app account is
  **not strictly required**".

**Conclusion: purchases restore across reinstall and device change with no
Scrollary account whatsoever.** The user's Apple Account or Google account *is*
the purchase identity.

### 4.7 Accounts, sign-in, and Sign in with Apple

> **Apple, guideline 5.1.1(v):** "**If your app doesn't include significant
> account-based features, let people use it without a login.** If your app
> supports account creation, you must also offer account deletion within the app.
> Apps may not require users to enter personal information to function, except
> when directly relevant to the core functionality of the app or required by law."

> **Apple, guideline 4.8:** "Apps that use a third-party or social login service
> (such as Facebook Login, Google Sign-In, Log in with X, …) to set up or
> authenticate the user's primary account with the app must also offer as an
> equivalent option another login service…" — with the exception that "Another
> login service is not required if: Your app exclusively uses your company's own
> account setup and sign-in systems."

**Google Play** requires apps that allow account creation to offer **in-app
account deletion** *and* a **web link** for deletion requests (policy deadline
2023-12-07, extended to 2024-05-31; enforcement includes removal).

**Conclusion: adding a login to a subscription-only app is not merely
unnecessary — under 5.1.1(v) it is a rejection risk.** 4.8 does not apply at all
unless a third-party login is offered, which it would not be.

### 4.8 Commission, small-business programmes, and the fee changes now in flight

**Apple.**

- Standard: 70% to the developer; **85% after a subscriber accumulates one year of
  paid service**.
- **App Store Small Business Program: 15% commission** for developers with "up to
  1 million USD in proceeds in the prior calendar year … as well as developers new
  to the App Store". Enrolled developers get **85% of subscriptions from the first
  billing cycle**, with no one-year wait.
- Enrolment must be applied for; proceeds adjust "fifteen (15) days after the end
  of the fiscal calendar month in which your enrollment is approved".

**→ Scrollary qualifies for 15% from day one. Enrol before the first sale.**

**Google Play.**

- Outside the EEA/UK/US: **15%** on the first USD 1M of annual earnings;
  **auto-renewing subscriptions are 15% regardless of revenue**.
- **From 2026-06-30, in the US, EEA and UK, Google separates the service fee from
  the billing fee.** Per the official Android Developers Blog announcement of
  2026-06-24: service fee **10%** on the first USD 1M and **10% on all
  auto-renewing subscriptions**, plus a **5% billing fee** when Google Play's
  billing system is used, and **no billing fee** for alternative billing or
  external web links. "New installs" are users whose first install or first update
  in those regions occurred on or after 2026-06-30.

**→ Practical effect for a small app using Play Billing: ~15% either way.**
Türkiye is not in the EEA/UK/US, so it stays on the standard 15% subscription
rate. Modelling 15% on both stores in §10 is therefore accurate to within a point
for the foreseeable term. *[The Play Console fee page and the blog post describe
the same change with slightly different framings for non-subscription tiers;
re-read both before relying on the non-subscription numbers.]*

### 4.9 Price points and regional pricing

**Apple.** "Choose from up to 800 price points by default, and request access to
an additional 100 higher price points (up to $10,000)" — 900 in total, with the
**lowest at USD 0.29** (Apple's 2022 pricing announcement, which introduced the
system still in use). You "set a price for the country or region you're familiar
with as the basis for automatically generating prices across the other 174
storefronts and 43 currencies". Critically:

> "Prices for your base country or region won't be adjusted by Apple as taxes and
> foreign exchange rates change." … "Periodically, Apple updates prices in certain
> regions based on changes in taxes and foreign exchange rates."

and

> "Alternatively, you can choose to manually manage certain storefronts or you can
> manually manage them all. Keep in mind that you'll be responsible for staying up
> to date with taxes and exchange rates in the storefronts you manually manage."

**Google Play.** Local-currency pricing per country; Play "converts your price to
the local currency, add[s] tax [in select countries], and appl[ies] locally
relevant pricing patterns". Sub-dollar minimums exist in a set of markets
including Türkiye. *[The exact TRY minimum was not obtainable from Google's own
tables in this session — the price-range table lives on a page the fetch could not
resolve. Third-party sources put the Türkiye minimum near USD 0.21. **Marked
[Unverified]; confirm in Play Console, which shows the live range.**]*

**Türkiye specifically:** Apple has repeatedly repriced the Turkish storefront for
FX and local tax; Turkish coverage retrieved 2026-08-03 reports the entry-level
app tier moving from ₺10.99 to ₺16.99, and separate updates applying to Türkiye,
Poland and Switzerland. The exact current TRY value of any tier is **[Unverified]**
and must be read from App Store Connect. §9.4 gives the resulting recommendation.

### 4.10 Is USD 1.00/month technically possible?

**Yes.** Apple's price points go down to USD 0.29, and Play offers sub-dollar
minimums. USD 0.99/month and USD 9.99/year are both ordinary, well-supported price
points on both stores. The obstacle to USD ~1/month is **economic, not technical**
(§9.3).

### 4.11 Would an external payment flow be permitted?

**Apple.** Guideline 3.1.1(a) currently reads: "These entitlements are not
required for developers to include buttons, external links, or other calls to
action in their **United States storefront** apps", and "In all other storefronts,
**except for the United States storefront, where this prohibition does not
apply**, apps and their metadata may not include buttons, external links, or other
calls to action that direct customers to purchasing mechanisms other than in-app
purchase." Elsewhere, a StoreKit External Purchase Link Entitlement is required
and is "limited to use only in the iOS or iPadOS App Store in specific
storefronts".

**This is live litigation.** The US position derives from the Epic injunction;
an appeals court has modified it to permit Apple to charge a fee, Apple's stay
application was refused, and Supreme Court argument is expected October–December
2026 with a ruling likely around mid-2027. **[Sourced from press reporting, not
from a court document — treat the procedural detail as [Likely].]**

**Google.** From 2026-06-30 in the US, EEA and UK: alternative billing and
external web links are permitted, with no 5% billing fee but the same 10% service
fee.

**Recommendation: use IAP and Play Billing exclusively.** Türkiye — a primary
target market — is in neither the US nor the EEA/UK, so an external flow would not
even be available there. Building a web checkout, handling VAT/KDV registration in
every market, and betting on an unresolved Supreme Court case is disproportionate
for a USD 9.99 product. Revisit only if revenue ever makes a 15% fee material in
absolute terms.

### 4.12 Privacy declarations — adding IAP does not break the existing claims

> **Apple, App Privacy details:** "Data that is processed only on device is not
> 'collected' and does not need to be disclosed in your answers." "'Collect'
> refers to transmitting data off the device in a way that allows you and/or your
> third-party partners to access it for a period longer than what is necessary to
> service the transmitted request in real time."

StoreKit and Play Billing transactions are processed on-device and between the
user and the store; the developer receives **aggregate sales reports** from Apple
and Google, not per-user purchase histories. With no third-party purchase SDK and
no developer server, the **Purchases → Purchase History** data type is not
collected by the developer.

**Therefore PRIVACY.md's claims survive verbatim**: "There is no account, no
server, no analytics", "Nothing goes to the developer". What **must** change:

- Apple 2.3.2 — "If your app includes in-app purchases, make sure your app
  description, screenshots, and previews clearly indicate whether any featured
  items, levels, subscriptions, etc. require additional purchases." STORE_PACKAGE.md
  §2/§3/§4 listing copy needs an IAP disclosure line in English **and** Turkish.
- STORE_PACKAGE.md §8.1/§8.2 console checklists must be re-answered with the IAP
  in place (expected answer: still no data collected — but the questionnaire must
  be walked, not assumed).
- The settings-screen sentence "Everything is stored on this device. There is no
  account, no sync and no background network activity" (`settings_screen.dart:158`)
  stays **true** and should stay **unchanged**.

---

## 5. Authentication analysis

### 5.1 Three identities, deliberately separated

| Identity | What it is | Needed now? |
|---|---|---|
| **Store purchase identity** | The user's Apple Account / Google account, owned and managed by the store. Proves entitlement. | **Yes — and it is the only one needed.** |
| **Scrollary application identity** | A developer-run account (email + password, or a social login) identifying a person to *this app*. | **No.** Nothing in the product is per-user-across-devices. |
| **Cloud-sync identity** | An account that owns synced state on a developer-run server. | **No.** No server exists and none is proposed before Stage 4. |

### 5.2 Direct answers

**Does the first monetized version require Apple login?** No. Sign in with Apple
is triggered by guideline 4.8 only when a *third-party or social login service* is
used to establish the user's primary account. No login exists, so 4.8 does not
apply. Purchases already flow through the user's Apple Account without any
in-app sign-in.

**Does it require Google login?** No. Play Billing operates against the Google
account already signed into the Play Store on the device.

**Can store purchases be restored without a Scrollary account?** **Yes.** This is
the normal path on both platforms (§4.6): StoreKit 2 entitlements are read from
the local cache and refreshed via `AppStore.sync()` behind a Restore Purchases
button; Play returns owned purchases from `queryPurchasesAsync`. Reinstalling,
switching devices, or restoring a backup all work. The only requirement is that
the user is signed into the **same store account** — which is a property of the
device, not of Scrollary.

**Would introducing accounts early be harmful?** Yes, on four independent counts:

1. **Policy risk.** Apple 5.1.1(v) — "If your app doesn't include significant
   account-based features, let people use it without a login." An account in an
   app with no account-based features invites rejection.
2. **Obligation.** Account creation triggers mandatory in-app account deletion on
   both stores, plus a Play-required web deletion link — a public web property the
   project does not have (STORE_PACKAGE.md §8.5 lists the support/legal URLs as
   *not yet created*).
3. **Privacy and legal.** Holding email addresses makes the developer a data
   controller under GDPR and Türkiye's KVKK, with the disclosure, retention,
   breach-notification and erasure duties that follow — and destroys the "nothing
   goes to the developer" claim that is currently the product's clearest privacy
   statement.
4. **Cost and support.** Password resets, lost-account recovery, and email
   deliverability are ongoing work with no revenue attached.

**When would a Scrollary account become genuinely useful?** Only when there is
state that must exist somewhere other than one device: cross-device reading
position, cloud backup of Collections and reading state, or a web/desktop
companion. Nothing else.

**If cloud sync arrives later, what auth is appropriate?** In order of
preference: (a) **no account at all** — iCloud/CloudKit on Apple platforms and a
Google Drive app-data folder on Android put sync on the *user's* infrastructure
with no developer identity, no developer server and no personal data reaching the
developer; (b) if a first-party account is unavoidable, **email + one-time code**
(passwordless), which keeps Scrollary in the 4.8 exemption "Your app exclusively
uses your company's own account setup and sign-in systems"; (c) social login is
the worst option, because adding Google Sign-In immediately obliges an equivalent
privacy-preserving option under 4.8. In every case, sign-in must remain
**optional** — the local reader must keep working, unchanged, for a user who never
signs in.

---

## 6. Competitor research

Prices retrieved **2026-08-03** from the sources in §18. App Store in-app-purchase
lists are live listing data; figures attributed to review articles are marked.

### 6.1 The comparison table

| App | Category | Free tier | Paid | Price (2026-08-03) | Account | Offline | On expiry |
|---|---|---|---|---|---|---|---|
| **GoodLinks** | Read-it-later, local-first, iOS | — (paid app) | One-time app purchase + optional annual feature upgrade | **USD 9.99 once**; "Annual Feature Upgrade" **USD 4.99**; tips USD 0.99–19.99 | No | Yes, local | N/A — never expires; unpaid upgrade only stops *new* features |
| **Panels** | Offline reader for image-based book files, iOS/Mac | Import, organise, read, track progress | Panels+ subscription **or** major-version unlock | **USD 1.49/mo · USD 14.99/yr · USD 19.99 major version (Panels 3) · USD 9.99 upgrade** | No | Yes, local files | Local library keeps working; premium features lock |
| **Instapaper** | Read-it-later, server-backed | Save, sync, folders, 5 notes/month | Premium | **USD 5.99/mo · USD 59.99/yr** | **Required** | Via sync | Content stays in the account; premium features lock |
| **Readwise Reader** | Read-it-later + highlights, server-backed | Trial only | Full Readwise subscription | **USD 9.99/mo billed annually (USD 119.88/yr) · USD 12.99/mo monthly** *(review-article figures)* | **Required** | Partial | Access ends |
| **Obsidian** | Local-first notes | **Entire app, free, no sign-up** | Sync / Publish add-ons | Sync **USD 4/mo annual, USD 5/mo monthly**; Publish **USD 8–10/mo**; optional commercial licence USD 50/user/yr | No (app) / Yes (Sync) | Fully local | Local vault untouched; only sync stops |
| **Aidoku** (iOS), **Mihon** (Android) | Free readers for serialised image-based sources | **Everything** | — | **Free, open source, ad-free** | No | Yes | N/A |
| **Pocket** | Read-it-later | Was freemium | Premium | **Discontinued** — service ended 2025-07-08, data deleted 2025-10-08, subscribers refunded pro rata | Required | Was sync-based | Everything ended |

### 6.2 What each one actually teaches

**GoodLinks is the closest structural analogue and the strongest single data
point.** A local-first reading tool, one developer, no server, **USD 9.99 one-time**
— plus a genuinely clever answer to the maintenance-funding problem: an optional
**USD 4.99 "Annual Feature Upgrade"** that buys another year of *new* features
while everything already purchased keeps working forever. That is a voluntary
subscription with no expiry cliff and no policy exposure under 3.1.2(a), because
nothing is taken away. **Directly applicable; §12.1 and §14 build on it.**

**Panels proves the price band for an offline reader of image-based content**, the
same content category as Scrollary's primary use case: **USD 1.49/mo, USD 14.99/yr,
or USD 19.99 for a major version**, with a free tier that genuinely reads. Two
lessons: (a) a reader of this kind can charge subscription prices *and* a lifetime
price simultaneously without confusing anyone; (b) even at USD 19.99, the "buy this
major version forever" option is the one that requires no ongoing promise. **Caveat:
the App Store listing shows a last update of 2024-07-26, so this is a mature app in
maintenance, not a growth exemplar.**

**Instapaper and Readwise Reader price 6–12× higher, and both run servers.**
Instapaper's premium list is essentially *server* features — full-text search over
an account, a permanent archive, cross-device sync, Kindle delivery, AI voices.
That is what a subscription is buying. **Scrollary has none of those and cannot
justify their prices.** The lesson is not "charge less"; it is "a subscription's
believability comes from the recurring cost behind it".

**Obsidian is the local-first pattern in its purest form**: the app is free
without limits and without sign-up; the *only* paid things are the two services
that cost the company money every month (Sync, Publish). If Scrollary ever builds
cloud sync, this is the template — free local app, paid cloud. It is also a
caution: Obsidian monetizes almost nothing else, which works at their scale and
may not at 1,000 users.

**Aidoku and Mihon are free, open-source and ad-free, and they are the direct
competition for the image-sequence use case.** This is the most uncomfortable finding in
this section and it must not be glossed over. Two mitigations, both real:
(i) they are not App Store apps in the ordinary sense — Aidoku is beta software
distributed outside the App Store, Mihon is Android-only sideloading; the audience
willing to do that is not the audience that pays USD 9.99 for a store app;
(ii) Scrollary is a *general* web reader with a restricted-site refusal policy and
a store-compliant posture, which is a different product with a different
distribution channel. But the pricing implication stands: **there is a free
substitute for the headline use case, and the price must respect that.** It argues
against a subscription and for a modest one-time price.

**Pocket is the cautionary tale, and it is recent.** A well-funded, widely used,
account-and-server read-it-later service shut down on 2025-07-08 and deleted all
user data on 2025-10-08. Every user's library depended on someone else's server
staying up. Scrollary's entire architecture is the opposite bet, and that is worth
saying in the store listing — **but only if the monetization model does not quietly
reintroduce the same dependency.** A model whose entitlement check requires a
developer-run server would do exactly that.

### 6.3 What does *not* transfer

- **Do not copy Instapaper/Readwise prices.** They sell hosting; Scrollary sells
  software.
- **Do not copy Panels' subscription without copying its update cadence.** A
  subscription is a promise about the future, and §4.2 makes the promise
  enforceable at review.
- **Do not copy Obsidian's "free forever, monetize the cloud".** It is the right
  *destination* (§14, Stage 4) but it produces zero revenue until a cloud service
  exists, which is precisely the speculative infrastructure this project should
  not build first.

---

## 7. Monetization-model comparison

Evaluated against this product, this codebase and one developer. "Backend"
means a developer-run server.

| # | Model | Acquisition friction | Expected conversion *[Assumption]* | Store fit | Impl. complexity | Backend | Account | Restore | Support burden | Pricing clarity | Frustration risk | Solo sustainability | Local-first fit | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Fully paid app** | **Highest** — no install without payment; kills discovery, kills word of mouth, near-fatal in Türkiye | 100% of installs, but installs collapse | Fine | **Lowest** — no IAP code at all | No | No | Store-native, automatic | Very low | Perfect | Low | Good | Perfect | **Alternative C** (§12.3) |
| 2 | **Free + hard paywall** | High — the app is a brochure until paid | Low | Allowed, but Apple 2.3.2 disclosure and review scrutiny | Low | No | No | Store-native | Medium — "I can't try it" | Muddy: why not just a paid app? | **High** | Medium | Poor — free users get nothing | **Rejected** |
| 3 | **Free trial → subscription** | Low to install, high to keep | Medium | Allowed; **3.1.2(a) "ongoing value" applies** | High — trial state, expiry, grace, hold, win-back | No | No | Store-native | **High** — trial-end and billing-failure contacts | Medium — trial mechanics need explaining | Medium-high | **Poor** — recurring obligation | **Rejected for v1** |
| 4 | **Freemium, permanent free limits** | **Lowest** | Low-medium | Excellent | Medium — one boundary to enforce | No | No | Store-native | Low | **Highest** if the boundary is one sentence | Low if the free tier is honest | **Best** | **Core of the recommendation** |
| 5 | **Subscription + optional lifetime** | Low | Medium | Allowed; both products must be honest | **Highest** — two entitlement shapes, upgrade paths, "I bought lifetime, why am I charged?" | No | No | Store-native | High | **Poor** — two prices need explaining | Medium | Medium | **Alternative A** (§12.1) |
| 6 | **One-time Pro unlock** | Lowest | Low-medium | Excellent; simplest possible review story | **Low** — one non-consumable, one restore button | No | No | Store-native, permanent | **Lowest** | **Highest** — one number, forever | **Lowest** | **Best** | **★ Recommended** |
| 7 | **Low-cost supporter subscription** | Low | Very low | Allowed; 3.1.2(a) still applies if it unlocks anything | Medium | No | No | Store-native | Medium | Medium | Medium | Medium | **Rejected as primary**; viable as a *later* voluntary add-on |
| 8 | **Donations / tips** | None | ~0.1–1% *[weak evidence]* | Apple 3.1.1: "Apps may use in-app purchase currencies to enable customers to 'tip' the developer" — permitted. Play treatment **[Unverified]** | Low | No | No | N/A (consumable) | Low | High | None | Cannot fund the app alone | **Supplement only** (§14, Stage 3) |
| 9 | **Usage-based** | — | — | — | — | — | — | — | — | — | — | — | **Rejected outright.** There is no metered cost to pass on, and pricing per saved Entry would literally monetize volume of capture — the exact reading of the product that STORE_POLICY_MAP.md §1–2 exists to refute. |
| 10 | **Later cloud-sync subscription, local reader free/paid separately** | Low | N/A | Excellent — a real service justifies a real subscription | High | **Yes** | **Yes** | Needs server-side linkage | High | High | Low | **Only with revenue to fund it** | **Correct destination, wrong starting point** (§14, Stage 4) |

### 7.1 Why model 6 beats model 3 here — the arithmetic

At USD 0.99/month with 15% commission, net revenue is **USD 0.84/month**. A
USD 9.99 one-time unlock nets **USD 8.49**. Break-even is **10.1 months of paid
retention**, before counting involuntary churn from billing retry and account
hold (§4.4). Consumer subscription retention at twelve months is very commonly
below that *[Assumption — no first-party data exists for this app, and no analytics
will be added to obtain any]*, so the subscription would need both a higher price
and better-than-typical retention merely to match a single unlock — while adding
every state in §4.4 to the support surface.

At USD 9.99/year the break-even is immediate (identical first-year revenue), and
the subscription wins from year two onward **if and only if** renewals hold. That
is the honest case for Alternative A, and it depends entirely on a sustained
update cadence — which is exactly what guideline 3.1.2(a) demands anyway.

---

## 8. Free versus paid feature matrix

### 8.1 Three candidates ruled out before commercial analysis

These are not judgement calls. They are prohibited by standing rules:

| Candidate | Ruling | Rule |
|---|---|---|
| **Supported-site presets** | **Never, at any price, free or paid.** No hostname, selector, site list or provider catalogue may ship anywhere in the binary, tests, fixtures or docs; `test/repository_cleanliness_test.dart` fails the build. The one exception is the *refusal* list in `capture_policy.dart`, and "no rule that *enables* anything" may be added to it. | CLAUDE.md; ARCHITECTURE.md §7.1 |
| **Background / unattended processing** | **Never.** "Nothing saves in the background. Queued work waits for an explicit Start, and that authorisation is never persisted." Selling background saving would require deleting the product's central safety property. | CLAUDE.md; ARCHITECTURE.md §5 |
| **Update-check *frequency* / scheduling** | **Not a thing that exists.** An update check is "a visible foreground operation" the user starts. There is no scheduler to sell a faster tier of. | ARCHITECTURE.md §9 |

### 8.2 The positioning constraint that decides the boundary

The obvious paywall — "free saves one page, Pro saves many" — is the **wrong**
one for this product, despite being the strongest revenue lever.

STORE_POLICY_MAP.md exists to establish that Scrollary is a personal reader and
not a bulk fetcher. A price list whose headline is *"Pro: save more pages at
once"* hands a reviewer, and every reader of the listing, the opposite reading —
that the app's value **is** volume of capture, and that the developer is selling
it. That risk is concrete: Apple 2.3 (accurate metadata) and 5.2.2, Play's
Deceptive Behavior and IP policies, and the residual-risk register in
STORE_POLICY_MAP.md §10 all point at the same surface.

**Therefore: multi-entry saving stays free and bounded exactly as it is today**,
and Pro sells something other than volume of capture. This costs some
conversion. It protects the thing that is harder to get back.

*This section's reasoning survives the supersession and is the reason the final
boundary is what it is.* Where it concluded "Pro sells ~~*library management*~~",
the decision landed one step further out: **Pro sells neither capture volume nor
library capability — it sells not having to watch.** The same argument applies
with more force to checking than to saving. *"Pro: find out whether your
collection updated"* prices the library's own knowledge of itself, which is
closer to the volume framing this section rejects, not further from it.

### 8.3 The matrix

> **⚠ This matrix is a 2026-08-03 proposal, and it is not what shipped.** Read
> it as one option that was considered, not as a plan of record and not as a
> description of the app.
>
> **What shipped instead** gates exactly one behaviour: whether a
> Browser-dependent phase may continue while another screen is in front
> (FOREGROUND_MULTITASKING.md §10.3). Everything else in that specification's
> matrix is unconditional, including the operation indicator, cancellation,
> failure states, retry, recovery and every access to already-downloaded
> content. Foreground multitasking does not appear anywhere in the table below,
> because it did not exist when this was written.
>
> **One row below has been decided against, not merely left unbuilt.**
> *Automatic update checking → Pro* is **superseded**. The product decision is
> that **update checking is Free** — a single Collection check, the Library-wide
> check, and every Entry either discovers — and that the Pro capability is
> **foreground multitasking** instead. Do not implement the row below, and do
> not treat it as a pending requirement.
>
> It is also blocked in code: `test/library_check_test.dart` fails the build if
> entitlement, tier, counter or purchase vocabulary appears anywhere in `lib/`
> outside a short exemption list — the capability seam plus the three files that
> merely name it — and its failure message states the reason: *checking is
> unrestricted*. That guard is now the executable form of the decision, not an
> accident to be worked around.

Legend: **Free** = permanent, unlimited, no paywall · **Pro** = one-time unlock ·
**Cloud** = only meaningful with a service that does not exist · **Never** = ruled
out by §8.1.

| Area | Tier | Reasoning |
|---|---|---|
| **Number of Collections** | **Free, unlimited** | A cap on a local list is arbitrary rent. Nothing about a Collection costs the developer anything. |
| **Number of saved / downloaded Entries** | **Free, unlimited** | Same. Also: a cap would make the library itself feel rationed, which is the one thing a *library* must never feel. |
| **Offline storage limits** | **Free, device-limited only** | The only real limit is the device. `SaveConfig.minFreeSpaceToStart` / `emergencyReserve` already protect the device honestly. |
| **Automatic multi-Entry saving** | **Free, bounded as today** | See §8.2. Bounded by a number the user typed, clamped to `maxEntriesPerRun`. **Open decision D-3 (§17):** whether free runs get a lower visible cap. |
| **Queue size** | **Free: 1 pending task · Pro: full depth + reordering** | A defensible convenience boundary that does not touch how much can be saved in total — a free user can queue one, run it, queue the next. |
| **Background / unattended processing** | **Never** | §8.1 |
| **Automatic update checking** | ~~**Pro**~~ → **FREE. Superseded by product decision.** | The 2026-08-03 reasoning, kept for the record: "Did a new Entry appear?" is the recurring-value question for the image-sequence use case, and its detection logic carries the most ongoing maintenance cost of anything in the app. **Rejected.** Checking is core library function — a library that cannot tell you it has grown is a worse library, not a cheaper one — and the cost argument justifies charging for maintenance, not for withholding the answer. What is sold instead is **not having to watch the check run**: foreground multitasking (§10.0 of FOREGROUND_MULTITASKING.md). Both granularities are Free: one Collection, and the Library-wide check that repeats it |
| **Foreground multitasking** — an operation continuing while the user reads or browses elsewhere **in the app** | **Pro** — and the only Pro row that reflects a decision | Did not exist when this matrix was written. It sells convenience rather than capability: the Free user runs the same check and the same save, gets the same results, and waits with the Browser on screen. Never described as background execution; nothing runs once the app is not in front |
| **Update-check frequency** | **Never (does not exist)** | §8.1 |
| **Retry and recovery tools** | **Free** | Data protection. Retrying a failed save, resuming an interrupted run, and `storage/recovery.dart` rebuilding rows from packages are how a user does not lose work. Never paywalled. |
| **Advanced capture controls** (per-collection `preferred_capture_mode`, duplicate policy) | **Pro** | Genuinely advanced, genuinely optional; the defaults are correct without them. |
| **User-assisted capture** — teaching a page element | **Free for the run in front of you** | It is the fallback that makes the core act work when detection is weak. Charging for it means the free app fails on hard pages, which is "intentionally broken". |
| **Saved rules** — persisting a taught hint and reusing it (`user_page_hints`) | **Pro** | The *reuse* is the convenience. Teaching once and having it work forever is a real, separable benefit. |
| **Text-based Entry support** (`textOnly`, `textAndImages`) | **Free** | A capture mode is what a page *needs*, not a premium. "The engine can only carry out modes `CaptureCapabilities` allows" — making one of them paid would produce a save sheet whose disabled reason is "buy Pro", which is a button that lies about the page. |
| **Collection organisation** (create, rename, reassign, archive, restore) | **Free** | Core library function. |
| **Tags, folders, pin, favourite, advanced sorting** | **Pro when built** | None exists today — `LibrarySort` has two values. Genuinely additive; safe to price. |
| **Reading progress · resume · completion** | **Free** | User-owned state. Never gated, never lost. |
| **Reading history** | **Free** | Same. |
| **Custom reader settings** (beyond a good default) | **Pro when built** | Additive polish. The default reading experience must be excellent for free. |
| **Cleanup automation** (per-collection preference, bulk removal, undo) | **Free** | Storage management is device hygiene and accidental-data-loss prevention. Charging for the undo window would be indefensible. |
| **Backup and export** | **Not offered yet; needs approval** | CLAUDE.md forbids export to Photos, Gallery, Downloads or shared storage. Any export feature is a rule change, not a pricing decision → **D-6 (§17)**. If it ships, an *Entry package* export is a reasonable Pro feature; a *reading-state* backup is data protection and should be free. |
| **Import and migration** | **Not offered; out of scope** | No format to import from. Revisit only with demand. |
| **Cross-device sync** | **Cloud** | §14 Stage 4. |
| **Cloud backup** | **Cloud** | §14 Stage 4. |
| **Desktop companion** | **Out of scope** | No desktop platform exists in the repository. |
| **Advanced diagnostics** (run logs, save reports, stop-reason detail) | **Pro** | Power-user feature; the *user-facing* stop reason and its plain sentence stay free — a user must always be told why something stopped. |
| **Supported-site presets** | **Never** | §8.1 |
| **Privacy / security features** (app-private storage, no analytics, clear website data, local reset) | **Free, always** | These are the product's identity. Selling privacy back to the user would contradict every claim in PRIVACY.md. |
| **Restore Purchases** | **Free, always, and prominent** | Required by Apple 3.1.1; must be reachable without owning anything. |
| **Accessibility** | **Free, always** | Non-negotiable. |

### 8.4 The one-sentence version

**Proposed on 2026-08-03, and superseded:**

> ~~**Free: browse, save, keep, read, organise — the whole reader, with no limits on
> what you keep.
> Pro: the tools that watch your library for you — update checks, saved rules,
> capture preferences, queue depth and diagnostics.**~~

**The current decision**, and the sentence that matches what shipped — one
behaviour, with the free path the correct path rather than a degraded one:

> **Free: all of it — including checking for new Entries — with Scrollary on
> screen while the check or save works.
> Pro: keep reading while it works.**

If the boundary cannot be stated in one sentence a user believes, it is the wrong
boundary. That test is what retired the five-item version: *"we watch your
library for you"* sells a capability the free app already has, so the user is
paying to stop being told to stand still — which is only honest if the standing
still is the only thing removed.

---

## 9. Pricing analysis

### 9.1 Fixed costs to clear

| Cost | Amount | Note |
|---|---|---|
| Apple Developer Program | **USD 99/year** | Recurring; the iOS listing disappears without it |
| Google Play registration | **USD 25 once** | One-time |
| Support/legal/privacy URLs (domain + hosting) | ~USD 15–60/year *[Assumption]* | Required by STORE_PACKAGE.md §8.5; not yet created |
| Demo site hosting (DEMO_CONTENT.md) | ~USD 0–60/year *[Assumption]* | Needed for reviewers and live verification |
| Backend | **USD 0** | By design |
| Analytics | **USD 0** | By rule |

**Floor: roughly USD 120–220/year.** At USD 9.99 one-time with 15% commission
(USD 8.49 net), that is **15–26 unlocks per year** to keep the lights on. That is
a legible, motivating target — and a useful sanity check on any model that needs
hundreds of paying users just to break even.

### 9.2 Net revenue per unit

| Product | List | Commission | Net to developer |
|---|---|---|---|
| One-time unlock | USD 9.99 | 15% (Apple SBP; Play 15% standard / 10%+5% in US-EEA-UK) | **USD 8.49** |
| Annual subscription | USD 9.99/yr | 15% | **USD 8.49/yr** |
| Monthly subscription | USD 0.99/mo | 15% | **USD 0.84/mo** |
| Monthly subscription | USD 1.49/mo | 15% | **USD 1.27/mo** |
| Lifetime (if offered) | USD 24.99 | 15% | **USD 21.24** |

VAT/sales tax is collected and remitted by the stores in most markets and is not
in these figures; Turkish income tax on the developer's proceeds is outside this
document's scope and should be checked with an accountant before the first payout.

### 9.3 Is USD ~1/month a good idea? No.

Technically possible (§4.10). Commercially poor, for four reasons:

1. **Break-even against a one-time unlock is 10.1 months** (§7.1), before
   involuntary churn.
2. **Support cost is not proportional to price.** A USD 0.99/month subscriber
   generates exactly the same billing-retry, grace-period, account-hold, expiry
   and restore questions as a USD 9.99/month subscriber, against USD 0.84 of
   revenue.
3. **A very low price signals low value.** Apple's own guidance warns about the
   opposite failure (3.1.1: "We'll reject expensive apps that try to cheat users
   with irrationally high prices"), but the underpricing failure is real and
   asymmetric: raising a subscription price later requires a consent or notice
   flow and reliably costs subscribers, whereas a one-time price can be raised for
   *new* buyers at any moment with **zero effect on anyone who already bought**.
4. **It buys a permanent obligation.** Guideline 3.1.2(a) ties the subscription to
   ongoing value for as long as it renews.

### 9.4 Regional pricing, and Türkiye specifically

Set the **base storefront to the United States at USD 9.99** and let both stores
generate equivalents — then **manually manage Türkiye**.

The reasoning is in Apple's own documentation: "Prices for your base country or
region won't be adjusted by Apple as taxes and foreign exchange rates change",
while other storefronts *are* adjusted "based on changes in taxes and foreign
exchange rates". For a lira-denominated market with sustained depreciation, a
USD-anchored auto price does not stay still — it **ratchets upward in TRY**,
repeatedly, without a decision ever being made. Turkish coverage retrieved
2026-08-03 describes exactly this pattern of repricings, including the entry app
tier moving ₺10.99 → ₺16.99.

Recommendation:

- **Manually manage the Türkiye storefront** on both stores, accepting the stated
  trade-off: "you'll be responsible for staying up to date with taxes and exchange
  rates in the storefronts you manually manage."
- Target a Turkish price in the band of **the local equivalent of roughly USD 2–4**,
  not USD 9.99. *[Assumption — based on the observation that Türkiye is
  consistently the lowest-priced major storefront on both stores and that Aidoku
  and Mihon are free substitutes for the headline use case. No purchasing-power or
  willingness-to-pay data specific to this audience exists. Weak evidence; treat
  as a starting point to be revised from actual unit sales.]*
- **Read the live price tables in App Store Connect and Play Console** before
  setting anything. The TRY values quoted anywhere in this document are
  **[Unverified]** and will have moved.
- Review the Turkish price on a fixed cadence (twice a year) rather than reactively.

### 9.5 Does USD 9.99 communicate enough value?

Yes, and the evidence is direct: **GoodLinks charges exactly USD 9.99 once** for a
local-first reading tool from a solo developer with no server, and **Panels charges
USD 14.99/year or USD 19.99 for a major version** for an offline reader in the
same content category.
USD 9.99 sits inside a band the category has already validated, below Panels'
lifetime, and far below any server-backed competitor. It is a price a user
recognises as "a real app, bought once".

### 9.6 The risks of getting the price wrong

| Risk | Direction | Mitigation |
|---|---|---|
| **Priced too low** | Revenue never clears fixed costs; the app reads as disposable; raising later is awkward for subscriptions | One-time price → raise for new buyers freely; existing buyers unaffected |
| **Priced too high** | Free substitutes (Aidoku, Mihon) win the image-sequence audience; Türkiye is priced out entirely | Manual Türkiye pricing; keep the free tier genuinely complete |
| **Turkish price drifts upward via auto-pricing** | Silent, repeated, unintended increases | Manually manage the TR storefront (§9.4) |
| **Subscription price increase later** | Requires a consent/notice flow; reliably costs subscribers | Avoided entirely by the recommended model |
| **Paying for a promise not kept** | The 3.1.2(a) "consistent, substantive updates" basis erodes if the update cadence stops | Avoided entirely by the recommended model |

---

## 10. Revenue scenarios

**These are arithmetic over stated assumptions, not forecasts, and not promises.**

**Assumptions, all explicit:**
- "Active users" = people with the app installed and using it, not downloads.
- Commission **15%** on both stores (§4.8).
- Conversion rates of **1% / 3% / 5%** are the commonly cited freemium band.
  **[Assumption — weak evidence.]** No first-party data exists, none of the
  competitors publish theirs, and the no-analytics rule means in-app conversion
  will never be measured. Treat the 3% column as a mid-case illustration only.
- One-time revenue is **non-recurring**: each row is a cohort converting once.
- Subscription rows assume all subscribers convert in the same year and use a
  **60% year-2 renewal** rate **[Assumption]**.
- Nothing here accounts for refunds, income tax, or FX on non-USD storefronts.

### 10.1 One-time unlock at USD 9.99 (net USD 8.49) — the recommendation

| Active users | 1% | 3% | 5% |
|---|---|---|---|
| 1,000 | 10 → **USD 85** | 30 → **USD 255** | 50 → **USD 425** |
| 5,000 | 50 → **USD 425** | 150 → **USD 1,274** | 250 → **USD 2,123** |
| 10,000 | 100 → **USD 849** | 300 → **USD 2,548** | 500 → **USD 4,245** |

Fixed costs (~USD 120–220/yr) are cleared at roughly **1,000 active users at 3%
conversion**, or 2,500 at 1%.

### 10.2 Annual subscription at USD 9.99/yr (net USD 8.49/yr)

| Active users | 3% conversion | Year 1 | Year 2 (60% renewal, same cohort only) |
|---|---|---|---|
| 1,000 | 30 | USD 255 | USD 153 |
| 5,000 | 150 | USD 1,274 | USD 764 |
| 10,000 | 300 | USD 2,548 | USD 1,529 |

Identical to the one-time model in year 1; **better than one-time in year 2 only
if renewals hold and no new cohort would have arrived anyway** — and every
renewing year carries the 3.1.2(a) obligation.

### 10.3 Monthly subscription at USD 0.99/mo (net USD 0.84/mo)

Per-subscriber net by retention: 3 months → USD 2.52 · 6 months → USD 5.05 ·
**10.1 months → USD 8.49 (break-even against one-time)** · 12 months → USD 10.09 ·
24 months → USD 20.17.

| Active users | 3% conversion | If avg. retention is 6 months | If avg. retention is 18 months |
|---|---|---|---|
| 1,000 | 30 | USD 151 | USD 454 |
| 5,000 | 150 | USD 756 | USD 2,268 |
| 10,000 | 300 | USD 1,513 | USD 4,535 |

**Reading of this table:** at plausible consumer retention, USD 0.99/month
*underperforms a single USD 9.99 unlock* while costing considerably more to run.
It only wins with retention roughly a year and a half or longer.

### 10.4 Sensitivity — what actually moves the number

Ranked by leverage:

1. **Installs.** Every scenario is linear in users, and the app currently has
   zero. Discovery work — the listing, screenshots, the name, the demo site — is
   worth more than any pricing refinement at this stage.
2. **Conversion**, driven by whether the Pro boundary is felt as fair.
3. **Price.** USD 9.99 → USD 14.99 is +50% revenue per conversion, with unknown
   conversion cost. Testable later by raising the price for new buyers only.
4. **Commission.** Fixed at ~15%; not worth optimising at this scale (§4.11).

### 10.5 The honest conclusion

**At 1,000–10,000 active users, no model in this document produces a salary.** The
realistic outcomes are "covers its costs" to "a few thousand USD per year".
The correct decision criterion is therefore *not* revenue maximisation — it is
**which model costs the least to run and is least likely to make users feel
cheated**, since those are the terms on which the app can survive long enough to
have a larger audience. That criterion points at the one-time unlock unambiguously.

---

## 11. Recommended initial model

### 11.1 The recommendation

**Free app · permanently usable free tier · one non-consumable in-app purchase,
"Scrollary Pro", USD 9.99 (Türkiye priced manually) · no subscription · no trial ·
no login · no backend.**

### 11.2 Every question answered

| Question | Answer |
|---|---|
| Free, paid, freemium or trial-first? | **Freemium**, permanent free limits. |
| Subscription, lifetime or both? | **A single one-time purchase.** Not a subscription, not a "lifetime" tier alongside one. |
| Monthly/annual price positioning? | **None.** No recurring price exists in v1. |
| Should a trial exist? | **No.** The free tier is the trial, permanently, with no countdown and no expiry email. Apple's Tier-0 "XX-day Trial" mechanism is available but adds receipt/DeviceCheck work for a worse experience. |
| What is in the permanent free tier? | The entire reader: browsing, saving (single **and** bounded multi-entry), all three capture modes, unlimited Collections and Entries, offline reading, reading position and resume, archive/restore, sorting, storage management and cleanup with undo, permanent deletion, retry and recovery, activity history, user-assisted capture for the run in front of you, appearance settings, browsing history, saved sites, clear website data, local reset, **and Restore Purchases**. |
| What is in Pro? | ~~Update checking · saved rules (persisted page hints) · per-collection capture preference and duplicate policy · queue depth and reordering · advanced diagnostics · tags/pins/advanced sorting and reader customisation **when they exist**.~~ **Superseded.** Pro is **foreground multitasking** — a supported operation continuing while the user reads or browses elsewhere in the app. **Update checking moved to Free** (§8.3, and FOREGROUND_MULTITASKING.md §10.0). The remaining items on the old list were never decided and are not requirements |
| Is login needed? | **No** — and requiring one would risk 5.1.1(v). |
| Is a backend needed? | **No.** |
| How do entitlements behave offline? | Read from the store's on-device cache, mirrored into the existing `settings` table, and **fail open**: an unknown answer grants Pro (§11.5). |
| What happens after expiry? | **Not applicable** — a non-consumable never expires. Under Alternative A, see §13. |
| What happens to previously downloaded Entries? | **Nothing, ever.** No entitlement state may write `content_path`, `byte_size`, `lifecycle`, `offline_removed_at`, or any reading column. |
| How does restore work? | A **Restore Purchases** row in Settings, always visible, that calls `AppStore.sync()` / re-queries Play. No account. |
| How do we avoid surprising users? | Price and scope stated before purchase (3.1.2(c), Play disclosure duty); IAP disclosed in both store listings (2.3.2); Pro features visible-but-locked with a plain reason rather than hidden — the same pattern the save sheet already uses for unavailable capture modes; **no interstitial paywall on launch**; no countdown; no email. |
| Explicitly out of scope for v1 | Accounts · cloud sync · cloud backup · analytics · ads · subscriptions · external payment flows · promo-code infrastructure · desktop companion · usage-based pricing · supported-site presets (forbidden) · background processing (forbidden). |

### 11.3 Why this and not the user's initial idea

The initial sketch — ~USD 1/month or ~USD 9.99/year — is technically supported by
both stores. It is not recommended because:

- **USD 0.99/month needs 10.1 months of retention to match one USD 9.99 unlock**
  (§7.1, §10.3) while adding billing retry, grace period, account hold, expiry
  messaging and win-back to a solo developer's support load.
- **A local app's subscription rests on the weakest of Apple's permitted
  justifications** — "consistent, substantive updates" (§4.2) — converting a price
  into an indefinite delivery obligation enforceable at review.
- **The USD 9.99/year figure is right; the recurrence is wrong.** Keep the number,
  charge it once (§9.5), and revisit recurrence when there is a recurring cost to
  fund.

### 11.4 Why no trial

A permanent free tier that saves and reads Entries without limits is a *better*
trial than a countdown: it never expires, never emails, never asks for a card, and
never produces the "my app stopped working" contact. It also removes an entire
class of implementation (trial state, clock tampering, receipt checks) from a
codebase that has no server to adjudicate any of it.

### 11.5 Entitlement behaviour, stated as a rule

> **The entitlement check fails open.** If StoreKit or Play cannot be reached, or
> the local cache has not synced, and the app has previously recorded a purchase
> in `settings`, Pro is **granted**. A paying user on an aeroplane, on a new
> device mid-restore, or behind a captive portal must never be told they do not
> own what they bought.

The cost of this rule is that Pro is trivially bypassable by anyone willing to
edit an unencrypted SQLite row. **That is accepted and should be stated
internally rather than defended against.** A USD 9.99 local app cannot win a DRM
arms race, the attempt would require exactly the server this document argues
against, and the users who would edit the row were never going to buy. Nothing
here is DRM and nothing should be built to look like it.

### 11.6 Two small configuration decisions

- **Enable Family Sharing on the non-consumable.** It costs nothing, it is
  goodwill, and it reduces "my partner's phone doesn't have it" contacts. Mild
  revenue dilution, accepted.
- **Enrol in the App Store Small Business Program before the first sale** — 15%
  instead of 30%, and the adjustment only takes effect 15 days after the fiscal
  month in which enrolment is approved (§4.8), so late enrolment loses real money.

---

## 12. Alternative models

### 12.1 Alternative A — Free + Pro subscription with a lifetime option (the Panels model)

**Shape:** free tier as recommended; Pro available at **USD 1.49/month**,
**USD 9.99/year**, or **USD 24.99 once ("lifetime")**. Optionally, outside the US
and Singapore, Apple's monthly-with-12-month-commitment for a lower headline
monthly price (§4.3).

**Choose this if — and only if —** the developer commits to a visible, sustained
update cadence, because that is the entire basis on which guideline 3.1.2(a)
permits it.

| For | Against |
|---|---|
| Recurring revenue that grows with a growing user base | Three prices to explain; §7 rates "subscription + lifetime" worst on pricing clarity |
| Directly validated by Panels in the same content category | Every state in §4.4 becomes a support surface |
| The lifetime tier gives one-time buyers a home | An indefinite obligation under 3.1.2(a) |
| Higher ceiling if the app succeeds | Expiry behaviour must be designed and tested (§13) — dead code until it fires, and wrong when it does |

### 12.2 Alternative B — Free + one-time Pro + optional paid annual feature upgrade (the GoodLinks model)

**Shape:** exactly the primary recommendation, plus a **voluntary** "Another year
of new features — USD 4.99" purchase introduced *only after* a year of shipped
work exists to point at. Everything already purchased keeps working forever;
declining the upgrade takes nothing away.

**This is the primary recommendation's natural successor, not a competitor to
it** — which is why it appears as §14 Stage 2 rather than as a v1 choice. It is
listed here because if the product owner wants recurring revenue *without* the
3.1.2(a) obligation and without any expiry behaviour, this is the way to get it.
Its weakness is honest: uptake on a voluntary upgrade is unknown and probably low
*[weak evidence — GoodLinks does not publish figures]*.

### 12.3 Alternative C — Paid-upfront app, no IAP

**Shape:** **USD 4.99** to download; no free tier, no IAP, no entitlement code at
all.

| For | Against |
|---|---|
| Simplest possible implementation — *zero* purchase code; the app never asks about tiers | Destroys discovery: no one installs an unknown paid app from an unknown developer |
| Simplest review story; no IAP metadata to get wrong | Near-fatal in Türkiye and other price-sensitive markets |
| No paywall UI, no restore flow to design (store handles redownload) | No word of mouth — nobody can show a friend |
| No boundary to argue about | Cannot be undone: converting a paid app to freemium later strands early buyers, and 3.1.2(a) warns against removing what existing users paid for |

**Verdict:** correct only if the goal is to ship the simplest possible thing and
accept a small audience. It is a real option and it is honest, which is why it is
listed — but it forecloses the most valuable asset an unknown app has, which is
free installs.

---

## 13. Subscription-expiry and user-data behaviour

**Under the primary recommendation, expiry does not exist.** This section defines
behaviour anyway, because (a) refunds and family-sharing revocation can revoke a
non-consumable, and (b) Alternative A needs it.

### 13.1 The invariant

> **Losing Pro removes future capability. It never removes anything the user
> already has.**

Concretely, on entitlement loss the app **must not** write: `content_path`,
`byte_size`, `offline_removed_at`, `lifecycle`, `archived_at`, `read_status`,
`progress_fraction`, `progress_page_index`, `progress_offset_in_page`,
`first_opened_at`, `completed_at`, `last_read_at`, `source_url`, or delete any
row or file. The codebase already makes most of this structurally hard: reading
state is writable only from `lib/reading/`, and permanent deletion exists only in
`CollectionDeletionService`. **An entitlement module belongs in neither.**

### 13.2 What happens, by surface

| Surface | On entitlement loss |
|---|---|
| Library, Collections, Entries | Unchanged. Every row stays. |
| Downloaded files | Unchanged. Every byte stays. |
| Offline reading | **Works exactly as before.** The reader must never consult entitlement state. |
| Reading position, progress, completion | Unchanged and still written. |
| Archive / restore | Unchanged, free. |
| Storage, cleanup, undo, permanent deletion | Unchanged, free. |
| Saving a page | Unchanged, free, single and bounded multi-entry. |
| **Update checking** | ~~Stops offering to start. Any queued check becomes a terminal row with a named reason.~~ **Superseded — checking is Free, so entitlement loss does not touch it.** A check still starts, still runs and still reports. What changes is only that it holds when the user leaves the Browser instead of continuing, which is the behaviour that shipped before the capability existed |
| **Foreground multitasking** | The *next* operation needs the Browser on screen; the one already running keeps the surface it started with and is never interrupted mid-page (`TaskCapabilitySnapshot`, FOREGROUND_MULTITASKING.md §10.5). The stored preference is kept, so restoring Pro restores the behaviour |
| **Saved rules** | Existing rules are **kept, not deleted**, and keep working for the run in front of the user; creating and managing them returns to Pro. **D-4 (§17)** — the alternative (rules stop applying) is defensible but punishes the user for work they did. |
| **Queue** | Existing rows are preserved. New enqueues beyond the free depth are refused with a reason. |
| Pro toggles already set (e.g. `preferred_capture_mode`) | **Left in place, honoured on the pages they apply to.** Silently reverting a stored preference is a change the user did not make. |

### 13.3 How a refusal is expressed

Reuse the pattern the codebase already has, rather than inventing one. A refused
task becomes a **terminal `failed` row carrying a named `StopReason`** — never a
silent deletion, never an auto-retry, never a partial Entry. A new
`StopReason.proRequired` (or similar) with its own plain sentence would sit
alongside `captureRestrictedForSite` in `lib/save/stop_conditions.dart` and
inherit every property that reason already has. This is design commentary, not an
instruction to implement.

The sentence must say what the app does, not what the user failed to buy — the
same rule `kCaptureRestrictedMessage` follows.

### 13.4 Refunds and revocation

Both stores can revoke a non-consumable (refund, family-sharing removal, chargeback).
The app should treat revocation exactly as §13.1–13.3 describe, and — given
§11.5's fail-open rule — should degrade only on a *positive* signal of
revocation, never on absence of a signal.

---

## 14. Proposed staged rollout

Each stage is gated on evidence from the previous one. **No stage builds
infrastructure for a stage that has not been justified.**

### Stage 0 — Ship free. No purchase code. *(Recommended before any monetization)*

> **Status note, added after the fact.** The app is still at Stage 0 by the only
> test that matters commercially — **nothing can be bought, and no purchase code
> exists**. But a Pro *boundary* now ships: one behaviour is gated, a locked row
> carries a `PRO` badge, and a Pro information sheet explains it with no Buy
> button behind it (FOREGROUND_MULTITASKING.md §10.6). That is more than this
> stage envisaged and less than Stage 1.
>
> Stage 0's exit criteria below are **not** met: the content-rights disclosures
> and the Privacy/Terms pages are still deferred, and the legal URLs do not
> exist. Whether a PRO-badged control should be visible in a build that has not
> yet shown its content-rights position is a live question, and it is **not
> resolved here** — see §17 D-5.

**Do this first.** ARCHITECTURE.md §10 lists the save-scope review step, the
first-use content-rights disclosures, and the Privacy/Terms/Content-rights pages
as **deferred**. Every one of those is a release blocker independent of money.
Adding a paywall on top of an app that has not yet shown its content-rights
position is the wrong order of work. (The third original reason — that the app
had never run on physical hardware — no longer applies: it has, see
ARCHITECTURE.md §10 and FOREGROUND_MULTITASKING_PLAN.md §6.)

Shipping free first also: produces the install base that every scenario in §10 is
linear in; gives a first submission with no IAP metadata to get wrong; and yields
the only pricing evidence that will ever exist for this app — real users, in real
markets, actually using it.

**Exit criteria:** the §10 deferred items are done; the app is on both stores;
there is a support address that a human reads.

### Stage 1 — Local Pro unlock

One non-consumable, USD 9.99, no login, no backend, entitlement in the existing
`settings` table, Restore Purchases in Settings, Family Sharing on, Small Business
Program enrolled.

**Exit criteria:** it works, purchases restore across a device change, and unit
sales are visible in both consoles.

### Stage 2 — Optional paid feature-year upgrade *(the GoodLinks pattern)*

Only once **a year of substantive shipped work exists to point at**. A voluntary
USD 4.99 purchase that buys another year of new features; nothing is ever taken
away from anyone who declines. Delivers recurring revenue with no expiry, no
grace period, no account hold, and no 3.1.2(a) exposure.

**Optionally alongside:** tip IAPs, which Apple explicitly permits ("Apps may use
in-app purchase currencies to enable customers to 'tip' the developer"). Play's
treatment of developer tips is **[Unverified]** — confirm before shipping on
Android.

**Exit criteria:** enough uptake to be worth the console maintenance, or a clear
answer that it is not.

### Stage 3 — Local backup and export *(needs a rule change, not just a decision)*

The most-requested thing a local-first library eventually needs is *"how do I get
my stuff off this phone"*, and the honest answer does not require a cloud. It does
require amending CLAUDE.md's export prohibition, so it is **D-6 (§17)**, not a
pricing decision. If it ships: reading-state backup free (data protection), Entry
package export as Pro.

### Stage 4 — Cloud sync or backup, and only then an account and a subscription

Build **only** on demonstrated demand from actual users, and only with revenue to
fund it. When it happens:

- **Prefer the user's own cloud** — iCloud/CloudKit on Apple, Google Drive
  app-data on Android — so there is no developer server, no account, no personal
  data, and Pocket's failure mode (§6.2) stays impossible.
- If a first-party service is unavoidable: passwordless email sign-in (keeps the
  4.8 exemption), mandatory in-app account deletion plus a web deletion link,
  a published privacy policy covering the new processing, and a **subscription** —
  which at that point is fully justified, because there is finally a recurring cost.
- **Sync metadata and reading state, never the saved page bytes.** This is the
  single most important constraint in the whole staged plan. Uploading captured
  third-party images and text to a developer-run server would make the developer a
  host of other people's copyrighted content, and would recast the app from
  "a personal reader" into a service that stores web content — the exact
  characterisation STORE_POLICY_MAP.md §1–2 is written to avoid. Syncing *"which
  Entries exist and where you are in them"* delivers most of the user value with
  none of that exposure.

**Exit criteria for even starting:** repeated, unsolicited user demand, plus
revenue from Stages 1–2 that covers the running cost before the first subscriber.

---

## 15. Implementation implications (not implemented)

Recorded so a later implementation task starts from the constraints rather than
rediscovering them. **Nothing below has been built.**

### 15.1 Dependency

A purchase client would be a **new dependency and therefore requires explicit
approval** (CLAUDE.md; the pubspec already carries a hard-won note about
`flutter_inappwebview` pinning). The obvious candidate is
**`in_app_purchase`**, published by the verified `flutter.dev` publisher,
latest **3.3.0** as of 2026-08-03, supporting iOS 13+/Android SDK 24+, both
subscriptions and non-consumables, restoration via `purchaseStream`, and **no
server requirement**. A third-party entitlement service (RevenueCat and similar)
would introduce a network dependency and a data processor, contradicting
PRIVACY.md, and should not be used.

### 15.2 Storage

Use the existing **`settings` key/value table**. The database is version 1 with
**no `onUpgrade` and no migration system**, so a new column or table is a schema
change the project is explicitly not set up to make. A settings key needs none.

### 15.3 Placement

**Already done, under a different name.** This section proposed
`lib/entitlement/`; what exists is **`lib/capability/`** — do not create a second
seam beside it. The rule it states is the one in force and is enforced by
`test/entitlement_test.dart`:

An entitlement module must live in its own directory and **must not be reachable
from `lib/reading/`, `lib/storage/cleanup.dart`, or `CollectionDeletionService`**.
That separation is what makes §13.1 structurally true rather than merely intended
— the same technique the codebase already uses for reading state and for the
capture policy.

### 15.4 Enforcement pattern

Follow `capture_policy.dart` exactly: **one module, asked at every boundary
independently, never copied.** A hidden button is not enforcement, and a second
copy is how the UI ends up hiding something the engine still honours. The
difference: the capture policy *refuses* and its list is a compliance boundary,
whereas entitlement is a commercial boundary that **fails open** (§11.5). Do not
let them share code or a mental model.

Server-side receipt verification is **not** recommended: it requires the backend
this document argues against, to protect USD 8.49 per bypass, in an app whose
value proposition is that it does not phone home.

### 15.5 Testing

`test/repository_cleanliness_test.dart` and `test/theme_palette_test.dart` both
scan `lib/` and fail the build on violations — any paywall UI must use
`AppPalette` and `HeaderIconButton`/`kHeaderActionSize`/`kHeaderIconSize`, and
must name no hosts. Store purchases cannot be exercised in `flutter test`; the
entitlement *decision* logic should therefore be pure Dart over injected state
(the same split the codebase already uses for detection: the bridge measures, Dart
decides), so it is testable without a store connection.

### 15.6 Copy and store metadata

- User-facing nouns come from `lib/library/entry_labels.dart` **and nowhere else**.
  Paywall copy must not invent its own.
- Apple 2.3.2 requires the IAP to be indicated in the description and screenshots
  — STORE_PACKAGE.md §2/§3/§4 (EN **and** TR) need an addition, and §6 needs the
  exact in-app paywall wording added the way every other sentence in that section
  is fixed.
- The App Privacy and Data safety answers (§8.1/§8.2) must be re-walked, with the
  expected outcome that nothing new is collected (§4.12).

---

## 16. Risks and unresolved questions

| # | Risk / question | Severity | Notes |
|---|---|---|---|
| R1 | **Free open-source substitutes** (Aidoku, Mihon) cover the headline image-sequence use case at zero cost | **High** | Mitigated by distribution channel and by pricing modestly, not eliminated. §6.2 |
| R2 | **Conversion rates are assumed, and will remain unmeasurable in-app** by rule | **High** | Only console unit sales will ever be visible. Argues for a model legible from one number. §3, §10 |
| R3 | **Google Play's fee split (2026-06-30) is days old** at the time of writing | Medium | Re-read both the Console fee page and the blog post before modelling non-subscription tiers. §4.8 |
| R4 | **Apple's US external-link position is before the Supreme Court** | Low for this plan | Only matters if an external flow were used; the recommendation avoids it entirely. §4.11 |
| R5 | **Türkiye price drift** via auto-generated pricing | Medium | Manual TR management, reviewed twice a year. §9.4 |
| R6 | **Paywall positioning could undermine STORE_POLICY_MAP.md** if Pro is framed as "save more" | **High** | Boundary chosen specifically to avoid it; the store copy must be reviewed against §8.2 before submission |
| R7 | **Local entitlement is bypassable** | Accepted | Stated, not defended against. §11.5 |
| R8 | ~~**App has never run on physical hardware**~~ — **resolved for iOS.** It has since run on a cabled iPhone 17, including a real-site save and a soak. **Still open for Android**, where no physical device has been available, and for the accessibility passes | Medium, down from High | ARCHITECTURE.md §10; FOREGROUND_MULTITASKING_PLAN.md §6 |
| R9 | **Support/legal/privacy URLs do not exist** (STORE_PACKAGE.md §8.5) | High | Blocks submission regardless of monetization |
| R10 | Play's treatment of **developer tips** | Open | **[Unverified]** — verify before Stage 2 on Android |
| R11 | Exact **TRY price points** on both stores | Open | **[Unverified]** — read from the live consoles |
| R12 | **StoreKit 2 first-launch sync caveat** (§4.6) | Open | **[Likely]**, sourced from forums/vendor engineering posts rather than a normative Apple sentence; verify with a real device restore during implementation |
| R13 | Whether the **free tier converts at all** — a genuinely complete free reader may simply be enough for most people | Medium | This is the honest cost of not shipping a crippled free tier, and it is accepted deliberately |
| R14 | **Türkiye tax treatment** of store proceeds for an individual developer | Open | Outside this document; requires an accountant before first payout |

---

## 17. Decisions requiring product-owner approval

| ID | Decision | Recommendation |
|---|---|---|
| **D-1** | **Model:** one-time Pro unlock vs subscription vs paid app | **One-time unlock** (§11). Alternatives A/B/C in §12 |
| **D-2** | **Price:** USD 9.99 base | **Approve USD 9.99**; approve manual Türkiye pricing at roughly the local equivalent of USD 2–4 (§9.4) |
| **D-3** | **Should free multi-entry runs carry a lower visible cap** (e.g. 3 per run) than Pro? | **No cap** — keep multi-entry free and bounded as today (§8.2). A cap is defensible but moves the paywall onto the surface §8.2 argues to keep clear |
| **D-4** | **On entitlement loss, do existing saved rules keep applying?** | **Yes, keep them applying**; only creation/management returns to Pro (§13.2) |
| **D-5** | **Sequencing:** monetize at first release, or ship free first and monetize in the following release? **Now also:** should a PRO-badged locked control be visible at all before billing exists and before the content-rights work is done? | **Ship free first** (§14 Stage 0). This is a real scope decision, not a technicality. **Still open, and now partly overtaken** — a Pro boundary ships today with no purchase behind it |
| **D-6** | **Backup/export** — CLAUDE.md forbids export to Photos/Gallery/Downloads/shared storage. Amend? | **Defer to Stage 3.** Needs a rule change and a design, not a pricing decision (§8.3, §14) |
| **D-7** | **New dependency** (`in_app_purchase`) | Required for D-1 unless D-1 chooses the paid-app alternative. Approval needed per CLAUDE.md (§15.1) |
| **D-8** | **Family Sharing** on the non-consumable | **Enable** (§11.6) |
| **D-9** | ~~**Update checking as the headline Pro feature**~~ | ~~Recommended **yes** on 2026-08-03.~~ **DECIDED — no. Closed.** Update checking is **Free** at both granularities; the Pro capability is **foreground multitasking**. The 2026-08-03 recommendation is superseded and is not to be revived as written. Recorded in FOREGROUND_MULTITASKING.md §10.0, ARCHITECTURE.md §9 and CLAUDE.md |
| **D-10** | **Store copy changes** to STORE_PACKAGE.md §2/§3/§4/§6 for IAP disclosure | Required before submission (§15.6) |

---

## 18. Sources

All retrieved **2026-08-03**.

**A note on the citation form.** `test/repository_cleanliness_test.dart` fails the
build if any file in this repository — documentation included — names a
third-party hostname outside its allowlist. That guard is correct and this
document complies with it rather than amending it. So: Apple's and Google's own
developer and support pages, the App Store, GitHub and pub.dev are cited with full
URLs; **every other source is cited by publisher, title and date, without a URL**.
Nothing was left out — each one is findable from the details given, and where an
allowed official page carries the same fact, that page is cited alongside.

### Apple — official

| Source | URL |
|---|---|
| App Review Guidelines — 3.1.1 In-App Purchase, 3.1.1(a) Link to Other Purchase Methods, 3.1.2 Subscriptions, 3.1.3 Other Purchase Methods, 4.8 Login Services, 5.1.1(v) Account Sign-In, 2.3.2 | https://developer.apple.com/app-store/review/guidelines/ |
| Auto-renewable Subscriptions — offers, trials, billing retry, grace period, Family Sharing, 70%/85% and Small Business Program interaction | https://developer.apple.com/app-store/subscriptions/ |
| App Store Small Business Program — 15%, USD 1M threshold, enrolment timing | https://developer.apple.com/app-store/small-business-program/ |
| App Store Connect Help — Set a price (800+100 price points, base storefront, automatic regional pricing, manual management) | https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/ |
| App privacy details — "processed only on device is not 'collected'", the Purchases data type | https://developer.apple.com/app-store/app-privacy-details/ |
| Apple Developer Program — USD 99/year | https://developer.apple.com/programs/ |
| Newsroom (2022-12-06) — 900 price points, lowest USD 0.29, up to USD 10,000 (the system still in use) | https://www.apple.com/newsroom/2022/12/apple-announces-biggest-upgrade-to-app-store-pricing-adding-700-new-price-points/ |
| Developer News (2026-04-27) — monthly subscriptions with a 12-month commitment; unavailable in the US and Singapore | https://developer.apple.com/news/?id=agq42lxe |

### Google — official

| Source | URL |
|---|---|
| Play Console Help — Service fees (15% first USD 1M; 15% subscriptions; the 2026-06-30 US/EEA/UK split) | https://support.google.com/googleplay/android-developer/answer/112622 |
| Play Payments policy — when Play's billing system is required; examples; exceptions | https://support.google.com/googleplay/android-developer/answer/9858738 |
| Play Billing — subscriptions: base plans, offers, trials, grace period, account hold, resubscribe, optional obfuscated account IDs | https://developer.android.com/google/play/billing/subscriptions |
| Play Console Help — Set up your app's prices (local currency conversion, tax, sub-dollar markets) | https://support.google.com/googleplay/android-developer/answer/6334373 |
| Play Console Help — Account deletion requirement (in-app + web link; 2023-12-07 / 2024-05-31 deadlines) | https://support.google.com/googleplay/android-developer/answer/13327111 |
| Play Console Help — USD 25 one-time registration fee; identity and device verification | https://support.google.com/googleplay/android-developer/answer/6112435 |
| **Android Developers Blog, "Expanded billing choice and lower fees on Google Play", 2026-06-24** — the announcement of the fee separation: 10% service fee, 5% billing fee, new vs existing installs. *(No URL: Google's developer blog host is outside the guard's allowlist. The same figures appear on the Service fees Console page cited above, which is allowed — prefer that page as the citable source.)* | — |

### Competitors — primary sources

| Source | URL |
|---|---|
| GoodLinks — App Store listing: USD 9.99, Annual Feature Upgrade USD 4.99, tips USD 0.99–19.99 | https://apps.apple.com/us/app/id1474335294 |
| Panels — App Store listing: Panels+ Monthly USD 1.49, Yearly USD 14.99, Panels 3 USD 19.99, Panels 3 Upgrade USD 9.99; listing last updated 2024-07-26 | https://apps.apple.com/us/app/id1236567663 |
| Mihon — free, open source, Android | https://github.com/mihonapp/mihon |
| Aidoku — free, open source, iOS (beta) | https://github.com/Aidoku/Aidoku |
| **Panels — the developer's own product website**: free tier, subscription vs one-off major-version unlock, no account required | *(no URL — outside the allowlist)* |
| **Instapaper — the service's own Premium page**: USD 5.99/mo, USD 59.99/yr, account required, premium feature list | *(no URL — outside the allowlist)* |
| **Obsidian — the developer's own pricing page**: free for personal use with no sign-up, Sync USD 4/mo annual or USD 5/mo monthly, Publish USD 8–10/mo, commercial licence USD 50/user/yr | *(no URL — outside the allowlist)* |

### Secondary sources — used only where marked, and flagged in-line

| Source | Used for |
|---|---|
| Flutter `in_app_purchase` package — https://pub.dev/packages/in_app_purchase | Version 3.3.0, verified `flutter.dev` publisher, platform support, no server requirement |
| Apple Developer Forums — https://developer.apple.com/forums/thread/706450 | StoreKit 2 `currentEntitlements` without an internet connection — **[Likely]** |
| **RevenueCat engineering blog, "Introducing Offline Entitlements"** *(no URL — outside the allowlist)* | The StoreKit 2 local transaction cache and the first-launch sync caveat — **[Likely]**, vendor engineering write-up rather than normative Apple documentation |
| **Press reporting on Pocket's shutdown**: CyberInsider, "Mozilla to Shut Down Pocket Service in July, to Allow Exports Until October" (2025-05); 9to5Mac, "Mozilla announces shutdown of Pocket" (2025-05-22) *(no URLs — outside the allowlist)* | 2025-07-08 service end, 2025-10-08 data deletion, prorated subscriber refunds |
| **Press reporting on the Epic injunction**: MacRumors, "Apple Wins Ability to Charge Fees on External Payment Links as Appeals Court Modifies Epic Injunction" (2025-12-11); TechCrunch, "Apple says Epic lawsuit shouldn't reshape App Store rules for all developers" (2026-05-22) *(no URLs — outside the allowlist)* | US external-link status, appeals-court modification, Supreme Court timing — **[Likely]**; procedural detail not verified against court documents |
| **Turkish technology press**: Teknoblog, "App Store Türkiye fiyatlarına zam yolda"; DonanımHaber, "Apple, App Store fiyatlarını Türkiye'de güncelliyor" *(no URLs — outside the allowlist)* | App Store Türkiye repricings; entry tier ₺10.99 → ₺16.99 — **[Unverified]** against App Store Connect |
| **Review articles on read-it-later pricing** *(no URLs — outside the allowlist)* | Readwise Reader pricing (USD 9.99/mo billed annually, USD 12.99/mo monthly) — **[Unverified]** against Readwise's own site |
| **Third-party app-pricing trackers** *(no URLs — outside the allowlist)* | Google Play Türkiye minimum near USD 0.21 — **[Unverified]**; read the live range in Play Console |

---

## 19. Related documents

- [ARCHITECTURE.md](./ARCHITECTURE.md) — the as-built model; §10 is the built-vs-deferred status table this plan is gated on
- [STORE_POLICY_MAP.md](./STORE_POLICY_MAP.md) — the policy positions §8.2 is written to protect
- [STORE_PACKAGE.md](./STORE_PACKAGE.md) — listing copy and console checklists that §15.6 would amend
- [PRIVACY.md](./PRIVACY.md) — the claims §4.12 confirms remain true
- [TERMINOLOGY.md](./TERMINOLOGY.md) — Collection / Entry, and the label rules paywall copy must follow
