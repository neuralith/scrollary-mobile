# Privacy audit

> Every data flow, and the exact claims the listing is allowed to make.
> Written to be checkable: each row names where in the code the behaviour lives.
>
> **This document describes the app as built: single-device, accountless, with
> no server.** Every claim below is accurate for the current code and must not
> be edited to describe unbuilt behaviour.
>
> **It must be rewritten before the first release.** The V2 direction adds an
> *optional* account and cross-device sync of library metadata and reading state
> ([DECISIONS.md](./DECISIONS.md) V2-D3, V2-D8). For a signed-in user, §2's
> "nothing goes to the developer" and §3's permitted claims *"No account."* and
> *"The app has no server and receives nothing from you"* become false and must
> be **re-scoped, not deleted** — they stay true for anonymous use, which stays
> a permanently supported configuration. Downloaded content is never uploaded
> under any circumstances ([V2_SYNC.md](./V2_SYNC.md) §8.2). The full list of
> what V2 adds to the release obligations is [V2_SYNC.md](./V2_SYNC.md) §14, and
> the task is 7.5 in [V2_ROADMAP.md](./V2_ROADMAP.md).

## 1. What is stored locally

| Data | Where | Deleted by |
|---|---|---|
| Collections, entries, reading position, read state | `entries` / `collections` in the app-private SQLite database | Collection detail → ⋯ → *Delete permanently*, per collection; the internal-build full reset, for everything |
| Saved page bytes (text + images) | `webread/library/…` in app-private storage, excluded from device backup | Remove offline files (per entry, per collection, all finished), which keeps the rows; *Delete permanently*, which removes the collection's files and its rows together |
| Browsing history (manual navigation only) | `browsing_history`, retained 90 days or 5,000 rows | Browser → Full history → Clear |
| Saved sites | `saved_sites` — empty until the user adds one | per-row removal |
| Favicons | `favicon_cache`, ≤ 24 KB each, purely derived | Settings → Browser data |
| Cookies and site storage | the WebView's own store | Settings → Browser data → Clear website data |
| User page hints | `user_page_hints` — empty until the user teaches one | per-row removal |
| Preferences | `settings` — including the "Keep working while I read" preference | the internal-build full reset |

The storage folder is still named `webread`, from the app's working name. It is
an app-private path and renaming it would strand every library already on a
device, so it stays.

**"The internal-build full reset"** is the destructive developer screen, gated
by `kInternalBuild` (`kDebugMode || bool.fromEnvironment('SCROLLARY_INTERNAL_BUILD')`).
A Store build passes no define, so the constant folds to `false` and the screen,
its route and its entry point are tree-shaken out: **a user's build has no full
reset.** Per-collection deletion, offline-file removal, history clearing and
website-data clearing are the deletion routes that ship, and none of them needs
an account. This is why the Play answer in STORE_PACKAGE.md §8.2 rests on those
and not on the reset.

When the content-rights disclosure is built (STORE_PACKAGE.md §6.1), its
acknowledgement — a local, versioned flag — will live in `settings` too. It does
not exist yet, and this table will gain a row when it does.

## 2. What leaves the device

**Nothing goes to the developer.** There is no account, no server, no analytics
SDK, no crash-reporting SDK and no advertising SDK.

Outbound requests exist for exactly two reasons, both to hosts the user
navigated to themselves:

1. The WebView loads the page the user opened.
2. `AssetFetcher` fetches that page's images, with the WebView's User-Agent,
   cookies and `Referer`, so the request is indistinguishable from the browsing
   the user was already doing.

| Question | Answer |
|---|---|
| Are browsing URLs sent to the developer? | No |
| Is saved content uploaded anywhere? | No |
| Do analytics receive URLs, titles, domains or content? | There are no analytics |
| Does crash reporting include page data? | There is no crash reporting |
| Is there optional sync? | No |
| How are cookies handled? | In the WebView's own store, cleared by Clear website data |

## 3. Claims the listing may and may not make

**May:** "Your library is stored on your device." · "No account." · "No
analytics, no advertising." · "The app has no server and receives nothing from
you."

**May not:** "No tracking." · "Completely private." · "Everything stays on
device." — the embedded browser necessarily contacts the sites the user visits,
and those sites may set cookies and track normally. Claiming otherwise would be
false.

## 4. Permissions

Internet only. Explicitly **not** requested: Photos, shared storage, all-files
access, contacts, location, installed-app queries, microphone, camera. Saved
images go to app-private storage; there is no export to Photos, Gallery or
Downloads.

## 5. Remaining legal work

- [ ] Publish a privacy policy at a stable URL matching this document
- [ ] Publish Terms of use and a content-rights page
- [ ] Legal review of the offline-copy position (see `STORE_POLICY_MAP.md` R3)
