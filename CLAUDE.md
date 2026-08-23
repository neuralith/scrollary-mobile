# Scrollary — project instructions

A personal reading library for web-based reading content, iOS-first and
Android-compatible: embedded browser + a library of Collections and Entries +
optional offline copies.

Read [docs/TERMINOLOGY.md](docs/TERMINOLOGY.md) before writing any code. The
product definition is [docs/PRODUCT.md](docs/PRODUCT.md); the as-built model is
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); why a decision was made is
[docs/DECISIONS.md](docs/DECISIONS.md); store positioning is
[docs/STORE_PACKAGE.md](docs/STORE_PACKAGE.md); the policy reasoning behind the
safety rules is [docs/STORE_POLICY_MAP.md](docs/STORE_POLICY_MAP.md).

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

### V2 replaces V1; it is composed and running

The V2 direction is a **recognition-driven, cross-platform reading library**: you
read, Scrollary recognises what it is, and your library stays current across your
devices. Downloading becomes a per-device capability of an Entry. Folders are
user organisation; a Collection has several Sources; an Entry has Locations.

Specified in [docs/PRODUCT.md](docs/PRODUCT.md),
[docs/V2_ARCHITECTURE.md](docs/V2_ARCHITECTURE.md) and
[docs/V2_SYNC.md](docs/V2_SYNC.md); sequenced for parallel worktrees in
[docs/V2_ROADMAP.md](docs/V2_ROADMAP.md); deferred production work in
[docs/V2_PRODUCTIZATION.md](docs/V2_PRODUCTIZATION.md); every decision recorded
in [docs/DECISIONS.md](docs/DECISIONS.md).

**What is built, merged and composed on `master`, by layer:**

- **Backend** (`../scrollary-backend/`, B1–B11) — `/healthz`, `/version`,
  `/identity/arbitrate`, `/mutations`, `/changes?cursor=`,
  `/entries/{id}/placement`, `/download-requests` (+ `/claim`, `/resolve`), and
  the dev `X-Scrollary-Library` header. Both stores are conformance-identical;
  revisions are allocated inside the write transaction; the feed reads from one
  snapshot; measurement tombstones are scoped by `source_id`.
- **Mobile domain and persistence** (`lib/domain`, `lib/data`) — the fresh
  schema, repositories, outbox and recognition index.
- **Recognition** (`lib/recognition`) — the pipeline, source-scoped discovery,
  the preferred-source check, placement, history and promotion.
- **Capture and offline read** (`lib/save`, `lib/reading_v2`) — capture
  retargeted to `(Entry, Location)`, the V2 save queue (`save_queue`;
  `save_runs` is deliberately absent — see the header of
  `lib/data/schema.dart`), and offline read through `OfflineCopy`. The two
  reviewed port seams are recorded in
  [docs/V2_PORT_CHECKLIST.md](docs/V2_PORT_CHECKLIST.md) §17.
- **The save flow** (`lib/features/v2_save_flow.dart`, `lib/recognition/adopt.dart`,
  `lib/save/save_scope.dart`) — a page becomes library through the matrix in
  [docs/V2_SAVE_FLOW.md](docs/V2_SAVE_FLOW.md): what the page *is* comes from
  `readPageShape`, which Collection it belongs to is the **user's answer**
  (V2-D45) and never a title match, and how much to download is the typed
  count V1 asked for, on the same `SaveLimits` bound (V2-D46). A page that
  belongs to serialized content is never written as a loose Entry without
  being asked (V2-D44); standalone stays first-class and stays chosen.
- **Library UX** (`lib/library_ui`, D1–D7) — the one-page Library (root
  Collections listed directly, Folders as collapsible sections, Continue
  Reading and the Settings/Activity doors in its header — V2-D43), folder
  actions, collection detail
  (one list, with a NEEDS PLACEMENT section), sources, entry actions including
  queue wiring, the placement dialog, the sync status section.
- **Sync** (`lib/sync`, G1–G7) — push, pull, identity canonicalisation, merge,
  session, scheduler, retry, status, download-intent consumption, device
  label, transport.
- **Composition** (`lib/features/v2_composition.dart`, `lib/app.dart`) — the
  V2 screens above are the running app. The sync stack is wired up with a Pro
  gate on the network drain (`SyncComposition.resolve`, docs/DECISIONS.md
  V2-D37) and the scheduler's lifecycle hooks called from app launch,
  resume, pause, local mutation and capability change; placement submits
  locally when no service is reachable and over the network when one is
  (V2-D41); a completed, user-initiated navigation updates the library only
  through a followed Collection or a standalone Entry, everything else
  becomes device-local history (V2-D40). The V1 library screens, queue,
  update checker and `CollectionDeletionService` are retired — `lib/library/`
  holds only the domain helpers V2 still calls (`entry_labels.dart`,
  `collection_identity.dart`, `collection_repository.dart`,
  `content_shape.dart`, `library_sort.dart`), not a screen.
- **Real-system end-to-end harness** (Lane H, H2–H4) — `tool/e2e/run.sh` and
  `test/e2e/` run the suite against a real Go service on a real PostgreSQL,
  over the app's real `HttpSyncTransport`, and assert the no-outbound
  invariant.

**Do not describe the V1 shell as the running app.** It is not — the V2
screens are what `lib/app.dart` routes to, and there is no V1 fallback left to
route to instead.

Rules that still bind: the port checklist
([docs/V2_PORT_CHECKLIST.md](docs/V2_PORT_CHECKLIST.md)) governs any further
change to a ported file; the shared contract (`contracts/`) is frozen and
changes only through `contracts/README.md`'s protocol; the guard tests in
`test/` gate every change in either half.

Three things future agents get wrong here:

- **V2 replaces the V1 domain, not the V1 device knowledge.** A defined set of
  components is ported verbatim — render guards, image enumeration, lazy
  settling, the decode budget, FileStore, manifest, document, capture policy,
  detection, extraction, stop conditions, the asset fetcher, both readers.
  Change their call sites, never their internals
  ([docs/V2_ROADMAP.md](docs/V2_ROADMAP.md) §9).
- **There is no V1 → V2 migration.** Nothing has shipped, so V2 starts from a
  fresh schema and development databases are reset by hand (V2-D26). The
  version-1 schema rule above still applies to V1 for as long as it runs.
- **An Entry is not a URL.** That was V1's axiom. `url_key` becomes Location
  identity and `host + collection_key` becomes Source identity — same
  algorithms, one level down (V2-D15).

## Standing rules

### Terminology — one model, one label system

- The canonical model is **Library / Collection / Entry / Page or Section**.
  `Collection` and `Entry` are the only nouns in code.
- User-facing nouns come from `lib/library/entry_labels.dart` and **nowhere
  else**. A screen that types its own noun is how one app calls the same thing an
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

- **The default is one page.** `SaveScope.currentPageOnly` is preselected in
  the scope sheet, and every path to the queue names its scope, so nothing
  inherits a default about how much of someone else's site to touch.
- `SaveLimits.forScope` is the only way to build limits and cannot produce an
  unbounded run. There is **no open-ended scope**: a multi-entry save is a
  number the user typed, so every ceiling is one they chose and can see. Do not
  reintroduce a range whose real bound lives in `SaveConfig`.
- Show what will happen *before* saving more than one page: which Collection,
  how many Entries the library can actually name an address for, that a short
  plan is short, and that nothing starts until Start. In V2 the count is
  planned against rows the library already holds — `SaveScopePlanner` opens no
  page — and finding more Entries is the update check, which is its own
  visible, bounded, cancellable act (docs/V2_SAVE_FLOW.md §4).
- Nothing saves in the background. Queued work waits for an explicit Start, and
  that authorisation is never persisted.

### Two kinds of network work, and only one of them is explicit

This rule was once written as *"every network operation is user-started, visible
and cancellable."* It is now **two rules**, because collapsing them would forbid
V2's metadata sync for reasons that only apply to capture.

- **Content-affecting source automation stays explicit.** Capture, source
  traversal, update checking and anything that drives the browser remain
  user-started, visible, bounded and cancellable. Every ceiling is a number the
  user chose and can see. Nothing about this weakens.
- **Lightweight metadata synchronisation is automatic.** Synchronising library
  organisation and reading state is opportunistic and mostly invisible: it
  fetches no page, drives no browser and stores no content. It runs when the app
  has a reasonable execution opportunity, resumes after connectivity returns and
  is safe to interrupt at any point. It is **not** a promise of permanent
  background execution — no mobile platform offers one. See
  [docs/DECISIONS.md](docs/DECISIONS.md) V2-D20 and
  [docs/PRODUCT.md](docs/PRODUCT.md) §6.

### The app stops; it never works around

- Add stopping conditions to `lib/save/stop_conditions.dart` as a named
  `StopReason`. Never add a retry with different headers, an alternate-URL
  attempt, cookie manipulation, or a rate-limit wait-out.
- Structural signals stand alone; **phrase hints never do**. A footer that says
  "subscribe to continue" is not a paywall.
- "Finished" and "the site stopped us" are different outcomes and live in
  different column values.

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
  go through `updateQueueTaskIfState` — one conditional SQL `UPDATE` — so exactly
  one wins and the loser is told; a pump that loses the claim skips the row and
  carries on. Never offer a stop that does not stop: `removeOfflineNow` takes
  `shouldContinue` and is asked between entries, and stopping is cooperative
  everywhere, so the wording is "at the next safe point".

- Reading state is writable only from `lib/reading/`; `writeEntryReading` is the
  only DAO method that can reach a reading column.
- A completed entry is 100% read, enforced on write and again on display.
- Removing offline files is never deleting an entry: only `content_path`,
  `byte_size` and `offline_removed_at` are written. Archiving is never deleting
  a collection either: it writes `lifecycle` and `archived_at` and nothing else.
  Neither may be offered as a way to delete.
- **Permanent deletion is `CollectionDeletionService.delete`, whole.** It
  cancels the collection's queue work (by collection id, and by address for a
  save that carries none), refuses while an entry is open in the reader or a
  save is still on it, moves every owned directory into `tmp/deleting-<id>`
  **before** any row goes, then deletes the queue rows, the interrupted runs,
  the entries and the collection in one transaction, then discards the staged
  tree. The file move is not an optimisation: rows first would leave packages
  under `library/` for the storage survey to report as orphans.
  `deleteCollection` / `deleteEntriesForCollection` /
  `deleteQueueTasksForCollection` / `allRuns` belong to that service and have no
  other caller — never delete the collection row on its own. Rationale and the
  full inventory of what goes and what stays: ARCHITECTURE.md §8.2.
- `entries.source_url` is durable metadata — every writer names its columns.
- `entries.collection_id` is nullable. A standalone entry is a first-class
  library item; never wrap one in a collection of one.
- Only manual navigation enters browsing history, enforced twice.
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
  The rule was widened from `kDebugMode` deliberately: profile and release
  builds are where device performance, energy and accessibility work happens,
  and that work needs these tools — see docs/FOREGROUND_MULTITASKING.md §10.4.

### Free and Pro — one boundary, and it is not the operation

**Update checking is Free. Foreground multitasking is Pro.**

- **Never gate an operation.** A Collection check, the Library-wide check, the
  Entries either discovers, saving and capture on the ordinary flows, the
  library, the offline reader, reading progress, archive, cleanup, deletion,
  retry and recovery are **Free, all of them**. Nothing about *what* the app
  will do for a user is smaller without Pro.
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
- The boundary is specified in docs/FOREGROUND_MULTITASKING.md §10.0 and carried
  as an invariant in ARCHITECTURE.md §9. An older proposal to sell update
  checking survives in MONETIZATION_STRATEGY.md §8.3, **marked superseded** — it
  is history, not a requirement.

### The database has no history; the manifest does

`schemaVersion` is **1**, with an `onCreate` and no `onUpgrade`. Do not add a
migration branch, a schema dump, a step verifier or a data-copying routine. If the
schema needs to change after release, write a migration then.

`manifest.json` is **version 2** and *is* versioned, because those files are
durable user data that exists on devices today. A version-1 manifest has no
`artifact` field and is read as an image sequence — the only thing the app could
produce when it wrote one. Never rewrite a stored manifest in place, and never
read an unrecognised `artifact` as a known one: it resolves to
`ArtifactFormat.unknown` and the reader says so. The storage survey
(`CleanupService`) lists a package with no `offline_copies` row as an orphan
rather than rebuilding a row for it.

## Verification

```bash
dart format lib test integration_test tool
flutter analyze
flutter test
dart run build_runner build          # after touching lib/data/schema.dart
```

Deterministic tests are network-free and gate everything. Fixture integration
suites run against the in-process server in `tool/fixture/`, and need a
simulator, emulator or device:

```bash
flutter test integration_test/save_flow_test.dart          -d <udid>
flutter test integration_test/offline_read_test.dart       -d <udid>
flutter test integration_test/reading_flow_test.dart       -d <udid>
flutter test integration_test/update_check_test.dart       -d <udid>
flutter test integration_test/user_assist_test.dart        -d <udid>
flutter test integration_test/text_capture_test.dart       -d <udid>
flutter test integration_test/capture_integrity_test.dart  -d <udid>
```

Three more answer questions a widget test cannot, and are run when the thing
they cover changes rather than routinely:

```bash
# Covered/unpainted rendering — the premise foreground multitasking rests on
flutter test integration_test/occlusion_gate_test.dart          -d <udid>
# A save and a check running with another screen in front
flutter test integration_test/foreground_multitasking_test.dart -d <udid>
# Where the activity pill lands against real device insets
flutter test integration_test/activity_indicator_test.dart      -d <udid>
```

### Physical-device verification

`integration_test/device_matrix_test.dart` is the hardware matrix: the check
race, terminal-state cleanup, duplicate protection, a covered save, a bounded
multi-entry run and a soak, each under a watchdog that reports a harness stall
as a harness verdict rather than as evidence about the product
(`integration_test/support/device_harness.dart`). It replaced an earlier
`device_validation_test.dart`, which measured the right things with unbounded
waits and lost three device runs to it.

Real pages are supplied at run time and never compiled in; with no `LIVE_ENTRY_*`
the live scenarios skip themselves and say so:

```bash
BUILD_ID=$(git rev-parse --short HEAD) \
flutter test integration_test/device_matrix_test.dart -d <udid> \
  --dart-define=BUILD_ID=$BUILD_ID \
  --dart-define=LIVE_ENTRY_A=<a real entry url> \
  --dart-define=LIVE_ENTRY_B=<a real entry url on another source> \
  --dart-define=SOAK_ROUNDS=6
```

Results belong in docs/FOREGROUND_MULTITASKING_PLAN.md §6.

### Live-site verification

Bounded and explicit. Two forms, and they are not interchangeable:

- **The developer-owned demo site** — see [docs/DEMO_CONTENT.md](docs/DEMO_CONTENT.md).
  It is not hosted yet, and **there is no test file for it today**: the six
  `integration_test/live_*.dart` files that named third-party sites were deleted
  (TERMINOLOGY.md §3) and nothing replaced them. When the demo site exists, a
  suite for it takes its origin from `--dart-define=DEMO_BASE_URL=…`; never
  compile one in.
- **A real page, by hand, through the device matrix above.** `LIVE_ENTRY_A` /
  `LIVE_ENTRY_B` exist for the cases that only a real site can produce. No
  hostname is written into the repository — `test/repository_cleanliness_test.dart`
  fails the build on one.

Rules: deterministic tests first, always. Never make `flutter test` or CI depend
on a network. Never commit downloaded third-party content. Report each live run as
**PASSED · FAILED · BLOCKED · SKIPPED (unreachable)** — an unreachable site is
never a passing verification. Keep each run to the smallest operation that answers
the question.

There is deliberately no matrix of third-party sites. If a change needs a real
site to prove it, add the case to the demo site.
