# Demo content

> The app ships no site list, so a reviewer needs somewhere to test. That place
> must be **developer-owned and entirely original** — no third-party text, images
> or trademarks in screenshots, previews, onboarding, seed data or review
> instructions.

## 1. Required pages

Hosted at a developer-controlled origin. Tests and reviewer notes refer to it as
`<DEMO_BASE_URL>`; nothing in the app hardcodes it.

| Path | Shape it exercises | Must contain |
|---|---|---|
| `/article` | standalone entry, no continuation | `<article>`, `<time datetime>`, ~1,200 words of original prose, no `rel=next` |
| `/doc/page-1` … `/doc/page-12` | numbered finite pagination | `rel=next` + `rel=prev`, a `nav[aria-label="Pagination"]` listing 1–12 |
| `/posts` | reverse-chronological feed | ≥ 6 sibling `<article>`s each with `<time datetime>`, newest first |
| `/journal` | chronological feed | same, oldest first |
| `/gallery/1` … `/gallery/6` | image-dominant sequence | ≥ 4 original images ≥ 800 px wide, < 400 chars of prose, `rel=next` |
| `/chain/1` … | open-ended next-link chain | `rel=next` on every page, no pagination control, no declared end |
| `/gated` | the stop conditions | a demo `<form>` with `<input type="password">`, so a save visibly **stops** |
| `/media` | unsupported media | a `<video>` element, so the placeholder path is visible |

## 2. Content requirements

- All prose written for this purpose. No quotation of third-party work.
- All images original artwork or photographs the developer owns.
- No real person's name, likeness or private detail.
- No third-party logo, trademark or brand name anywhere.
- A visible footer on every page: "Demo content for Scrollary. Original work,
  free to save."

## 3. In-app support already present

- `tool/fixture/fixture_site.dart` serves an equivalent set in-process for the
  deterministic integration suites — no network, no third-party host. This is
  what every integration suite runs against today.
- **No test targets a hosted demo site yet.** The six `integration_test/live_*.dart`
  files that once named third-party sites were deleted (TERMINOLOGY.md §3) and
  nothing replaced them, so `--dart-define=DEMO_BASE_URL=…` is a convention this
  document is reserving, not a switch any current test reads. When the site
  exists, a suite for it takes its origin that way; no hostname is ever compiled
  into the app or its tests.
- For the cases that need a *real* page rather than a demo one,
  `integration_test/device_matrix_test.dart` takes `LIVE_ENTRY_A` / `LIVE_ENTRY_B`
  at run time and skips those scenarios when they are absent.

## 4. Not blocking the implementation

Hosting is an external task. Everything in the app works against the in-process
fixture; the hosted site is needed for store screenshots and reviewer testing.
