# Architecture

> **The as-built product and data model — what the code does today, and nothing
> else.** This document's value is that it can be trusted about the present, so
> nothing proposed belongs in it.
>
> Terminology is defined in [TERMINOLOGY.md](./TERMINOLOGY.md); the product
> definition in [PRODUCT.md](./PRODUCT.md); store positioning in
> [STORE_PACKAGE.md](./STORE_PACKAGE.md); policy reasoning in
> [STORE_POLICY_MAP.md](./STORE_POLICY_MAP.md); data flows in
> [PRIVACY.md](./PRIVACY.md).
>
> **V2 is the running app; this document is the historical record of the V1
> build it replaced.** The V1 library screens, save queue, save run and update
> checker described below are retired (V2_ROADMAP.md §10); the capture engine,
> file store, readers and browser guards were ported verbatim and still apply. Scrollary is evolving into a cross-platform reading library in which
> an Entry belongs to the library because the user wants to read it, not
> because it has been downloaded, and in which library state can follow the
> user across their own devices. The domain, persistence, recognition, capture
> and sync work for that is built and merged — see
> [V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) and
> [V2_ROADMAP.md](./V2_ROADMAP.md) for what exists and its current status —
> decided in [DECISIONS.md](./DECISIONS.md). That composition **has since
> merged: the V2 screens are the running app**, and this document is the
> historical record of the V1 build they replaced. Read it for the reasoning
> behind ported internals — render guards, image enumeration, the decode
> budget, FileStore, manifests, detection, extraction, stop conditions — and
> never as a description of what the app does today. §1 below describes a
> library organised around what has been downloaded, which V2 deliberately
> undid: [V2_ARCHITECTURE.md §7](./V2_ARCHITECTURE.md) itemises every place
> that was true and what it became.

## 1. What the app is

A general-purpose personal reading tool: an embedded browser, a native library,
and an offline reader. It lets a user save web pages they are legally permitted
to keep, organise them, and read them offline.

It is **not** a bulk fetcher, an automated harvester, a site archiver, a client
for particular websites, or a tool for getting past any access control. It ships no
site list and no site-specific behaviour.

It ships one list of hosts, and it is a list of hosts it **refuses** to save
from: a conservative restricted-site capture policy covering commercial content
services. Browsing them is untouched. See §7.1.

## 2. The model

Library → Collection → Entry → Page/Section. See TERMINOLOGY.md §1.

A **standalone entry** is a first-class library item: `entries.collection_id` is
nullable, no collection row is created for a single saved page, and the library
shelf is a union of collections and standalone entries
(`LibraryCollection` in `lib/features/library_screen.dart`).

The three ways content leaves again — archived, its offline files removed, or
deleted permanently — are three different operations with three different blast
radii. §8.2 is the authoritative account of which is which.

## 3. Content shape — three independent dimensions

`lib/library/content_shape.dart`. Kept independent because a page can be
image-dominant *and* part of a dated feed *and* ordered by publication date.

- **ContentKind**: standalonePage · article · datedPost · sequentialText ·
  imageDominant · **videoDominant** · paginatedDocument · longFormDocument ·
  unknownWebContent
- **SequenceKind**: none · explicitNextPrev · numberedPagination · openEndedNext ·
  chronologicalFeed · reverseChronologicalFeed · continuousPage · manualSelection
- **OrderingBasis**: explicitNumericIndex · publicationDate · detectedNextLink ·
  discoveryOrder · userDefinedManualOrder

Each carries a **ShapeConfidence**, and `low` is a real answer. Nothing assumes
numbering starts at 1, that a total is known, that a sequence increases, that
"next" means newer, that every entry belongs to a collection, or that a
collection has a final entry. `collections.known_entry_total` is nullable and
usually null.

### 3.1 Three separate questions

`ContentKind` is only one of three, and conflating any two of them is what
produced a library where every entry was an image list:

| Concept | Question | Where | Who decides |
|---|---|---|---|
| **ContentKind** | What is this *page*? | `library/content_shape.dart`, `entries.content_kind` | Detection; the user can correct the label |
| **CaptureMode** | What should the *save* produce? | `save/capture_mode.dart`, `save_runs.capture_mode`, `queue_tasks.capture_mode`, `entries.capture_mode` | The user, from what detection says is possible |
| **ArtifactFormat** | What does the stored *package* hold? | `storage/manifest.dart`, `entries.artifact_format`, `manifest.json` | The save that wrote it — a fact, not a claim |

**Only `ArtifactFormat` decides how an entry is read.** Correcting a label to
"article" changes what the library calls an image package and nothing else;
the reader still opens it as the image sequence it physically is. Reader mode
is *derived* from the artifact rather than stored, so the two cannot disagree.

`CaptureCapabilities` (`save/capture_mode.dart`) turns a probe into the set of
modes the engine can genuinely carry out on that page, the reason each
unavailable one is unavailable, and which to preselect. The save sheet is built
from it, so it can never offer a mode the engine would then refuse — and the
engine resolves against the *same* function on the settled page, so the two
cannot disagree.

Two fallbacks live in that one function rather than being duplicated:

- **Unclassifiable and not video** → the image attempt is offered. It is the
  only path with user assistance behind it, and a page nothing could classify
  used to be saved that way.
- **Video-dominant with nothing readable** → nothing is offered, the sheet's
  launch buttons are disabled, and the run refuses.

The engine resolves on the **settled** probe, after scrolling, not on the one
taken at page load: on the second entry of a multi-entry run a lazy image page
has barely loaded at that point, and deciding from it is how entry 2 would end
up stored in a different format from entry 1.

## 4. Detection — generic and domain-independent

`lib/save/content_detection.dart`. Signals used: `rel=next`/`rel=prev`,
`<article>`, `<main>`, `<time datetime>`, article metadata and JSON-LD dates,
pagination controls with a numeric range, measured prose length, measured image
area, document height, and elements the user pointed at. No hostname appears
anywhere in the file, and `test/repository_cleanliness_test.dart` fails the build
if one does.

Two rules are load-bearing: a number in a URL is not evidence of a structure, and
arriving from the web is not evidence of a page.

**Video** is classified, never captured. `videoDominant` requires all three of:
a player inside the readable region, occupying at least
`kVideoDominantViewportShare` (20%) of the measured viewport, on a page that is
neither prose nor a run of full-size images. A page that merely embeds a clip
stays what it is. `PageMediaSignals` carries geometry only — a count, an area
and an in-region flag — and deliberately no media URL of any kind.

**Text extraction** is split the same way detection is. `bridge_script.dart`
walks the readable region and reports every candidate block with flags
(`chrome`, `hidden`, tag, size); `save/document_extraction.dart` decides what
survives. The judgement half is pure Dart over literal fixtures, which is what
makes "what ends up in a user's saved copy" testable without a WebView.

Feed **direction** is measured from the dates on the page, never assumed —
getting it backwards saves the wrong end of a blog.

## 5. Save flow

**Built today:**

0. **What to save** and **how much to save** are separate choices, in one sheet.
   The capture modes are *Images only* · *Text only* · *Text and images*;
   unavailable ones stay on screen, disabled, with the reason beside them. The
   default comes from detection and every alternative is one tap away.
1. The default and preselected scope is **Save current page only**.
2. `SaveScope` is `currentPageOnly` | `selectedEntries` | `fixedCount`.
   `SaveLimits.forScope` is the only constructor and **cannot produce an
   unbounded run**: `maxEntries` is always a positive integer, clamped to
   `maxEntriesPerRun`.

   There is deliberately **no open-ended scope**. The app used to offer "until
   there is no next page", bounded by an internal ceiling the user never saw —
   and, because the sheet had no field to type one into, it passed a count of 1
   and saved exactly one entry. A typed number is the same safety guarantee
   stated plainly: the run stops where the person said it would, and every
   ceiling in the app is now one they chose and can see. A row persisted with
   the removed scope reads as `currentPageOnly`, the safest value, rather than
   saving more than was asked for.
3. `SaveRunController.start` takes `range` as a **required** parameter, so no
   caller can inherit a default about how much of someone else's site to touch.
4. Every multi-entry save is user-initiated, bounded, visible in the queue,
   cancellable, retryable, and survives a restart as *queued and unstarted* —
   the start authorisation is never persisted.
5. A collection can **remember** a capture mode (`collections.preferred_capture_mode`).
   It is a proposal, never an instruction: every page is re-measured and the
   preference is run through `CaptureCapabilities.resolve`, so a remembered
   mode that no longer applies falls back and the run says so in its log.
   A multi-entry run re-resolves per entry, because entry 7 may not be shaped
   like entry 1.
6. A text extraction that finds nothing is reported and walked past. It
   deliberately does **not** route into reader-area selection: that assistance
   hands back a container of images and cannot help a page with no prose.
7. **A new collection is named by the user.** Membership is decided once per
   run, on page 1, and `CollectionRepository.resolveCollection` is the only
   place a `collections` row is written. When it is about to write one it asks
   first, through `confirmNewName`, and the run holds in the panel slot the
   duplicate prompt uses (`features/collection_name_panel.dart`). The detected
   title is the *suggestion*, and it stays on `title` either way — what the
   source called this is a fact worth keeping. The answer lands on
   `user_title`, which is presentation-only and never part of matching, so a
   page titled "Part 24: The Quiet Year" can no longer name a whole collection
   after one of its parts. Declining writes nothing and stops the run through
   the ordinary `stop()` path, before the preflight and therefore before the
   first entry: no collection, no entry, no file, and everything already held
   untouched. Joining an existing collection and saving a standalone entry both
   return before the prompt, so neither is ever interrupted. A run with nothing
   able to answer — a test harness, a headless run — is built with
   `asksForCollectionName: false` and keeps the detected title; `main.dart` is
   the only place it is true.

**Deferred — modelled but not on screen.** The domain layer computes everything
the review step needs (`detectSequence` returns the kind, direction, known total
and confidence; `SaveLimits` the ceiling), and `SaveScope.selectedEntries` is
plumbed through the queue and the run — but there is **no review-step UI yet**.
Until there is, a multi-entry save is bounded and cancellable but is not
previewed. Wording for that screen is fixed in `STORE_PACKAGE.md` §6.4.

## 6. Stopping conditions

`lib/save/stop_conditions.dart`, one `StopReason` per outcome, persisted on
`save_runs.stop_reason` and `queue_tasks.stop_reason`. See STORE_POLICY_MAP.md §7
for the full table.

The app detects and stops. There is no retry-with-different-headers, no
alternate-URL attempt, no cookie manipulation, and no rate-limit wait-out
anywhere in the codebase.

## 7. Capture modes and unsupported media

**Built today.** Audio and video are **not saved**: `AssetFetcher` accepts image
bytes only, verified by magic number rather than `Content-Type`. `<video>`,
`<audio>` and media `<iframe>`s are counted by the page probe
(`PageMediaSignals`) and the run logs that they were left alone; no media URL is
read or fetched. Images are stored byte-for-byte in app-private storage — no
re-encoding, and no export to Photos, Gallery or Downloads.

**Built today.** The capture modes are on screen in the save sheet, and the
old `save_runs.include_images` boolean is gone: it could not express the
difference between an ordered sequence of full-size images and an article with
pictures in it, and nothing ever read it. `save_runs.capture_mode` and
`queue_tasks.capture_mode` carry a real `CaptureMode` end to end.

A page that is primarily a video is classified `videoDominant`, the sheet says
plainly that video is not saved, and — when the page carries no readable text —
the save is refused rather than falling back to sweeping up its thumbnails.
A document's inline image that was not stored renders as an honest "this image
was not saved" placeholder in its right position.

**Not built, and out of scope:** any video capture or playback. See §11.

### 7.1 The restricted-site capture policy

`lib/save/capture_policy.dart`. A static, manually maintained list of commercial
content services — subscription video, hosted commercial video, music,
audiobooks, ebook stores and readers, licensed serialised-reading services and
official publisher reading services — that the app **does not save from**.

**Browsing them is untouched.** Back, forward, reload, the address bar, sign-in
and ordinary navigation all work exactly as they do anywhere else. What is
withheld is capture, and only capture. A user browsing a restricted site sees no
warning and no explanation — the save control is simply not there.

**Two rule kinds, and no third.**

| Kind | Constant | Matches |
|---|---|---|
| Domain | `restrictedCaptureDomains` | the apex **and every subdomain**: `host == domain` or `host` ends with `.domain` |
| Exact host | `restrictedCaptureHosts` | that normalised host and nothing else |

Amazon's retail domains are on the **domain** list and are therefore blocked
whole: its reading, video, music and audiobook services are served from paths and
subdomains of the retail domains, and no static rule can separate a product page
from a reader without inspecting the page. Apple and Google are on the
**exact-host** list only — `tv.apple.com` and `play.google.com` are restricted;
`apple.com`, `developer.apple.com`, `support.apple.com`, `google.com` and
`developers.google.com` are not. Publisher reading services hosted beneath broad
parent domains are named individually for the same reason.

**Matching is on `Uri.host` alone.** Normalisation is: require `http`/`https`,
lowercase, strip trailing dots; ports never appear in `Uri.host`, so a port
changes nothing. There is no substring matching anywhere, which is what stops
`notyoutube.com`, `fakeamazon.com` and `youtube.com.example.org` from matching,
and why a restricted name sitting in a path or a query parameter is never seen at
all. A malformed, hostless or non-web URL answers "not restricted" — it is not on
the list, and every capture path already refuses it for its own reasons.

**This is not a per-page judgement.** The app does not determine whether a given
page is paid, licensed, protected or public, and does not try. Conservative
overblocking is the deliberate trade: a marketing page, a store listing or a
support article on one of these hosts is refused along with everything else.

**Enforcement is below the UI, at every boundary independently.** These are the
files that *ask* the policy — each imports `capture_policy.dart` and decides for
itself:

| Boundary | Where |
|---|---|
| The Browser's save control (absent, not disabled) | `features/browser_save_state.dart`, `features/browser_screen.dart` |
| Direct start · resume · retry · enqueue · the pump · update-check scheduling | `queue/task_queue.dart` |
| Run start, per-entry continuation, and the landed URL after a redirect | `save/save_run.dart` |
| Before the page is probed, and again before anything is committed | `save/save_engine.dart` |
| Update checking, every navigation it would make, and every discovered row | `library/update_checker.dart` |
| Whether a collection may be checked at all (`collectionSourceIsRestricted` → `collectionCheckBlock`) | `library/library_check.dart` |

Everything else that mentions the policy only *reports* it, and is not a
boundary: `features/browser_page_actions.dart` receives the already-decided
`canSave` flag and omits its Save block, and
`features/collection_detail_screen.dart`, `features/library_screen.dart` and
`features/save_queue_ui.dart` import nothing from it but
`kCaptureRestrictedMessage`, the one sentence (§6.5.1 of STORE_PACKAGE.md).
A screen that displays a refusal is not the thing that made it.

**And what it deliberately does not cover.** The policy asks "may this app
capture this *page*". An asset is part of a page that has already been judged,
so an asset's own host is never tested:

| URL | Policy applies |
|---|---|
| The Browser's page · a task's source URL · an update-check source and every page that walk opens · a discovered entry's page · top-level navigation, redirects and the landed URL · the manifest's `sourceUrl` before commit | **yes** |
| An image `src`, a responsive candidate, a CSS background, a document's inline image · the CDN or third-party host delivering any of them · an **asset request's** own redirects | **no** |

That second row is load-bearing. Ordinary sites deliver their pictures through
CDNs owned by large commercial platforms, and a host under `amazon.com`,
`googlevideo.com` or `books.google.com` serving an image on an otherwise
permitted page is completely normal. Testing it against the list refused those
images and marked the entry `partial` — a false refusal on content the user was
entitled to keep, produced by a rule aimed at something else entirely.

A **top-level** redirect into a restricted site still ends the run (`save_run.dart`
checks the landed URL). An **asset** redirect onto a restricted CDN does not: it
is not a document navigation, and the page it belongs to was judged already.

`AssetFetcher` therefore does not import the policy and is **not** the
authoritative boundary. It cannot become one either: it accepts image bytes only
(magic number, not `Content-Type`), writes into an already-open staging
directory, and returns an `EntryAsset` — there is no path from it to a page, a
document or a row. `SaveEngine` validates the page *before* `fileStore.beginEntry`,
so a restricted page never opens a staging directory and never reaches the
download loop at all; `test/asset_host_policy_test.dart` asserts that no request
is made in that case. The audio/video refusal that lives in `AssetFetcher` is a
separate rule (§7) and is untouched by any of this.

A refused queue row becomes a terminal `failed` row carrying
`StopReason.captureRestrictedForSite` (§6). It is kept rather than deleted,
nothing re-runs it on its own, and `retryTask` refuses to clone it.

**It never touches what is already held.** No collection, entry, file, reading
position, read state or history is modified or removed by this policy — it
prevents *new* capture, re-capture, retry, resume, continuation and update
discovery, and nothing else.

**Independent of the media rules.** §7 and §11 still apply everywhere: on a
permitted site audio and video are still never saved, and unsupported media is
never reclassified as image or text in order to continue.

**This is risk reduction, not a compliance guarantee.** The list is incomplete by
construction, and a host's absence from it says nothing about whether saving a
given page is permitted. Reasoning is in STORE_POLICY_MAP.md §1.

## 8. Database — version 1, created whole

`lib/storage/database.dart`. `schemaVersion` is **1**, the strategy has an
`onCreate` and **no `onUpgrade`**, and there is no schema dump, step verifier or
data-copying routine anywhere in the project.

Tables: `collections` · `entries` · `save_runs` · `user_page_hints` · `settings` ·
`queue_tasks` · `browsing_history` · `saved_sites` · `favicon_cache`.

Columns carrying the three separated concepts:
`entries.content_kind` / `content_kind_confidence` / `content_kind_is_user_set`
(what the page was) · `entries.artifact_format` / `capture_mode` (what the
package holds and how it was produced) · `collections.preferred_capture_mode`
(what to propose next time) · `save_runs.capture_mode` /
`capture_mode_is_user_set` and the same pair on `queue_tasks`.

Relationships: `entries.collection_id → collections.id`, nullable, with
`PRAGMA foreign_keys = ON` set in `beforeOpen`. There is **no `ON DELETE
CASCADE`**: a collection row cannot go while an entry still points at it, which
is what forces permanent deletion to remove dependents first and in a
transaction (§8.2). The four browsing tables reference nothing in the library
and nothing references them, so clearing history can never cascade into saved
content.

Indexes created with the schema: a **partial unique index** on
`entries(url_key) WHERE collection_id IS NULL` (a composite UNIQUE cannot enforce
standalone identity — SQLite treats NULLs as distinct), plus
`entries(collection_id, entry_order | save_status | read_status)`,
`entries(url_key)`, `entries(canonical_url)`, `entries(last_read_at)`,
`collections(lifecycle, last_read_at)`, `collections(created_at)`,
`queue_tasks(state, order_index)`, `browsing_history(source, visited_at)`, and a
unique index on `saved_sites(url_key)`.

Pages live in each entry's `manifest.json`, next to the bytes they describe,
rather than in a table that could disagree with the files.

### 8.1 Entry packages and manifest versioning

    library/<collection-id>/entries/<entry-id>/
      manifest.json        always
      document.json        structured-document entries only
      assets/001.png …     image pages, or a document's inline images
    library/standalone/<entry-id>/    entries belonging to no collection

**`manifest.json` is version 2.** It gained `artifact`, `captureMode` and a
`document` reference. Version 1 packages are read exactly as written and are
never rewritten in place: a manifest with no `artifact` field is an image
sequence, because that is the only thing this app could produce when it wrote
one. That rule is asserted against literal version-1 JSON in
`test/document_persistence_test.dart`, not against something this build wrote.

An `artifact` value this build does not recognise resolves to
`ArtifactFormat.unknown` and the reader says the entry was saved in a format it
cannot open. It is deliberately *not* read as an image sequence — misreading a
newer package would be worse than refusing it.

`document.json` is a list of typed blocks with plain text and offset-based
emphasis marks. It is **not** HTML: a saved page cannot carry a script, a
stylesheet, an iframe, an event handler or a remote reference, and the offline
reader has no HTML engine in it at all.

The database is still **version 1 with no migration system**, per the rule at
the top of this section: nothing has shipped, so the new columns were added to
`onCreate` rather than to a migration branch. The durable user data is the
packages on disk, and `storage/recovery.dart` rebuilds library rows from them —
for both manifest versions, and for standalone entries as well as collected
ones.

That last property is a **capability, not a guarantee that a row always comes
back**, and the difference matters: recovery reconciles the packages it finds,
so anything that intends a row to stay gone has to remove the package too. That
is exactly why permanent deletion takes the files out of `library/` before it
touches a row — see §8.2.

### 8.2 Three ways content leaves: archive · remove files · delete

Three operations, three blast radii, and none of them is a substitute for
another. The confirmation copy for each is built on this table.

| Operation | Entry point | Rows written | Files | Reversible |
|---|---|---|---|---|
| **Archive a collection** | `CollectionRepository.archive` → `setCollectionLifecycle` | `collections.lifecycle` + `archived_at`, nothing else | untouched | **Yes** — *Restore* puts it back exactly as it was |
| **Remove offline files** | `CleanupService.removeOffline` (soft, with undo) / `removeOfflineNow` (bulk) | `content_path`, `byte_size`, `offline_removed_at` on the entry, nothing else | that entry's bytes | **Yes** in substance — the entry never left the library, so it reads "Not available offline — save again", and the soft path also has a real undo window |
| **Delete a collection permanently** | `CollectionDeletionService.delete` (`lib/library/collection_deletion.dart`) | the collection row, its entry rows, and the local work records that named it | every file the collection owns | **No.** The *source* can be saved again, which produces a new collection with a new id |

Archiving hides, removal frees space, and only deletion removes the record.
Archiving a collection is not a quiet way to delete it, and removing offline
files is not a way to delete an entry — see the two invariants in §9.

The action lives on the collection screen's overflow menu, below a rule and in
the danger colour, and it is offered only for an actual collection: a
standalone entry has no collection to delete. There is one confirmation, not a
type-the-name step — nothing else in this product uses that pattern.

#### What deletion removes

- the `collections` row, and with it the collection-scoped preferences and
  pointers stored on it: `cleanup_preference`, `preferred_capture_mode`,
  `last_opened_entry_id`, `last_completed_entry_id`, `last_read_at`, and the
  update-check columns;
- every `entries` row of that collection, and therefore the reading state
  carried on those rows — `read_status`, `progress_fraction`, the anchor,
  `first_opened_at`, `completed_at` — so Continue Reading stops offering it
  because the rows it derives from are gone;
- `queue_tasks` rows naming the collection, **in any state**, waiting or
  historical;
- `save_runs` rows for an interrupted run that was walking it, so the library's
  Resume card cannot re-walk a collection that no longer exists;
- `library/<collection-id>/` entire, including the `.previous` backups an
  interrupted replacement leaves inside it;
- any entry file outside that tree — an entry saved standalone and later moved
  into the collection keeps its `library/standalone/<entry-id>` path, because
  reassignment moves the row and not the bytes;
- `tmp/undo-<entry-id>` and `tmp/<entry-id>`: a removal still inside its undo
  window would otherwise restore a package under `library/`, and startup
  recovery would reconcile it back into existence.

#### What deletion keeps

Other collections and their files · standalone entries that were never part of
it · `user_page_hints` · `saved_sites` · `browsing_history` · `favicon_cache` ·
`settings` · queue history belonging to anything else.

The hints are the deliberate one. They are keyed to a *host and page shape*,
not to a collection, they are shared with every other collection on that host,
and they are what makes saving the same source again work as well as it did the
first time. Deleting a collection is not a statement about the site it came
from.

#### The order, and why it is that order

1. **Stop the work.** The collection's queue rows are cancelled through the
   existing conditional-`UPDATE` path (§9): waiting rows are cancelled outright,
   a running one is asked to stop at its next safe point. Save tasks carry a
   collection id only when the caller knew one, so a save started from the
   Browser is matched by **address** instead — the entries' URLs, plus same host
   and same `collectionFingerprint` as the stored `collection_key` for a page
   that has never been saved. That second test is skipped for a key that is not
   a path (`manual:…`, `title:…`, `host:…`, and the `…#…` form a low-confidence
   grouping gets), because those keys are built so that nothing matches them.
   A row matched only by address is **cancelled, not deleted**: it names no
   collection, so it survives step 4 as ordinary cancelled history rather than
   disappearing from Activity without explanation.
2. **Refuse if anything still holds it.** A cooperative stop lands between
   entries, not instantly. If an entry is open in the reader or mid-save
   (`CleanupService.lockReasonFor`), if the live run is on one of the
   collection's addresses, or if a task naming it is still pending, the delete
   **refuses and nothing is touched**. `DeleteRefusal` names which
   — `gone` · `inUse` · `filesKept` — and the UI shows the reason. Deleting
   under an in-flight save would either resurrect the collection or fail the
   save on a foreign-key error.
3. **Move the files out of the library.** Every owned directory is *renamed*
   into `tmp/deleting-<collection-id>` — one atomic rename each, no partial
   trees. A failure here restores what was already moved and returns
   `DeleteRefusal.filesKept`; **nothing has been deleted** and the collection
   still works.
4. **Delete the rows in one transaction**, dependents first: queue rows, then
   the matching runs, then the entries, then the collection. The foreign key
   makes that order mandatory rather than stylistic (§8).
5. **Discard the staged tree.** A failure at this last step leaks into `tmp/`,
   which the startup sweep already owns. It is not a failed delete.

The filesystem cannot join the SQL transaction, so the ordering is chosen to
make the **reachable** intermediate state the harmless one:

- a crash between 3 and 4 leaves rows whose files are gone. That is a state the
  app already handles: opening such an entry finds no package, calls
  `markEntryContentMissing` — dropping `content_path` and recording *local files
  missing* — and says so instead of failing. The collection is still listed and
  a second delete finishes the job. Nothing comes back to life.
- the reverse order — rows first, bytes second — would leave committed packages
  under `library/` with no rows, and the next launch would reconcile them into
  a collection the user deleted. That failure is silent and looks like a bug in
  the app rather than an interrupted delete, which is why the ordering is not a
  preference.

Afterwards the same source can be saved again: identity is matched on
`(host, collection_key)`, the deleted row is gone, so a save creates a new
collection rather than joining a ghost.

### 8.3 Moving forward in the reader: completion, then cleanup

Three decisions that look like one and are not: **has the reader finished this
entry**, **where are they going**, and **what happens to the finished entry's
downloaded files**. Collapsing them is how "next entry" turns into a delete
button. The reader's forward transition (`_goTo` → `_planForForward` →
`_applyOnArrival` in `lib/features/reader_screen.dart`) keeps them apart.

**Finishing an entry** happens automatically at
`CompletionPolicy.threshold` (0.97 of the entry) once the reader has stayed
past it for `CompletionPolicy.dwell` (800 ms). That dwell is what stops a fling
to the bottom from counting as reading, and it is the *only* automatic route to
`completed`.

**Moving forward is not evidence of finishing.** A reader looks ahead, compares
two entries, mistaps, or means to come back. So a forward move out of an
unfinished entry does one of two things, decided by
`CompletionPolicy.nearThreshold` (0.90 — a tenth of the entry left, measured
the way `ReadingPosition.fraction` measures, i.e. against the **bottom** of the
viewport):

| Where the reader is | What happens |
|---|---|
| Entry already `completed` | The collection's cleanup decision applies (asked once if unset) |
| Unfinished, at or past `nearThreshold` | Asked: *Mark complete and continue* · *Continue without completing* · *Cancel* |
| Unfinished, below `nearThreshold` | Move, and change nothing — no question, no completion, no cleanup |

*Mark complete and continue* joins the first row: the entry is marked read and
the collection's decision applies to it. *Continue without completing* moves on
and leaves the entry `inProgress` with its position, its anchor and its files —
the collection's `remove` preference is deliberately **not** consulted, because
it is a rule about finished entries. *Cancel* stays put.

**The cleanup preference is per-collection and tri-state** —
`collections.cleanup_preference` is unset · `keep` · `remove`, and unset is a
question, not a default. It is asked once per collection, on the first
transition that actually finishes an entry, and an answer is stored the moment
it is given (the dialog's button says *Save choice*, and the collection sheet
writes on each tap). It applies only to entries that are complete or that the
reader has just said are complete. It is reset from *Collection detail →
Downloaded entries → Ask again next time*, and it goes with the collection row
on deletion and on a developer reset.

**Order, and what it protects.** Flush the outgoing position → confirm the
destination with `readerCanOpen` → ask → move → **and only once the destination
has actually opened**, mark complete and remove. "Opened" means the load
resolved to something readable, not merely that the row looked right a moment
earlier: a package whose files vanished between the check and the read lands on
the unavailable screen, and the entry just left is then the only readable thing
the reader has. So a transition that is cancelled, or whose destination fails at
any point, leaves the outgoing entry with its progress, its status and its
files. One transition runs at a time, so a burst of taps completes and removes
once.

Removal is `CleanupService.removeOffline` and nothing more — the entry row, its
`source_url`, its reading history and its place in the collection all survive,
and there is a real undo window (§8.2). None of this is conditioned on
entitlement: `lib/features/reader_screen.dart`, `lib/storage/cleanup.dart` and
`lib/reading/` import nothing from `lib/capability/`, and `entitlement_test.dart`
fails the build if that changes.

## 9. Invariants worth keeping

- **Reading state is writable only from `lib/reading/`.** `writeEntryReading` is
  the only DAO method that can reach a reading column.
- **A completed entry is 100% read.** `progress_fraction` is pinned at 1 whenever
  `read_status` is `completed`, on write and again on display.
- **Removing offline files is not deleting an entry.** Only `content_path`,
  `byte_size` and `offline_removed_at` are written; everything else survives, and
  the entry reads as "Not available offline — save again". Deleting is a
  different operation with a different entry point (§8.2), and neither this nor
  archiving may be offered as a way to do it.
- **Collection-owned state is deleted through `CollectionDeletionService`, or
  it is not deleted.** Permanent deletion is one flow — cancel the collection's
  queue work, refuse while an entry is locked or a save is still on it, move
  every owned directory out of `library/` *before* any row goes, then remove the
  queue rows, the interrupted runs, the entries and the collection in one
  transaction. Each part is load-bearing: skipping the file move lets startup
  recovery rebuild the entries from the manifests still on disk; skipping the
  cancellation lets delayed work write into a collection that is being deleted.
  `deleteCollection`, `deleteEntriesForCollection`,
  `deleteQueueTasksForCollection` and `allRuns` are that service's vocabulary
  and have no other caller — deleting the collection row on its own leaves
  orphaned files, live queue rows and a foreign-key error. See §8.2.
- **Semantic label and stored format are separate, and only one is editable.**
  `setEntryContentKind` writes `content_kind` and cannot reach
  `artifact_format`. Relabelling an image package as an article changes what it
  is called; it never causes the reader to parse it as a document.
- **A reading anchor belongs to an artifact.** `ReadingPosition.anchorIndex` is
  a panel index for an image sequence and a *block* index for a document. When
  a re-save changes an entry's stored format, `carryReading` keeps everything
  that is a fact about the content (finished, first opened, the
  content-independent fraction) and resets only the anchor, which would
  otherwise drop the reader somewhere arbitrary and call it "where you were".
- **Moving between entries never finishes one by itself.** The only automatic
  route to `completed` is `CompletionPolicy.threshold` plus its dwell. Forward
  movement out of a nearly-finished entry *asks*; below `nearThreshold` it does
  not even ask, and an unfinished entry is always still resumable afterwards.
  Backward movement asks nothing and changes nothing. See §8.3.
- **An entry's `source_url` is durable.** Every writer names its columns, so it
  survives removal, archive, restore, re-save and reading updates. It is what
  "Open original page" stands on.
- **Cancelling preserves the row; dismissing deletes it.** A cancel moves a task
  to the existing `cancelled` state — no sixth state — and *Remove from Activity*
  deletes a row that is already terminal, refusing anything live. Both the pump's
  claim and every cancel go through one conditional SQL `UPDATE`
  (`updateQueueTaskIfState`), so exactly one wins and the loser is told.
  `cancelTask` reports which happened (`CancelResult`). Stopping is cooperative
  everywhere — `removeOfflineNow` takes `shouldContinue` and is asked between
  entries — so the wording is "at the next safe point", never an instant stop the
  app cannot deliver.
- **Only manual navigation enters browsing history.** Enforced twice: the source
  the automation sets, and `effectiveNavigationSource`, which cannot answer
  `manual` while `automationOwner` is held.
- **An update check is a visible foreground operation, and a shallow one.**
  Three parts, and dropping any of them makes the Browser move on its own with
  nobody able to see or stop it. It **opens the page it is about to read**: the
  queue asks `UpdateChecker.firstPageToInspect` and passes it to the shell's
  `ensureBrowserVisible`, which routes it through `BrowserNavigator` — the same
  mechanism every "open in Browser" uses, and the reason the page is *revealed*
  rather than loaded behind Browser Home. It **shows `UpdateCheckPanel`** in the
  same slot the save run gets, sharing `features/operation_panel.dart` so
  neither panel is a copy of the other, and stopping goes through
  `TaskQueueController.stopRunningCheck` so the Activity row and the panel agree.
  And it **follows at most `kUpdateCheckForwardDepth` (2) next-entry links**:
  the page a check starts on is depth 0, so two hops are two further pages, and
  whatever is beyond is left for the next check, which resumes from the
  `next_source_url` this one stored. The bound is on `UpdateCheckConfig` and is
  check-only — save ranges come from `SaveLimits.forScope` and share nothing
  with it.
- **A Library-wide check is that same check, repeated — never a second
  checker.** "Check all collections" (`features/library_check_ui.dart`) expands
  through `TaskQueueController.enqueueLibraryCheck` into one ordinary
  `collectionCheck` row per collection, which the pump runs one at a time
  through `UpdateChecker.check`. Everything else falls out of that choice rather
  than being built again: one collection's failure is its own history row with
  its own reason, a kill mid-run leaves the remainder as queued rows for the
  restart offer, and stopping is the queue's existing `cancelQueuedChecks` —
  waiting collections are dropped (scoped to the run's own task ids, so a
  single-collection check queued from a collection screen is not swept up in
  it), the one in flight finishes, and every collection already checked keeps
  its result.

  *One eligibility rule.* `collectionCheckBlock` in
  `library/library_check.dart` is the only answer to "can this collection be
  checked?", asked by the queue before it schedules and by the Library screen
  before it offers, so the count the user is shown is the count that runs. It
  excludes archived collections, restricted sources (through
  `collectionSourceIsRestricted`, the one place a collection's three source
  columns are tested together), standalone entries, and collections with no
  page to start from — the last mirroring the checker's own precondition, so
  nothing is scheduled that could only fail. **There is no durable "track this
  collection" preference:** every part of that answer is already derivable from
  existing state, and a stored flag would mean a schema column the version-1
  database cannot take.

  *What the run reports is read back, not accumulated.*
  `computeLibraryCheckReport` is pure and derives everything from rows that
  already exist — the queue's task states, each collection's `last_check_*`
  columns, and `discovered_at` — so nothing new is persisted and the report
  cannot drift from the database. Its phases are explicit (`idle · preparing ·
  checking · blocked · completed · partiallyCompleted · cancelled ·
  failedBeforeAnyCheck`): a partly successful run is never collapsed into a
  failure, and a run that found nothing still reports how many collections it
  asked. The run itself is session state (`libraryCheckPlanProvider`); a
  restart loses the framing of "these were one operation" and nothing else,
  because every result lives on the collection it belongs to.

  *Checking is not saving.* A discovered entry is a `knownRemote` row with no
  package; the library-wide flow queues no save and starts no download. The
  Collection Detail card names its own scope ("Check this collection") and
  points at the Library for the many-collection version — one vocabulary, two
  granularities, and neither of them a refresh or a device sync.
- **A number a discovery cannot stand behind stops it.** The number an entry is
  discovered with is durable: it sets reading order and becomes the checkpoint
  the next check measures novelty against, so a wrong one does not merely
  display wrong — everything genuinely newer afterwards compares as older, and
  discovery for that collection quietly ends. `lib/library/entry_identity.dart`
  is the narrow guard against that. It asks one question and no other: **do the
  two independent readings of this entry — its label and its address —
  contradict each other, in a way the rest of the list says they should not?**
  It is deliberately *not* a plausibility check. Collections number in twos,
  restart at a season boundary, skip and use decimals, and none of that is this
  file's business.

  Nothing here repairs anything. There is no "drop the last digit", no "assume
  the next number", no "prefer the URL" — guessing which reading was right
  trades one class of wrong data for a quieter one. A contradiction the evidence
  cannot resolve **stops the operation and keeps the contradiction**, carrying
  `kEntryIdentityUnreliableMessage`: *"Could not reliably identify one or more
  entries."* Reasons are a named enum (`EntryIdentityDoubt`) rather than free
  text, so a new one cannot be added by writing a new sentence. Tested in
  `test/entry_identity_test.dart`.
- **A discovery can be withdrawn; nothing else can.** Discovery is not a
  growing union of everything ever seen: a `knownRemote` row is a claim about
  somebody else's site, and a later reading of that site can show the claim is
  no longer true. Left forever, those rows are offered as fetchable, point at
  addresses that are gone, and — because the checkpoint is the highest number
  held — one wrong high number silently ends discovery for the collection.

  *Absence has to be proved, and only a window of it can be.* A check reads one
  page, and a page is a window: paginated, latest-N, or built as the user
  scrolls. So `discoverFromEntryList` returns an `ObservedEntryWindow` — the
  complete set of entry addresses the page showed and the numeric interval it
  covered — and returns **none at all** unless the reading was recognisable,
  unambiguously ordered, free of identity concerns, not truncated by the
  `maxNew` bound, and able to place every entry it saw on the number line. The
  interval's floor is hard; its ceiling opens only for a list the page itself
  ran newest-first, and `reconcileDiscoveredEntries` closes it again the moment
  an entry whose bytes are on this device sits above it. The chain walk never
  produces a window — two hops ahead of the newest entry held says nothing
  about a collection's membership.

  *The rule lives at the database.* `AppDatabase.reconcileDiscoveredEntries`
  takes the observation and never a list of rows, so no caller can name an
  entry into deletion: each row must satisfy `_isDiscoveredOnly` on its own —
  every column that could carry bytes, a reading position or a user correction,
  not just `save_status` — carry a number that falls inside the window, be
  absent from the observed set, and be claimed by no queued or running save.
  A pending multi-entry save for the collection stops the whole operation,
  because where such a run will reach is not knowable from its row. It is one
  transaction, so a collection is never half reconciled. A failed, cancelled,
  doubted, unordered or truncated check reconciles nothing at all.

  *And the checkpoint is rebuilt, not adjusted.* Reconciliation runs before the
  new rows are written; when it removed anything, the checker re-derives
  `latestKnownNumber` from the database and re-reads the page already in hand —
  pure, no second request — so the check that drops a stale high number is the
  same check that finds what that number had been hiding.

  *Seen again is not found.* An entry the page still lists is not a discovery
  and is never counted as one, but it is the source's current words about a row
  written from an older reading. `refreshDiscoveredEntry` takes them, through
  the same identity gate the new rows pass: the label is replaced, a **missing**
  number or next address is filled in, and weak provenance is upgraded. A
  stored number is never overwritten — it orders the collection and is the next
  check's checkpoint, so a second reading that disagrees is logged and the
  stored value kept. `discovered_at` is deliberately untouched: it is what a
  run's report counts, and moving it would make everything the source still
  lists read as newly found.

  *And the user can retract one by hand.* Some stale rows are unreachable by
  any check — below the window it could read, unnumbered, or in a collection
  with no entry list at all — so *Forget this entry* offers the same operation
  manually. Same rule, same place: `forgetDiscoveredEntry` re-reads the row and
  the queue inside the transaction that deletes it, refuses anything that is no
  longer only a discovery, and refuses rather than cancels when a save is
  waiting on it. The screens ask `isDiscoveredOnlyEntry` before offering it, so
  no surface restates the rule as `save_status == …`.

  *A failed save is an attempt, not a verdict.* This app cannot tell a page the
  source withdrew from one that timed out — `classifyPageError` maps 4xx and
  5xx alike to `unavailable` — so nothing is ever deleted on a failure. What is
  recorded is that the attempt happened (`save_error` on a row that is still a
  bare discovery), which takes the entry out of *Save new* while leaving it
  listed, individually retryable, and exactly as removable as it was. Asking
  for that one entry again clears the note.
- **Checking is independent of navigation; the Library's *entry point* is
  not.** The checker needs a rendered WebView, so a run started from the
  Library card moves the user into the Browser to watch it. That move has a
  second half, and leaving it out is what stranded people on somebody else's
  entry list after the last collection finished. It belongs to the entry
  point, not to the operation: `LibraryCheckFlow`
  (`features/library_check_flow.dart`) is the *foreground coordinator*, and it
  is the only thing that knows about tabs, surfaces and sheets.

  *What a run owns.* This app has no browser tabs and the check creates no
  WebView of its own — there is one shared surface, and what a run visibly
  changes is which shell tab is showing and which *local* surface
  (`BrowserPresentation`: website · home · address editor) is stacked over the
  page. So the flow records exactly that at the start: the tab the run was
  started from (`shellTabProvider`), the local surface it is about to cover,
  and whether it is what brings the Browser forward at all. "Cleaning up" is
  giving those two back. Nothing is closed, cleared or reloaded: no page is
  navigated, no cookie, history entry or saved site is touched, and the
  document the WebView ended on stays where it is — restoring *that* would mean
  fetching someone else's page a second time.

  *Completion.* `LibraryCheckCompletionWatcher` lives in the Library tab —
  always built inside the shell's `IndexedStack`, and outside its `ListView`,
  because a lazily-built watcher is not a watcher. It subscribes rather than
  `ref.watch`es: a run can end while the user is on another route, where a
  covered subtree is not rebuilt for a stream tick. On a terminal report
  (`completed` · `partiallyCompleted` · `cancelled` · `failedBeforeAnyCheck`,
  never `blocked`, which still has work queued) it claims the presentation
  once — `LibraryCheckFlow.claimCompletion`, a field on the session, not a
  global — then hands the local surface back, returns the user to the tab they
  started from, and opens the terminal report as a bottom sheet. Dismissing the
  sheet is not dismissing the result: the card keeps it until the user clears
  it there.

  *Whose screen is it.* One rule, evaluated at completion: if the user has
  pushed another surface above the shell — the reader, Settings, Activity, a
  collection — the flow **releases** and does nothing at all. It does not
  navigate, restore or present; the result waits on the card. Being anywhere
  *inside* the shell (either tab) still counts as the run's presentation,
  because the run is what put them there.

  *This policy belongs to this entry point.* `LibraryCheckPresentation`
  distinguishes a run that owns the foreground from one that does not, and the
  execution path is identical for both: same eligibility, same queue rows, same
  `UpdateChecker`, same `computeLibraryCheckReport`. An unattached run
  navigates nothing and presents nothing. Concurrent or background-capable
  checking is **not built** and remains out of scope; what exists is the seam
  it would use.
- **A page is only read while the app is drawing it.** The authority is
  `BrowserController.surfaceIsPainted`, written by `resolveBrowserSurface` in
  `lib/browser/browser_surface_policy.dart` and nowhere else, and the save
  engine and the update checker both hold on it. It is the app's own fact, not
  the page's, because no page-side signal answers it portably: a WebView the app
  has stopped compositing keeps reporting a full viewport and keeps accepting
  programmatic scrolling on both platforms, and on Android it goes on calling
  itself `visible`. What actually degrades is `requestAnimationFrame` — stopped
  on iOS, throttled to about a fifth of the display rate on Android — which is
  how a page's lazy content silently fails to arrive, and how the 2026-07-27
  audit got a complete-looking entry made of the wrong images. The two page-side
  checks stay as corroboration and are never relaxed: a zero viewport holds, and
  a page reporting itself hidden holds. Measured on both platforms in
  `integration_test/occlusion_gate_test.dart`; the numbers are in
  docs/FOREGROUND_MULTITASKING.md §3.1.
- **Whether the WebView keeps being drawn is one decision in one place.**
  `ForegroundMultitasking` is a single boolean; while it is on and an operation
  owns the WebView, the shell keeps the Browser child onstage and every screen
  pushed above the shell (`AppPage`) stops being an opaque route, so Flutter goes
  on painting the one WebView at the one rect it has always had. Occlusion,
  pointer blocking and semantics blocking are Flutter's own — a route's modal
  barrier absorbs every pointer and wraps its content in `BlockSemantics`. With
  the boolean off, every one of those reverts and the behaviour is exactly what
  it was: leaving the Browser holds the run. See
  docs/FOREGROUND_MULTITASKING.md.
- **What an operation does is never gated; only where the user has to be while
  it happens.** This is the whole monetization boundary, and it is one sentence
  on purpose. **Update checking is Free** — a single Collection check, the
  Library-wide check that repeats it, the Entries either discovers, and the
  report either produces. **Saving is Free**, single and bounded multi-entry, in
  every capture mode. The library, the offline reader, reading progress,
  archive, cleanup, deletion, retry and recovery are Free. The **only** thing
  the Pro capability buys is the *execution experience*: a Browser-dependent
  phase continuing while the user reads another Entry or uses the Library,
  instead of holding until they come back.

  Two consequences, both load-bearing. **The Free flow may never be degraded to
  create Pro value** — a Free operation is not cancelled, truncated, slowed, or
  limited in what it may discover, and walking away from the Browser pauses and
  resumes exactly as it did before the capability existed. And **this is
  foreground multitasking, not background execution**: nothing continues once
  the app is not in front, which is unchanged.

  Enforced, not merely asserted: `test/library_check_test.dart` fails the build
  if gating, counter or purchase vocabulary appears anywhere in `lib/` outside
  the capability seam and three files that only name it, and
  `entitlement_test.dart` fails the build if a reading or cleanup surface so
  much as imports `lib/capability/`. Boundary and rationale:
  docs/FOREGROUND_MULTITASKING.md §10.0. An older proposal to sell update
  checking is recorded, and marked superseded, in MONETIZATION_STRATEGY.md §8.3.
- **The app ships no page hints.** `user_page_hints` is empty on a clean install
  and nothing seeds it.
- **The restricted-site policy lives in one file and is asked at every
  boundary.** `lib/save/capture_policy.dart` is the only file in `lib/` that may
  name a host, and it only ever *refuses*. Declaring
  `restrictedCaptureDomains` or `restrictedCaptureHosts` anywhere else fails
  `test/repository_cleanliness_test.dart` — a second copy is how the UI ends up
  hiding a control the engine still honours, or the reverse. Every capture
  boundary enforces the policy by importing it, never by keeping its own copy;
  a hidden button is not enforcement. **It judges pages, never assets** — an
  image's delivery host is not a capture source, and `AssetFetcher` must not
  import it. See §7.1.
- **`AppPalette` is the only source of colour.** `test/theme_palette_test.dart`
  scans `lib/` and fails on a literal `Color(0x…)`.
- **drift trap:** `insertOnConflictUpdate` treats a null field as *absent*, so
  anything that must be cleared needs its own narrow writer
  (`clearOfflineRemovedMark`, `clearRunPauseReason`).

## 10. Status — what is built, and what is not

This document describes a **foundation**, not a finished product. The split
matters because several safety properties are real in the domain layer and not
yet reachable from a screen.

| Area | State |
|---|---|
| Library / Collection / Entry model, standalone entries | **Built**, tested |
| Version-1 schema, no migration system | **Built**, tested (`schema_v1_test.dart`) |
| Content-shape model and detection | **Built**; `detectContentKind` / `detectSequence` / `detectCaptureCapabilities` unit-tested directly (`content_detection_test.dart`) |
| Capture modes (images · text · text+images) | **Built**, tested (`document_save_test.dart`, `document_extraction_test.dart`) |
| Structured-document extraction and storage | **Built**, tested |
| Structured-document reader | **Built**, tested (`document_reader_test.dart`) |
| Manifest v1 → v2 compatibility | **Built**, tested against literal v1 JSON |
| Collection capture-mode preference, with validated fallback | **Built**, tested |
| Entry content-type correction (UI) | **Built** — label only; cannot change the stored artifact |
| Semantic labels, one producer | **Built**, tested |
| Stopping conditions and `StopReason` | **Built** in `stop_conditions.dart` and wired into the run; **no dedicated tests yet** |
| Bounded scopes, required `range`, no unbounded run | **Built**, tested |
| Audio/video never fetched | **Built** (image-only MIME allow-list) |
| Video-dominant pages classified and refused | **Built**, tested; **no video capture or playback exists** |
| Restricted-site capture policy (§7.1) | **Built**, tested (`capture_policy_test.dart`, `capture_restriction_test.dart`, `asset_host_policy_test.dart`); the list is static and manually maintained, and applies to pages only |
| Audio/video **bytes** refused by the fetcher | **Built**, tested — `asset_host_policy_test.dart` feeds real MP4, MP3 and WAV byte streams to `AssetFetcher` and asserts each comes back `AssetStatus.failed` (*not a recognised image format*): from an ordinary host, from a restricted host, and under a lying `.png` / `.jpg` extension. It also asserts `detectImageMime` answers null for all three. This closes the gap STORE_POLICY_MAP.md §1 previously recorded as untested |
| Offline reader, reading position, queue, cleanup, archive, storage | **Built**, tested |
| Permanent collection deletion (§8.2) | **Built**, tested (`collection_delete_test.dart`) |
| Repository-cleanliness guard | **Built**, tested |
| Save-scope review step (UI) | **Deferred** |
| First-use and contextual content-rights disclosures (UI) | **Deferred** |
| Video capture or playback | **Not built, and out of scope** — see §11 |
| Privacy / Terms / Content-rights settings pages | **Deferred** |
| Hosted demo site, store assets | **Deferred**, external |
| Foreground multitasking — one operation continuing while the user reads | **Built**, off by default; unit, widget and fixture-integration tested, and the architecture gate has passed on physical iOS hardware. It stays off because accessibility verification (VoiceOver, TalkBack) has not been done and Android hardware has not been run — see docs/FOREGROUND_MULTITASKING.md §14 and the plan's §5 |
| Free/Pro capability boundary — entitlement, capability, preference | **Built**, tested (`entitlement_test.dart`, `foreground_gate_test.dart`, `foreground_gate_ui_test.dart`). It gates exactly one behaviour: whether a Browser-dependent phase may continue while another screen is in front. **Update checking, saving and every library and reading function are Free**; only that execution mode is Pro — see the invariant in §9 and docs/FOREGROUND_MULTITASKING.md §10.0. **There is no billing** — `productionEntitlement()` returns `free`, and the Pro path is reachable only through the internal-build override |
| Device runtime verification | **Partially run.** The architecture gate (`integration_test/occlusion_gate_test.dart`) has passed on the iOS Simulator, the Android emulator **and a cabled iPhone 17 (iOS 26.5.2)**; idle/cleanup, real-source save and bounded multi-entry scenarios were recorded on that iPhone. Still outstanding: any physical **Android** device, VoiceOver and TalkBack, and the profile-build performance, memory, thermal and renderer-termination phases. The full record — including which measurements were taken on hardware and which were not — is docs/FOREGROUND_MULTITASKING_PLAN.md §6 |

## 11. The video boundary

Video is **detected and refused**, never captured. What exists:

- `ContentKind.videoDominant`, with the three guards in §4.
- `PageMediaSignals` — a count, the largest player's laid-out area, and whether
  it sits in the readable region. **Geometry only.** There is no field here that
  holds a media URL, and adding one would turn a classification signal into the
  first half of a downloader.
- Save-sheet copy saying video is not saved, and what will happen instead.
- A refusal when a video page carries nothing readable, rather than a fallback
  that sweeps up its thumbnails.
- `ArtifactFormat`, which a future video artifact could join as another value
  without disturbing the image or document formats.

What does **not** exist, and is out of scope: video URL extraction, network
interception, iframe inspection for media addresses, HLS, DASH, DRM, video file
storage, background video downloading, playback, picture-in-picture, subtitles,
seasons, and any genre-specific logic. `CaptureMode` has no video value on
purpose — the save sheet is built from that enum, so a mode the engine cannot
honour would become a button that lies.

Nothing in this repository, its store copy or its documentation describes video
saving as supported.

## 12. Known limitations

- **Text extraction is heuristic and says so.** The readable region is chosen
  from standard landmarks, then from paragraph density. A page that structures
  itself unusually may lose blocks or keep furniture; the failure mode is a
  named, explained refusal or a visibly incomplete document, never a silent
  half-save.
- **Furniture exclusion uses generic class/id words** (`comment`, `advert`,
  `sidebar`, `related`, `share`, …) alongside HTML landmarks. These are
  structural conventions, not a site list — but a page that names its main
  column with one of them will lose blocks.
- **A document restores *to* its position, not *at* it.** A paragraph has no
  offset until it has been laid out, so the document reader scrolls to the
  saved block on the first frame after measurement. The image reader still
  opens at its position, because panel heights are known from the manifest.
- **A document is built in full rather than lazily**, so every block offset is
  exact and restore is precise. Extraction caps the block count; a pathological
  page is bounded rather than unbounded.

  **This has a measured memory cost, and it is the open one.** Because every
  block is built, every inline image in a document is decoded and resident at
  once. On a physical iPhone in a debug build, one real entry of 81 blocks with
  76 inline images took the app from ≈482 MB to ≈1465 MB while its Reader was
  open, returning to ≈634 MB once closed — roughly 13 MB per image, which is an
  ordinary panel decoded at display width. **The cost is the count, not the
  size**, so it scales with how many pictures a document has and not with how
  large any one of them is. Numbers and method: FOREGROUND_MULTITASKING_PLAN.md
  §6.1c. Debug-build figures are not release figures, but the shape of the
  result is not a build-mode artefact.

  `lib/reading/decode_budget.dart` bounds each decode — it stops both readers
  *upscaling* a stored image narrower than the screen, which cost
  `(display/natural)²` for no added detail, and caps a single pathological
  panel. It bounds only on dimensions read back from the stored bytes, never on
  `EntryAsset.width` when `dimensionsVerified` is false, because that field is
  the page's unverified claim and trusting it could ask for fewer pixels than
  the file holds. It is correct and tested, and it **does not** address the
  count. Making image blocks lazy while keeping text offsets exact is the real
  fix and has not been attempted; it is a Reader change needing its own device
  validation for restore drift, flashing and repeated decoding.
- **The database has no migration system.** A developer with a library created
  before these columns existed must reset it; the packages on disk are
  unaffected and `storage/recovery.dart` rebuilds the rows from them.
