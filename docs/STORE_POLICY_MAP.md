# Store policy map

> Official Apple App Store Review Guidelines and Google Play Developer Program
> Policy areas that bear on this app, the risk each one creates, and what was
> done about it — in code, in the UI, and in the store listing.
>
> Reviewed against the guidelines as published July 2026. Sources:
> [Apple App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) ·
> [Play: Intellectual Property](https://support.google.com/googleplay/android-developer/answer/9888072) ·
> [Play: Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646) ·
> [Play: Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) ·
> [Play: Content ratings](https://support.google.com/googleplay/android-developer/answer/9898843)
>
> **This document does not claim the app will be approved, and does not claim
> legal compliance.** A disclaimer is not a defence, and neither is a mitigation
> table. Review outcomes are the reviewers' to decide, and several rows below end
> in an unresolved question that needs a lawyer rather than an engineer.

---

## 0. The one-paragraph summary

The app is an embedded browser plus a personal offline reading library. The
riskiest thing it does is **store a copy of a third-party page for later reading**
— which is legal for some content and not for other content, and which no
technical measure can tell apart. Every mitigation below follows from accepting
that: the app defaults to one page, never runs unattended beyond an explicit
ceiling, stops rather than pushing past any access control, positions itself
honestly, and puts the rights question in front of the user before the first
external save instead of burying it.

---

## 1. Intellectual property

### Apple 5.2.1 (Generally) · 5.2.2 (Third-Party Sites/Services) · Play IP policy

> Apple 5.2.2: *"If your app uses, accesses, monetizes access to, or displays
> content from a third-party service, ensure that you are specifically permitted
> to do so under the service's terms of use. Authorization must be provided upon
> request."*
>
> Play: *"We don't allow apps that … encourage or induce infringement of
> intellectual property rights"*, naming *"streaming apps that allow users to
> download a local copy of copyrighted content without authorization."*

**Risk — high, and irreducible.** The app can store a local copy of any page the
user can open. Nothing in it verifies whether that copy is permitted.

| Mitigation | Where |
|---|---|
| **No provider catalogue.** No hostname, selector, site list or "supported sites" exists in the binary. `test/repository_cleanliness_test.dart` fails the build if one appears. The single allowance is the restricted-site list below, which only ever *refuses*: nothing on it makes a site work. | `test/repository_cleanliness_test.dart` |
| **No site-specific behaviour.** Continuation detection uses only `rel=next`/`rel=prev`, semantic anchor text, pagination `aria-label`, `<article>`/`<time datetime>`, JSON-LD dates and measured layout. | `lib/save/content_detection.dart`, `lib/save/next_page.dart` |
| **User-created hints are local preferences, not a catalogue.** `user_page_hints` starts empty, is written only when a person taps an element, and never syncs. Asserted in tests. | `lib/storage/database.dart`, `lib/save/page_hint.dart` |
| **Every save is user-initiated.** There is no background save, no scheduler and no queue that starts itself; queued work waits for an explicit *Start*. | `lib/queue/task_queue.dart` |
| **Content-rights disclosure before the first external save**, versioned, re-readable from Settings. **Not built yet** — wording fixed, surface deferred (§8). | §8 below |
| **Restricted-site capture policy.** A static list of commercial content services the app will not save from — subscription video, hosted commercial video, music, audiobooks, ebook stores and readers, licensed serialised reading, and official publisher reading services. Browsing them is untouched; only capture is withheld. See below. | `lib/save/capture_policy.dart` |
| **Store listing avoids inducement wording** — no "download", "downloader", "unlimited", "any website", "bulk" — and says plainly that saving is not offered on some commercial services. | `docs/STORE_PACKAGE.md` |
| **Store assets use only original content.** | `docs/STORE_PACKAGE.md` §demo |

**Unresolved (legal, not engineering).** Whether a personal offline copy made
through an embedded browser is permitted differs by jurisdiction and by each
site's terms. The app cannot determine this and does not claim to. A lawyer
should review the Terms and the content-rights wording before submission.

#### The restricted-site capture policy

The mitigations above are all about *how much* and *how deliberately* the app
saves. This one is about *where it will not save at all*.

`lib/save/capture_policy.dart` holds a static list of commercial content
services. On a host it names, the save control is **absent** — not disabled, not
explained, not preceded by a warning — and the address stays fully browsable:
back, forward, reload, the address bar and sign-in all work normally. The user is
not told off for visiting; they are simply not offered a save.

- **Two rule kinds.** A *domain* rule covers the apex and every subdomain. An
  *exact host* rule covers one host. Matching is on the parsed `Uri.host` only
  — lowercased, trailing dots stripped, ports irrelevant, `http` and `https`
  identical — with no substring matching anywhere, so `notyoutube.com`,
  `fakeamazon.com` and `youtube.com.example.org` do not match, and a restricted
  name inside a path or query parameter is never examined.
- **Amazon's retail domains are blocked whole**, deliberately. Reading, video,
  music and audiobook services are served from paths and subdomains of the retail
  domains, and no static rule can separate a product page from a reader without
  inspecting the page — which this policy does not do.
- **Apple and Google are restricted only through selected content-service
  hosts.** `tv.apple.com`, `music.apple.com`, `books.apple.com`,
  `podcasts.apple.com`, `itunes.apple.com`, `play.google.com`,
  `books.google.com`. The parent domains and their unrelated subdomains
  (`developer.apple.com`, `support.apple.com`, `developers.google.com`) are
  untouched. The same reasoning applies to publisher reading services hosted
  under broad corporate parents, which are named individually.
- **No per-page judgement.** The app does not detect DRM, read Terms of Service,
  fetch remote configuration, or try to work out whether a page is paid or
  public. **Conservative overblocking is accepted**: a marketing page, a store
  listing or a support article on one of these hosts is refused with everything
  else.
- **Enforced below the UI.** Hiding a button is not a control. Direct start, Add
  to Queue, the queue pump, resume, retry, multi-entry continuation, top-level
  redirects mid-run, update checking, discovered-entry recording, and the save
  engine before it probes *and* again before it commits each ask the policy
  independently. A queued row from before a host joined the list is settled as a
  terminal failure rather than run. `test/capture_restriction_test.dart` proves
  each of these with the UI out of the picture.
- **It governs pages, not the assets inside them.** The policy answers "may this
  app capture this page". An image `src`, a responsive candidate, a CSS
  background, a document's inline image, the CDN delivering any of them, and an
  asset request's own redirects are **not** capture sources and are not tested
  against the list. Ordinary sites deliver their pictures through CDNs owned by
  large commercial platforms, and refusing those marked perfectly permitted
  entries as incomplete for a reason unrelated to them. A **top-level** redirect
  into a restricted site still ends the run; an **asset** redirect onto a
  restricted CDN does not. The page is judged before a staging directory is
  opened, so a restricted page never reaches a download at all
  (`test/asset_host_policy_test.dart`).
- **Independent of the media rules.** 5.2.3 above still applies everywhere and is
  enforced separately, at the byte level: the asset fetcher accepts image bytes
  only, verified by magic number, so audio and video are refused from **any**
  host, restricted or not, and unsupported media is never reclassified in order
  to continue. Narrowing the restricted-site policy to pages did not touch that
  allow-list. This is an additional layer, not a replacement.
- **Nothing already saved is affected.** The policy prevents new capture,
  re-capture, retry, resume, continuation and update discovery. It never deletes
  or modifies a collection, an entry, a downloaded file, reading progress,
  read state or history.
- **The user-facing sentence is neutral**: *"Saving isn't available on this
  site."* It states what the app does. It never characterises what the user was
  trying to do, and makes no accusation about copyright.

**The list is static, incomplete by construction, and manually maintained.** It
is a risk-reduction measure, **not a claim of copyright or legal compliance**,
and a host's absence from it says nothing about whether saving a given page is
permitted. There is no user override and no developer bypass in a release build.

`test/repository_cleanliness_test.dart` allows this one file to name hosts, and
fails the build if the constants are declared anywhere else — one authority, or
the UI and the engine drift apart.

### Apple 5.2.3 (Audio/Video Downloading)

> *"Apps should not facilitate illegal file sharing or include the ability to
> save, convert, or download media from third-party sources … without explicit
> authorization from those sources."*

**Risk — high if unaddressed; this guideline removes whole apps.**

**Mitigation: the capability is absent, not discouraged.** The asset fetcher
accepts image bytes only (verified by magic number, not by `Content-Type`, which
servers misreport). Media elements are *measured* by the page probe — a count,
the largest player's laid-out area, and whether it sits in the readable region —
so a page that is primarily a video can be recognised and refused. **No media
URL is read, returned or stored anywhere in the codebase.**

A page classified `videoDominant` is handled explicitly rather than silently:
the save sheet says video is not saved, and when the page carries no readable
text the save is **refused** rather than falling back to collecting its
thumbnails and calling that an offline copy.

- `lib/browser/page_data.dart` → `PageMediaSignals` (geometry only, no URLs)
- `lib/save/content_detection.dart` → `videoDominant`, with three guards so an
  incidental player never triggers it
- `lib/save/capture_mode.dart` → `CaptureMode` has **no video value**; the save
  sheet is built from that enum, so no video option can appear
- `lib/save/asset_fetcher.dart` → image MIME allow-list
- `lib/save/save_run.dart` → refuses a video page with nothing readable

**Tests.** `test/content_detection_test.dart` covers video-dominant
classification, every incidental-video case that must *not* trigger it, and the
refusal. `integration_test/text_capture_test.dart` proves the same against a
real `<video>` element in a live WebView, including that the page's sidebar
thumbnails are not swept up instead. The image-only MIME allow-list stays
verified by `mime_extension_test.dart`.

**That gap is now closed.** It previously read: *"there is still no test that
asserts a media byte stream offered to `AssetFetcher` is rejected — the
allow-list makes it unreachable by construction, but that is an argument rather
than an assertion."*

`test/asset_host_policy_test.dart` now feeds real MP4, MP3 and WAV byte streams
to the fetcher and asserts each returns `AssetStatus.failed` with *not a
recognised image format* — from an ordinary host, from a restricted host, and
served under a lying `.png` / `.jpg` extension, which is the case
`Content-Type` and filename checks both miss. It also asserts the sniffer
itself answers null for all three while still recognising PNG. The argument is
now an assertion, and it covers audio as well as video.

---

## 2. Minimum functionality and repackaged websites

### Apple 4.2 / 4.2.2 · Play "Spam and Minimum Functionality"

> Apple 4.2: *"Your app should include features, content, and UI that elevate it
> beyond a repackaged website."*
> Apple 4.2.2: *"Other than catalogs, apps shouldn't primarily be marketing
> materials, advertisements, web clippings, content aggregators, or a collection
> of links."*

**Risk — moderate.** An app whose first tab is a WebView invites this rejection.

**Mitigation — native value that a WebView cannot provide**, all of it on screen
without hidden gestures:

native library · collections and standalone entries · offline reader with page
geometry restored from stored dimensions · durable reading position and
Continue Reading · a visible, cancellable, retryable work queue · search ·
archive · per-entry and bulk offline-file removal with undo · permanent
collection deletion, confirmed and complete · storage metering
with per-collection breakdown · source attribution and *Open original page* ·
user-controlled save scope · native loading, empty, offline and error states.

The Library — not the Browser — is the launch tab, so the first screen a reviewer
sees is the native one.

### Apple 2.5.6 (web browsing must use WebKit)

Satisfied: `flutter_inappwebview` wraps `WKWebView` on iOS. No alternative engine
entitlement is requested.

---

## 3. Device and network abuse

### Play "Device and Network Abuse"

> *"Apps containing a webview with added JavaScript Interface that loads
> untrusted web content or unverified URLs obtained from untrusted sources"* are
> prohibited.

**Risk — material, and easy to miss.** This app *does* add a JavaScript handler
to a WebView that loads arbitrary user-chosen pages. That is the literal shape
the policy describes.

**Mitigation — the bridge exposes no capability worth attacking:**

| Property | Where |
|---|---|
| The bridge is **read-only measurement plus scrolling**. It reports layout metrics, image metadata, links and structural signals. It exposes no filesystem, no database, no network, no native API. | `lib/browser/bridge_script.dart` |
| It **never evaluates page-supplied code**. No `eval`, no `Function()`, no dynamic import of page content. | same |
| Page-supplied strings cross into Dart as **data only** — parsed into typed models with defaults, never interpreted. | `lib/browser/page_data.dart` |
| URLs the app navigates to are **validated before use**: scheme allow-list, origin check, loop check. During a run the WebView is navigation-locked and popups are disabled. | `lib/save/stop_conditions.dart`, `lib/save/next_page.dart` |
| No code is downloaded or executed from any source. No self-update mechanism. | — |

**Action for submission:** state this explicitly in the Play data-safety /
policy declarations and in the App Review notes, because a reviewer scanning for
"WebView + JavaScript interface" will otherwise flag it.

---

## 4. Deceptive behaviour and accurate metadata

### Apple 2.3, 2.3.1, 2.3.3, 2.3.7 · Play "Deceptive Behavior"

> Apple 2.3.1(a): *"Don't include any hidden, dormant, or undocumented features …
> All new features … must be described with specificity in the Notes for Review."*
> Play: *"All metadata, including store listing, screenshots, and title, must
> precisely reflect the app's functionality."*

**Mitigation:**

- The listing describes a read-later and offline reading tool, which is what it
  is. No claim of universal site support, no claim of unlimited saving.
- Screenshots show the app in use (Library, Collection, Reader, Queue, Storage),
  not a splash or a login — Apple 2.3.3.
- Reviewer notes describe the save flow, the bounds, the stopping conditions and
  where every control lives — Apple 2.3.1(a). See `docs/STORE_PACKAGE.md`.
- No hidden features in a **submitted** build, and the mechanism is a
  compile-time constant rather than a runtime check. The destructive developer
  reset and the internal entitlement override are gated by `kInternalBuild` —
  `kDebugMode || bool.fromEnvironment('SCROLLARY_INTERNAL_BUILD')` — at the
  settings entry, the route registration and the screen itself. A build that
  passes no define folds that to `false`, and the tree-shaker removes the
  screen, the route and the override, so a Store build contains no reset and no
  way to reach one. **This holds only if the Store build passes no define**; it
  is a build-configuration obligation, not something the code can enforce on its
  own, and it belongs on the release checklist (§8.6).
- App name ≤ 30 characters — Apple 2.3.7.

---

## 5. Privacy

### Apple 5.1.1(i)–(iii) · Play Data safety

> Apple 5.1.1(iii): *"Apps should only request access to data relevant to the
> core functionality … and should only collect and use data that is required."*
> Play: *"'Collect' means transmitting data from your app off a user's device."*
> and *"User data … only processed locally on the user's device and not sent off
> device does not need to be disclosed."*

**Position: nothing is transmitted to the developer.** There is no account, no
analytics SDK, no crash-reporting SDK, no advertising SDK and no developer
server. The library, reading history, browsing history and saved pages are
on-device, in app-private storage.

Network requests are made only to hosts the user navigated to, for the page and
its images. See `docs/PRIVACY.md` for the per-flow audit and the exact
declaration values.

**Wording discipline:** the listing says *"Your library is stored on your
device"* and *"the app has no account and sends nothing to us"* — both literally
true. It does **not** say "no tracking", "completely private" or "everything
stays on device", because the embedded browser necessarily contacts the sites the
user visits, and those sites can set their own cookies.

**Permissions:** internet only. No Photos, no shared storage, no contacts, no
location, no installed-apps query, no all-files access. Saved images go to
app-private storage; there is no bulk export to Photos, Gallery or Downloads.

---

## 6. Age rating, target audience and unrestricted web access

### Apple 2.3.6 · Play Content ratings / Target audience

The app provides **unrestricted access to arbitrary URLs**. Both questionnaires
have to say so.

| Question | Answer to give | Why |
|---|---|---|
| Apple: "Unrestricted Web Access" | **Yes** | The user can enter any address. |
| Apple: expected age rating | **17+** | Unrestricted web access alone drives this on the current questionnaire. |
| Apple: Kids Category | **No** | |
| Play: IARC — "app allows unrestricted access to the internet" | **Yes** | Produces the *Unrestricted Internet* interactive element. |
| Play: Target audience | **18+ only** | Do not select any child age band. |
| Play: "Appeals to children" | **No** | Branding and copy are deliberately adult and utilitarian. |
| Play: user-generated content | **No** | There is no sharing, no social feature, no publishing. Content is fetched by the user for the user. |

Apple 1.2 (user-generated content: filtering, reporting, blocking, published
contact) does **not** apply: nothing a user saves is visible to anyone else.
Apple 4.7 (mini apps) does not apply: the app hosts no third-party software and
exposes no native API to page content.

**Must be confirmed manually in the consoles** — these cannot be set from the
repository. See `docs/STORE_PACKAGE.md` §checklists.

---

## 7. Access controls: the app stops, it never works around

### Apple 5.2.2, Play IP policy, and every platform's anti-circumvention stance

There is **no** bypass of authentication, subscriptions, paywalls, DRM, CAPTCHAs,
robots restrictions, rate limits or anti-bot measures anywhere in the codebase.
Automatic continuation *detects and stops*, names the condition, and tells the
user. There is no retry-with-different-headers, no alternate-URL attempt, no
cookie manipulation and no waiting-out of a rate limit.

`lib/save/stop_conditions.dart` is the whole surface:

| Condition | Detected by | `StopReason` |
|---|---|---|
| Sign-in required | password input, sign-in form, or a near-empty page saying so | `authenticationRequired` |
| Paywall | `isAccessibleForFree=False` / `content_tier=locked` / `data-paywall`, or a near-empty page saying so | `paywallDetected` |
| Human verification | reCAPTCHA / hCaptcha / Turnstile iframe or `data-sitekey` | `captchaDetected` |
| Access denied | near-empty page saying so | `accessDenied` |
| Rate limited | near-empty page saying so | `rateLimited` |
| Different origin | scheme+host+port comparison against the run's start | `crossOrigin` |
| Repeated address | normalised URL already walked | `repeatedUrl` |
| Loop behind changing URLs | `rel=canonical` already seen | `navigationLoop` |
| Layout changed | image-heavy → text, or content disappeared | `structureChanged` |
| Unclear next page | confidence gate in the next-page chain | `lowConfidence` |
| User's ceiling | `SaveLimits.maxEntries` / `maxBytes` | `userLimitReached` / `storageLimitReached` |
| **This app's own restricted-site policy** | a static host list (§1) — not something the site did | `captureRestrictedForSite` |

Three design points matter for review:

1. **Phrase hints never fire alone.** "Subscribe to continue" in a footer is not
   a paywall. A phrase counts only alongside a structural signal or a near-empty
   document — which is what a real interstitial looks like.
2. **"Finished" and "the site stopped us" are different outcomes**, stored in a
   column (`save_runs.stop_reason`), not inferred from a log line.
3. **`captureRestrictedForSite` is the app declining, not the site refusing.**
   It is deliberately excluded from `StopReason.isAccessGate`: reporting it as
   an access gate would claim something about the site that is not true, and the
   sentence the user reads says only that saving is not available here.

---

## 8. First-use and contextual content-rights disclosure

**Exact wording** is in `docs/STORE_PACKAGE.md` §wording, and is the single
source both the app and the listing draw from.

Requirements met by design:

- Shown **before the first external save**, not at launch (a wall of legal text
  on first run is a dark pattern of its own).
- Acknowledgement is stored **locally**, with a **version**, so a material change
  can ask again without nagging on every save.
- Re-readable any time from **Settings → Content rights**.
- It does **not** claim the app verified anyone's rights.
- Normal reading never shows it again.
- A smaller **contextual notice** appears before the first multi-entry save from a
  domain, naming the domain, the scope, the ceiling and how to cancel.

**Status:** wording finalised; the two disclosure surfaces are specified and not
yet built. Listed in the final report's remaining-blockers section.

---

## 9. App completeness and review access

### Apple 2.1

> *"…include demo account info (and turn on your back-end service!) if your app
> includes a login."*

There is no login and no back end, so no demo account is needed. What a reviewer
*does* need is content to save. Because the app ships no site list, the reviewer
notes point at a **developer-owned demo site** with original content covering
every content shape. Requirements are in `docs/DEMO_CONTENT.md`; hosting it is an
external task tracked in the final report.

---

## 10. Residual risk register

| # | Risk | Severity | Owner |
|---|---|---|---|
| R1 | A reviewer reads "save a web page for offline reading" as a downloader regardless of wording | High | Product — mitigated by scope defaults, bounds, disclosures and reviewer notes; cannot be eliminated |
| R2 | Play flags WebView + JavaScript interface under Device and Network Abuse | Medium | Declare explicitly (§3); bridge is read-only |
| R3 | Copyright legality of a personal offline copy varies by jurisdiction | High | **Legal review required** |
| R4 | A site's terms forbid automated requests; the app cannot read terms | Medium | Contextual notice names the risk; ceilings and serial navigation limit load |
| R5 | Brand name availability and trademark conflict unverified | Medium | **Trademark search required** before submission |
| R6 | Age-rating questionnaires can only be answered in the consoles | Low | Checklist in `docs/STORE_PACKAGE.md` |
| R7 | Demo site not hosted | Medium | External task |
| R8 | The URL bar's default search provider is hardcoded to one third-party service | Low | Product — a search engine is not a content provider and is never saved from, but making it user-selectable would remove the only third-party name in the build |
| R9 | The restricted-site list is static, hand-maintained and incomplete; a service not on it can still be saved from | Medium | Product — deliberate: dynamic remote configuration is out of scope (§1). Reduces risk, does not eliminate it, and is never described as compliance |
| R10 | Conservative overblocking refuses ordinary pages (marketing, support, editorial) on restricted hosts | Low | Product — accepted trade. Browsing is unaffected; the alternative is per-page judgement the app cannot make |
