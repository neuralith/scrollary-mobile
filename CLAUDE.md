# Scrollary — project instructions

A personal reading library for web-based reading content, iOS-first and
Android-compatible: embedded browser + a library of Collections and Entries +
optional offline copies.

Read [../docs/TERMINOLOGY.md](../docs/TERMINOLOGY.md) before writing any
code. The documentation set for both halves of the product lives in
[../docs/](../docs/README.md): `PRODUCT.md` is the product definition,
`ARCHITECTURE.md` and `V2_ARCHITECTURE.md` the as-built model, `DECISIONS.md`
why a decision was made (cited below as V2-Dnn), `V2_SYNC.md` the sync design,
`V2_SAVE_FLOW.md` the save matrix, `V2_CAPABILITY_PARITY.md` what must stay
reachable, `V2_PORT_CHECKLIST.md` the rules for ported files,
`FOREGROUND_MULTITASKING.md` the Free/Pro boundary, and `STORE_PACKAGE.md` /
`STORE_POLICY_MAP.md` the store positioning and the reasoning behind the safety
rules. The sync service is a separate repository (`scrollary-backend`, Go +
PostgreSQL); the shared contract in `contracts/` is the only bridge.

## What this app is, and is not

It lets a user track web-based reading content they want to read, organise it
into Collections and Entries, keep their reading state, and — where they are
legally permitted to keep a copy — download Entries and read them offline.

**An Entry is in the library because the user wants to read or track it, not
because its content has been downloaded.** Downloading is a per-device
capability of an Entry, not the precondition for the Entry's existence, and
removing a download never removes the Entry. Do not write code, comments, tests
or copy that treats a non-downloaded Entry as second-class, or that uses "saved"
and "downloaded" as synonyms for "in the library".

It is **not** a bulk fetcher, an automated harvester, a site archiver, a client
for particular websites, a generic bookmark manager, a hosted content platform,
a content redistribution service, or a tool for getting past any access control.
Do not write code, comments, tests, fixtures, docs or store copy that position it
as any of those. `test/repository_cleanliness_test.dart` enforces part of this
and will fail the build.

## Where the code stands

V2 is a **recognition-driven, cross-platform reading library**: you read,
Scrollary recognises what it is, and your library stays current across your
devices. Folders are user organisation; a Collection has several Sources; an
Entry has Locations; downloading is a per-device capability of an Entry.

**V2 is the running app.** `lib/app.dart` routes to the V2 screens
(`lib/library_ui`, `lib/reading_v2`, `lib/features`), composed in
`lib/features/v2_composition.dart`. The V1 library screens, queue, update
checker and `CollectionDeletionService` are retired and there is no V1 fallback
to route to; `lib/library/` holds only the domain helpers V2 still calls
(`entry_labels.dart`, `collection_identity.dart`, `content_shape.dart`), not a
screen. **Do not describe the V1 shell as the running app.**

Three things future agents get wrong:

- **V2 replaced the V1 domain, not the V1 device knowledge.** A defined set of
  components is ported verbatim — render guards, image enumeration, lazy
  settling, the decode budget, FileStore, manifest, document, capture policy,
  detection, extraction, stop conditions, the asset fetcher, both readers.
  Change their call sites, never their internals; the port checklist
  ([../docs/V2_PORT_CHECKLIST.md](../docs/V2_PORT_CHECKLIST.md)) governs
  any further change to a ported file.
- **An Entry is not a URL.** That was V1's axiom. `url_key` is Location
  identity and `host + collection_key` is Source identity — same algorithms,
  one level down (V2-D15).
- **Before removing anything a V1 implementation used to do, read
  [../docs/V2_CAPABILITY_PARITY.md](../docs/V2_CAPABILITY_PARITY.md).** An
  implementation may go only when a durable decision retires its capability, or
  an equivalent surface exists, is reachable, and its parity test passes.
  Deleting a regression test needs the same authorisation.

The shared contract (`contracts/`) is frozen and changes only through
`contracts/README.md`'s protocol; the guard tests in `test/` gate every change.

**A synced field is written out by hand in both halves, and the service
*rejects* a field it does not know** — so an intent carrying one is parked on
the device forever, not silently dropped (V2-D73,
[../docs/V2_SYNC.md](../docs/V2_SYNC.md) §8.1a). Two tests hold the halves
together: `test/sync/support/contract_vocabulary.dart` reads
`contracts/openapi.yaml` and the fake service applies it, so every push test is
a parity test; the service has the same test for its own allowlist. Push is
strict and pull is tolerant, which is why the **service ships before the
client** that sends a new field.

## Standing rules

### Terminology — one model, one label system

- The canonical model is **Library / Collection / Entry / Page or Section**.
  `Collection` and `Entry` are the only nouns in code.
- User-facing nouns come from `lib/library/entry_labels.dart` and **nowhere
  else**. A screen that types its own noun is how one app calls the same thing
  three different things on three consecutive screens.
- Low or unknown confidence prints **Item** / **Saved item**. Never infer a
  structure from a number in a URL, and never infer a page from the fact that the
  content came from the web.

### Nothing site-specific ships

- No hostname, selector, site list, provider catalogue or "supported sites"
  anywhere in the binary, the tests, the fixtures or the docs. Use the reserved
  example domains.
- **The one exception is `lib/save/capture_policy.dart`**, the restricted-site
  capture policy: a static list of commercial content services this app refuses
  to save from. A refusal is the opposite of a catalogue — nothing on it makes a
  site work, and no page is detected, measured or handled differently because of
  it. It is the **only** file in `lib/` that may name a host;
  `test/repository_cleanliness_test.dart` allows it by name and fails the build
  if `restrictedCaptureDomains` or `restrictedCaptureHosts` is declared anywhere
  else. Never re-implement the matching, never copy the constants into a screen
  or the queue, and never add a rule that *enables* anything.
- `user_page_hints` holds only what a person taught by tapping an element. It is
  empty on a clean install; nothing seeds it, and nothing seeds `saved_sites`
  either.
- Detection uses standard HTML semantics and measurements only —
  `lib/save/content_detection.dart` is the whole surface.
- **An image that has not loaded is judged by the run it is in, not by its own
  box** (`LazyImageRuns`, `lib/save/image_candidates.dart`). Until a picture
  arrives it has no size of its own, so a page that reserves a small box for it
  reports one: a `min-width`/`min-height` placeholder, an unfired advert slot
  and an avatar are the same measurement, and read one at a time a column of
  unloaded panels is a column of icons. What separates them is arrangement —
  reading content arrives as a stacked run of same-width boxes, each starting
  where the one above it ended, while an advert rail is slots thousands of
  pixels apart and a related-items grid is several boxes sharing one vertical
  position. Geometry only: no hostname, no selector, no class name.
- That rule is **traversal's, never selection's**. It answers "keep waiting
  here", not "save this". An image still a placeholder when the page settles
  has nothing to store and `selectImageCandidates` rejects it exactly as
  before, so the traversal set stays a superset of the selected one.

### Some sites are never saved from

- **Browsing is never restricted; only capture is.** On a restricted host the
  save control is *absent* — not disabled, not a warning — and back, forward,
  reload, the address bar and sign-in all behave normally.
- **Enforcement is never UI-only.** Every boundary asks the policy for itself:
  direct start, enqueue, the queue pump, resume, retry, multi-entry
  continuation, top-level redirects, update checking, discovered-entry
  recording, and the save engine before it probes and again before it commits.
  A hidden button is not enforcement.
- **The policy judges pages, never assets.** It applies to the page or document
  being captured — the Browser's URL, a task's source URL, a landed URL after a
  top-level redirect, the manifest's `sourceUrl`. It does **not** apply to an
  image `src`, a responsive candidate, a CSS background, a document's inline
  image, the CDN delivering any of them, or an asset request's own redirects.
  Ordinary sites serve pictures from commercial-platform CDNs, and testing
  those marked permitted entries `partial` for a reason unrelated to them.
  `AssetFetcher` must never import `capture_policy.dart` and is never the
  authoritative boundary; the page is judged before a staging directory exists,
  so a refused page never reaches a download. The image-only MIME allow-list
  there is a **separate** rule and stays.
- A refused task becomes a terminal `failed` row carrying
  `StopReason.captureRestrictedForSite`. It is never silently deleted, never
  auto-retried, and never creates a partial entry. The policy prevents new
  capture; it never deletes a collection, an entry, a file or a reading
  position.
- The user-facing sentence is `kCaptureRestrictedMessage` and nothing else. It
  states what the app does — never what the user was trying to do.

### Saving is explicit and bounded

- **The default is one page.** `SaveScope.currentPageOnly` is preselected, and
  every path to the queue names its scope, so nothing inherits a default about
  how much of someone else's site to touch.
- `SaveLimits.forScope` is the only way to build limits and cannot produce an
  unbounded run. There is **no open-ended scope**: a multi-entry save is a
  number the user typed, so every ceiling is one they chose and can see. Do not
  reintroduce a range whose real bound lives in `SaveConfig`.
- Show what will happen *before* saving more than one page: which Collection,
  how many Entries the library can actually name an address for, that a short
  plan is short, and that nothing starts until Start. The count is planned
  against rows the library already holds — `SaveScopePlanner` opens no page —
  and finding more Entries is the update check, which is its own visible,
  bounded, cancellable act ([../docs/V2_SAVE_FLOW.md](../docs/V2_SAVE_FLOW.md) §4).
- Nothing saves in the background. Queued work waits for an explicit Start, and
  that authorisation is never persisted.

### The save flow

The matrix is [../docs/V2_SAVE_FLOW.md](../docs/V2_SAVE_FLOW.md);
`lib/features/v2_save_flow.dart`, `lib/recognition/adopt.dart` and
`lib/save/save_scope.dart` implement it. What survives as rules:

- What the page *is* comes from `readPageShape`; **which Collection it belongs
  to is the user's answer** (V2-D45), never a title match. A Collection is not
  a claim that the content is a series — nothing branches on whether a page
  looks episodic (V2-D44). Entries held outside a Collection stay first-class
  everywhere (I7).
- A page the library does not hold yet is asked **one** question — which
  Collection is this — and is never offered a loose save (V2-D69). Starting a
  Collection is the picker, then **one** sheet (V2-D57): the picker is first,
  because the Collections already held must be visible before another begins.
- **The save sheet asks everything** (V2-D62): one identity line, the range
  block (`library_ui/save_scope_section.dart`), the capture line and the
  launch, in that order, on one surface. No scope sheet after it, no
  *Download this entry* / *Download entries…* pair; the picker stays the only
  modal on the unknown-site path. Two ranges, not three.
- **A count means captures, not discoveries** (V2-D51). *The next N from here*
  is **one sequential journey** (`lib/save/capture_journey.dart`, V2-D56): the
  entry in front of the user is captured first, the next is found only when the
  one before it is on the device, each page is opened once, and stopping the
  download stops the traversal. Never reintroduce a phase that resolves the
  range before anything is captured.
- A Collection remembers what it is normally saved as, and the page still
  decides whether that is possible (V2-D53). That fallback is resolved at the
  **capture seam** (`EntryCaptureService.capture`, V2-D58) so it applies
  wherever a capture starts; never re-implement it where a queue row is
  written. The sheet shows **one line** (`Capture · Images only ⌄`, V2-D60)
  whose row opens the full block inline — never a second modal.
- **Starting or queueing a save with the proposed mode is what answers it**
  (V2-D61): opening the sheet writes nothing, an answer already given changes
  only by a tap, and *Ask each time* is stored as a value so the next save
  cannot undo it. Removing a Collection forgets it; archiving keeps it.
- **The sheet's own probe never vetoes a remembered mode on an image count**
  (V2-D65): it measures a page that has not been scrolled, where "not enough
  images" means "not yet". Only `noReadableText` is a fact at that point.

### Reading, progress and moving forward

- Reading state is writable only through `lib/data/reading_state_repository.dart`;
  no other code may reach a reading column. A completed entry is 100% read,
  enforced on write and again on display.
- Reading an Entry at its Source records a `Measurement` scoped to that Source;
  reading an OfflineCopy keeps its anchor. Neither needs the other, and neither
  is a download (V2-D54).
- **A fraction is of the reading, not of the page**: where the page's own
  geometry establishes a band of stacked content images (`imageContentBand` —
  the same candidate filter capture uses, plus a single-column and a density
  check, never a selector or a host), the fraction is measured against that
  band, so reaching the last panel is 100% however far the site carries on with
  comments below it. A page whose band cannot be established honestly falls
  back to the whole document.
- **A scroll a machine performed is never a reading**: capture leaves the page
  at the bottom, so the meter is sealed when an operation takes the Browser and
  unsealed only when the user scrolls it themselves. The app root is the one
  place that can tell those apart (`lib/app.dart`), fed by the WebView's own
  scroll callback.
- **Reading on to the next Entry corroborates completion, it never establishes
  it** (`lib/reading_v2/source_completion.dart`): the Entry left behind is
  marked read only when the move is forward by the Collection's own order —
  asked of `NextEntryResolver`, never re-derived — *and* the reading reached
  `CompletionPolicy`'s threshold *and* it was read at a natural pace
  (`NaturalPacePolicy`: a dwell floor, a per-viewport floor, real scrolling).
  A fast tap through writes nothing.
- **Moving forward inside a Collection is what frees a downloaded copy**
  (`lib/reading_v2/forward_transition.dart`, V2-D59), by a rule asked once per
  Collection (*Remove after finishing* · *Keep downloaded*) that is
  **device-local**, in `local_settings`, because it is a decision about these
  bytes on this device. It is the one Collection preference that stays local:
  what a Collection is normally *saved* as and what order its Entries are
  *drawn* in are answers about the work and are synced columns (V2-D73).
  Three decisions stay apart — did you finish it, where are you going, what
  happens to its files — and **nothing is freed until the destination has
  genuinely opened**. There is no Undo (V2-D33). The plan is held by the
  service rather than the reader, because `V2ReaderRoute` replaces itself to
  move.
- ***Next entry* is a request, never a destination** (`lib/reading_v2/next_entry.dart`,
  V2-D66): it is resolved when the reader asks, in four cases and no fifth — it
  opens if this device holds it, it is offered **at its Source** if the library
  has it and this device does not, and where the library knows of no next Entry
  the offer is **Check for new entries**, because that is a fact about the
  library and never about the work. The bottom-bar control, the end of a
  finished Entry and the pull-up from the bottom edge
  (`lib/features/pull_up_next.dart`) are three ways of making one request; what
  a *move* means is still `ForwardTransitionService`'s. Nothing there
  reimplements opening a source or checking a Collection, and a source URL is
  read from a Location, never constructed.
- **A tap on an Entry row opens the Entry** (`lib/library_ui/entry_open.dart`,
  V2-D71): the copy on this device where there is one, its own site where there
  is not, and a question about which site only where the Collection has several
  Sources and no preferred one. The actions sheet is the three-dot control's
  alone — it holds an Entry's settings and its two removals, and a reading
  gesture never reaches it.
- Inside a Collection a row leads with the Entry's **position**, because the
  work is named above the list; across the library it names itself. The stored
  title is never modified, and *Entry details* is where the record is read
  (V2-D55).

### Two kinds of network work, and only one of them is explicit

- **Content-affecting source automation stays explicit.** Capture, source
  traversal, update checking and anything that drives the browser remain
  user-started, visible, bounded and cancellable. Every ceiling is a number the
  user chose and can see. Nothing about this weakens.
- **Lightweight metadata synchronisation is automatic.** Synchronising library
  organisation and reading state is opportunistic and mostly invisible: it
  fetches no page, drives no browser and stores no content. It runs when the app
  has a reasonable execution opportunity, resumes after connectivity returns and
  is safe to interrupt at any point. It is **not** a promise of permanent
  background execution — no mobile platform offers one (V2-D20,
  [../docs/PRODUCT.md](../docs/PRODUCT.md) §6).

### The app stops; it never works around

- Add stopping conditions to `lib/save/stop_conditions.dart` as a named
  `StopReason`. Never add a retry with different headers, an alternate-URL
  attempt, cookie manipulation, or a rate-limit wait-out.
- Structural signals stand alone; **phrase hints never do**. A footer that says
  "subscribe to continue" is not a paywall.
- "Finished" and "the site stopped us" are different outcomes and live in
  different column values.
- **A refused asset is an answer, not a bad moment.** A host that replies 401,
  402, 403, 407, 429 or 451, or that serves a *web page* where an image was
  asked for, has settled the question; `AssetFetcher` classifies that as
  `AssetFailure.refused`, stops retrying it, and tries only the page's own
  session — the one context that legitimately has whatever the user established
  by browsing there. Retrying a refusal is the "retry with different headers"
  rule one step removed.
- **A reading whose images were refused does not become a partial entry.**
  When more assets were refused than were stored, the capture stops with
  `StopReason.assetsRefusedBySource`, commits nothing and says one sentence
  about what the site does. A refusal that did *not* prevent the entry from
  being saved is an ordinary broken asset and still yields a `partial` — the
  comparison is against what was actually stored, so one dead panel among a
  hundred good ones stays what it is.
- **Some sites will not hand over their files, and no amount of asking changes
  it.** A host that is cross-origin to the page, serves no
  `Access-Control-Allow-Origin`, and answers a separate client with a
  human-verification interstitial has no path to its *files*: `<img>` renders
  the picture while script may read nothing, and the direct request is
  challenged. Measured, not assumed — the reasoning is in
  `lib/save/asset_fetcher.dart`. Getting past **that** would mean completing a
  verification check on the user's behalf or defeating the browser's
  cross-origin rules, and neither is something this app does.
- **A refusal is remembered, and it is remembered about the *origin*.**
  `asset_origins` (device-local, `lib/data/asset_origin_repository.dart`) holds
  what this device has watched a host do, keyed by `scheme://host[:port]`.
  Not the Source and not the Collection: a real site served its own furniture
  perfectly from its page host while every panel came from a separate CDN that
  refused all of them, and a Source is one work — scoping it there would
  re-learn the same refusal once per work on the same site. Learned, never
  seeded, and **never synced**.
- **Nothing about that memory is permanent, and it is not a site list.** One
  refused reading earns `suspected` and changes nothing; two *separate
  Locations* earn `refusing`, which costs the next reading exactly one request
  instead of one per panel. A verdict goes stale after `kVerdictFreshness` and
  the full path is taken again from scratch. The only thing a verdict ever
  changes is how many times the app asks again before believing an answer it
  already has.
- **A gate in front of a CDN is not all-or-nothing.** Measured on the real
  site: with a verdict in place, the single probe was *served* and nine of the
  next thirteen were still refused. So a served file never clears a verdict on
  its own — only a capture that actually completes does.
- **Sites shard their assets, and a verdict speaks for the siblings** — but
  **only inside a domain the page itself belongs to**, which is what keeps it
  from reaching across a public suffix (`a.co.uk`'s parent label is `co.uk`,
  and this app ships no public-suffix list). `SaveEngine._siblingScopeFor`
  applies that constraint; `verdictUnderDomain` only answers what it is asked.

### Rendered capture is the fallback, and only ever the fallback

`lib/save/rendered_capture.dart` keeps a reading the browser *drew*, when its
files cannot be had.

- **Original bytes stay primary, everywhere they are possible.** A rendering is
  reached from the refusal points in `SaveEngine` and from nowhere else, so by
  the time it runs the primary path has not been skipped — it has been
  exhausted. A Source that serves its files keeps getting them, byte for byte.
- **Silence is not consent, and the question is asked once per Source.**
  `SaveEngine.renderedConsent` is null by default, and null means *never*: an
  engine nobody gave an answerer to stops with its named reason.
  `RenderedFallbackGate` (`save/rendered_consent.dart`) obeys a stored answer,
  asks when there is none, and treats *no way to ask* as no. Both answers are
  recorded, because a declined Source must not be asked again on its next
  Entry; the answer is keyed by the Source (by host for a page no Source has
  adopted yet), device-local beside the other per-Collection answers. The
  question is put only after the band is established, so it is never asked
  about a page nothing could have been kept from.
- **It bypasses nothing.** The compositor is asked for the pixels it has
  already put on the screen the person is looking at, which is what the
  device's own screenshot key does. No protected file is obtained and no check
  is answered.
- **It says what it is.** `manifest.renderedFromPage` is durable and travels
  through `PageCaptureOutcome`; the byte-for-byte rule still governs
  `imageSequence` packages of *originals*, and a rendering is never recorded as
  one.
- **The page's own geometry decides what is kept**, not a selector and not a
  host: `imageContentBand` — the same band reading progress measures against. A
  page whose band cannot be established is not rendered at all.
- **Bounded memory is the design, not a tuning knob.** One tile exists at a
  time, written to staging and released before the next scroll; tiles are asked
  for at about the width of the pictures they render rather than at the
  screen's scale; and the platform's JPEG encoder is used so a bitmap never
  enters the Dart heap. The naive order — settle the page, then capture it at
  full scale — was measured killing the process part-way down a real reading.
  `dart:ui` can only encode PNG, so nothing here re-encodes in Dart.

### Capture modes

- **Three separate concepts, never merged**: `ContentKind` (what the page is),
  `CaptureMode` (what the save was asked for), `ArtifactFormat` (what the
  package holds). Only `ArtifactFormat` decides how an entry is read, and
  `setEntryContentKind` deliberately cannot reach it.
- Modes are `imageSequence` · `textOnly` · `textAndImages`. **There is no video
  mode** — the save sheet is built from that enum, so an unhonourable value
  would become a button that lies.
- A mode is only ever offered when `CaptureCapabilities` says the engine can
  carry it out. A collection preference proposes; the page disposes.
- Text extraction splits the same way detection does: the bridge measures and
  flags, `save/document_extraction.dart` decides. Keep the judgement in Dart so
  it stays testable against literal fixtures.
- Documents are stored as typed blocks in `document.json`, never as HTML. No
  script, stylesheet, iframe or remote reference may enter a saved package.

### Media

Audio and video are never saved. `AssetFetcher` accepts image bytes only, verified
by magic number rather than `Content-Type`. `PageMediaSignals` carries **geometry
only** — never a media URL — so a video-dominant page can be classified honestly
and refused. Do not add video URL extraction, HLS/DASH, interception or playback.

### Storage and privacy

- Original image bytes are stored byte-for-byte; no format conversion, no quality
  profiles. Stored extensions come from sniffed MIME.
- App-private storage only. No export to Photos, Gallery, Downloads or shared
  storage. No new permission without a visible, justified feature.
- No analytics, crash-reporting or advertising SDK. Nothing is sent to the
  developer. Do not add a dependency that changes this.
- Never claim "no tracking", "completely private" or "everything stays on device"
  — the embedded browser contacts the sites the user visits.

### Structural invariants

- **Cancelling preserves the row; dismissing deletes it.** A cancel moves a task
  to the existing `cancelled` state — there is no sixth state — and *Remove from
  Activity* deletes a row that is already terminal, refusing anything live. A
  waiting row is removed on a tap with an **Undo** that restores its
  `orderIndex`; a running one gets a dialog naming what survives, and its
  cancellation is written the moment it is asked for, because `restore()` demotes
  a killed `running` row back to `queued`. Both the pump's claim and every cancel
  go through `SaveQueueRepository.updateIfState` — one conditional SQL `UPDATE` —
  so exactly one wins and the loser is told; a pump that loses the claim skips
  the row and carries on. Never offer a stop that does not stop: stopping is
  cooperative everywhere — the runner polls the row's state between safe points —
  so the wording is "at the next safe point".
- The V2 save queue is `save_queue`; `save_runs` is deliberately absent — see the
  header of `lib/data/schema.dart`.
- Removing offline files is never deleting an entry: the copy's own row is
  marked inactive and nothing on the Entry is touched. The Entry whose copy is
  open in the reader is never eligible for a bulk sweep
  (`CleanupService.openInReader`) — it is skipped and kept, never failed.
  Archiving is never deleting a collection either: it writes `lifecycle` and
  `archived_at` and nothing else. Neither may be offered as a way to delete.
- **Permanent deletion goes through the V2 repositories, whole** (V2-D42).
  Removing a Collection cancels its queued work, deletes its Entries and their
  Locations, and lets the OfflineCopy cascade (I14) take the packages with them.
  Never delete a collection row on its own.
- `entries.source_url` is durable metadata — every writer names its columns.
- `entries.collection_id` is nullable. A standalone entry is a first-class
  library item; never wrap one in a collection of one.
- Only manual navigation enters browsing history, enforced twice. A completed,
  user-initiated navigation updates the library only through a followed
  Collection or a standalone Entry; everything else becomes device-local
  history (V2-D40).
- **Seeing what the device is doing is never gated** — a run says which entry it
  is on and how many images of it, a finished run says what it came to with
  *Retry failed* and *Details*, a Collection carries its last check state, and
  *Check all collections* stays reachable. The parity contract pins this, and it
  was lost once already.
- `AppPalette` is the only source of colour; `test/theme_palette_test.dart` scans
  `lib/` and fails on a literal `Color(0x…)`.
- Header actions use `HeaderIconButton` / `kHeaderActionSize` (40) /
  `kHeaderIconSize` (22) / `kHeaderIconColor`.
- **drift trap:** `insertOnConflictUpdate` treats a null field as *absent*, so
  anything that must be cleared needs its own narrow writer.
- The app mark is generated by `tool/brand/generate_brand_assets.swift`, never
  hand-edited. Its colours are `AppPalette`'s.
- Destructive developer tools are `kInternalBuild`-only at the settings entry,
  the route registration and the screen — all three, every time. `kInternalBuild`
  is `kDebugMode || bool.fromEnvironment('SCROLLARY_INTERNAL_BUILD')`
  (`lib/capability/internal_build.dart`), reached through
  `developerToolsAvailable` in `lib/core/local_reset.dart`. It is a compile-time
  constant, so a build that passes no define folds it to `false` and the
  tree-shaker removes the screen, the route and the entitlement override
  entirely. **A Store build must never pass that define**, and the same gate
  carries the internal entitlement override, so passing it also unlocks Pro.
  Profile and release builds are where device performance, energy and
  accessibility work happens, and that work needs these tools
  ([../docs/FOREGROUND_MULTITASKING.md](../docs/FOREGROUND_MULTITASKING.md) §10.4).

### Free and Pro — one boundary, and it is not the operation

**Update checking is Free. Foreground multitasking is Pro.**

- **Never gate an operation.** A Collection check, the Library-wide check, the
  Entries either discovers, saving and capture on the ordinary flows, the
  library, the offline reader, reading progress, archive, cleanup, deletion,
  retry and recovery are **Free, all of them**. Nothing about *what* the app
  will do for a user is smaller without Pro. (The one wired gate is the sync
  network drain — `SyncComposition.resolve`, V2-D37.)
- **Gate one thing only: the execution experience.** Pro buys a
  Browser-dependent phase continuing while the user reads another Entry or uses
  the Library, instead of holding until they return to the Browser. That is the
  entire product difference.
- **Never degrade the Free flow to create Pro value.** A Free operation is not
  cancelled, truncated, slowed or capped in what it may discover, and leaving
  the Browser pauses and resumes as it always has. If a change makes Free worse
  in order to make Pro attractive, it is wrong regardless of how it is worded.
- **Say "foreground multitasking", never "background".** Nothing runs once the
  app is not in front, and the rule that nothing saves in the background is
  unchanged.
- Two build guards keep this honest and **must not be weakened to ship a
  paywall**: `test/library_check_test.dart` fails on gating, counter or purchase
  vocabulary anywhere in `lib/` outside `lib/capability/` and three files that
  only name it; `test/entitlement_test.dart` fails if a reading or cleanup
  surface imports `lib/capability/` at all.
- Specified in
  [../docs/FOREGROUND_MULTITASKING.md](../docs/FOREGROUND_MULTITASKING.md)
  §10.0 and carried as an invariant in `ARCHITECTURE.md` §9. An older proposal
  to sell update checking survives in `MONETIZATION_STRATEGY.md` §8.3, **marked
  superseded** — it is history, not a requirement.

### The database has history, and so does the manifest

The drift `schemaVersion` in `lib/data/schema.dart` has an `onCreate` *and* an
`onUpgrade` (V2-D75). It was 1 with no upgrade path for as long as the only
databases were development ones that could be reset by hand; then schema
additions shipped against libraries somebody was already using, the version
stayed at 1, and every read of `collections` threw `Null check operator used on
a null value` on a column that was not there.

**A schema change is a version bump and a step in `_reconcileToDeclaredSchema`,
in the same commit.** That step *reconciles* — it asks the file what it already
has and adds only what is missing — so it is correct for a database of any older
shape and safe to run twice. Still no schema dump and no step verifier:
additions are checked against `PRAGMA table_info` and `sqlite_master`, and
`test/data/schema_migration_test.dart` opens a file in the older shape and
proves the library survives.

**Structure only.** A step adds what is missing and touches no row: getting an
existing library open is not the place to settle what should happen to rows an
older rule wrote. `sources` accordingly still carries a version-1
`UNIQUE (collection_id, host, path_key)` and lacks `CHECK (host = lower(host))`
— neither rejects a row the current rules accept, and neither is worth
rebuilding a table three foreign keys point at.

`manifest.json` is **version 2** and *is* versioned, because those files are
durable user data on devices today. A version-1 manifest has no `artifact`
field and is read as an image sequence — the only thing the app could produce
when it wrote one. Never rewrite a stored manifest in place, and never read an
unrecognised `artifact` as a known one: it resolves to `ArtifactFormat.unknown`
and the reader says so. The storage survey (`CleanupService`) lists a package
with no `offline_copies` row as an orphan rather than rebuilding a row for it.

## Verification

```bash
dart format lib test integration_test tool
flutter analyze
flutter test
dart run build_runner build          # after touching lib/data/schema.dart
```

Deterministic tests are network-free and gate everything. **Never make
`flutter test` or CI depend on a network.** Fixture integration suites run
against the in-process server in `tool/fixture/` and need a simulator, emulator
or device:

```bash
flutter test integration_test/<name>_test.dart -d <udid>
```

`save_flow`, `offline_read`, `reading_flow`, `update_check`, `user_assist`,
`text_capture`, `capture_integrity`, `reading_chrome`, `next_entries` (the
typed count end to end — and *not a byte captured until Start*) and
`stale_state_scope` (state belongs to the page it is shown for; turns on timing
only a real WKWebView produces).

Run when the thing they cover changes rather than routinely: `occlusion_gate`
(covered/unpainted rendering — the premise foreground multitasking rests on),
`foreground_multitasking`, `activity_indicator`.

`integration_test/device_matrix_test.dart` is the hardware matrix — the check
race, terminal-state cleanup, duplicate protection, a covered save, a bounded
multi-entry run and a soak, each under a watchdog that reports a harness stall
as a harness verdict rather than as evidence about the product
(`integration_test/support/device_harness.dart`). Real pages are supplied at run
time and never compiled in; with no `LIVE_ENTRY_*` the live scenarios skip
themselves and say so:

```bash
BUILD_ID=$(git rev-parse --short HEAD) \
flutter test integration_test/device_matrix_test.dart -d <udid> \
  --dart-define=BUILD_ID=$BUILD_ID \
  --dart-define=LIVE_ENTRY_A=<a real entry url> \
  --dart-define=LIVE_ENTRY_B=<a real entry url on another source> \
  --dart-define=SOAK_ROUNDS=6
```

Results belong in `../docs/FOREGROUND_MULTITASKING_PLAN.md` §6.

`tool/e2e/run.sh` and `test/e2e/` run the sync suite against a real Go service
on a real PostgreSQL, over the app's real `HttpSyncTransport`, and assert the
no-outbound invariant.

### Live-site verification

Bounded and explicit, and **no hostname is ever written into the repository** —
`test/repository_cleanliness_test.dart` fails the build on one. Every address is
supplied at run time and every case skips itself, saying so, when the defines
are absent:

```bash
flutter test integration_test/live_next_control_test.dart -d <udid> \
  --dart-define=LIVE_ENTRY_A=<a real entry url, part of a sequence> \
  --dart-define=LIVE_NEXT_LABEL=<the visible label of its next control>

flutter test integration_test/live_rendered_fallback_test.dart -d <udid> \
  --dart-define=LIVE_REFUSING_A=<an entry whose asset host refuses> \
  --dart-define=LIVE_REFUSING_B=<another entry on that same host> \
  --dart-define=LIVE_REFUSING_C=<a third, to consume the learned verdict> \
  --dart-define=LIVE_SERVING=<an entry whose assets download normally>
```

The developer-owned demo site ([../docs/DEMO_CONTENT.md](../docs/DEMO_CONTENT.md))
is not hosted yet and has no test file; when it exists, a suite takes its origin
from `--dart-define=DEMO_BASE_URL=…`. There is deliberately no matrix of
third-party sites — if a change needs a real site to prove it, add the case to
the demo site.

Rules: deterministic tests first, always. Never commit downloaded third-party
content. Report each live run as **PASSED · FAILED · BLOCKED · SKIPPED
(unreachable)** — an unreachable site is never a passing verification. Keep each
run to the smallest operation that answers the question.
