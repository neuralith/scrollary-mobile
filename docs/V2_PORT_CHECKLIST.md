# V2 port-as-is checklist — task E1

The executed record of [V2_ROADMAP.md](./V2_ROADMAP.md) §9. One section per
inventoried component: where it lives, where it goes, what changed inside it
(the answer must be "none"), which tests carry it, which device-validated
assumptions it encodes, and which V2 lane consumes it.

**What "ported verbatim" means here.** The component's internals are frozen.
V2 work may change *call sites* — who constructs it, what identifiers it is
handed, where its output is written — and nothing else. A component that seems
to need an internal change is an open item on this list and a task with its own
review, never a side effect of a call-site edit.

Line counts are as of the base commit in the signing block. Test lists were
verified by reading each test file's import lines, not by filename. Suites
listed as *shared harness* import the component as part of a wider fixture
(most widget suites construct the full FileStore + database + browser stack);
the *dedicated* suites are the ones whose subject the component is.

---

## 1. Browser surface policy and render guards

- **Original files:** `lib/browser/browser_surface_policy.dart` (128 lines);
  the guard call sites in `lib/browser/browser_controller.dart` (1156 lines —
  `surfaceIsPainted`, `awaitPaintedSurface`), `lib/save/save_engine.dart`
  (1788 lines — `_waitForRenderedSurface`, the zero-viewport re-probe in the
  verify phase) and `lib/library/update_checker.dart` (1719 lines — the
  `awaitPaintedSurface` call before the first navigation, the
  `surfaceHoldReason` loop in `_navigateAndProbe`).
- **New location:** unchanged. `browser_surface_policy.dart` and the
  `lib/browser/**` hosts port in place. `update_checker.dart` itself retires
  after F3 + F4 (§10); the guard *pattern* it demonstrates — claim the owner,
  await the painted surface before the first navigation, hold on
  `surfaceHoldReason` before reading anything — is what Lane F's checker must
  reproduce, with `browser_surface_policy.dart` remaining the single authority
  for the rule.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/foreground_multitasking_test.dart`
  (policy truth table, `kPageHiddenGrace` bounding, the born-hidden regression
  from PLAN §7 A7), `test/hidden_webview_test.dart` (an offstage surface's
  real-DOM/zero-viewport answers never reach disk);
  integration — `integration_test/occlusion_gate_test.dart` (the
  covered-rendering premise), `integration_test/foreground_multitasking_test.dart`,
  `integration_test/device_matrix_test.dart` (covered save on hardware).
- **Device assumptions:** `requestAnimationFrame` is the only honest
  covered-rendering signal — an unpainted WebView "reports a full viewport,
  accepts programmatic scrolling, and completes a save" while rAF stops (iOS)
  or throttles to about a fifth of display rate (Android)
  (FOREGROUND_MULTITASKING_PLAN.md §7 A1). `document.visibilityState` is a
  hold signal only: `hidden` holds, `visible` proves nothing (A2), and WebKit
  fixes it at document creation, so a document born in an uncomposited view
  stays `hidden` after compositing — the reason `awaitPaintedSurface` runs
  before the first navigation and the page-side veto is bounded by
  `kPageHiddenGrace` (A7, FOREGROUND_MULTITASKING.md §7.2). The two app-side
  holds (not painting, no measurable layout) are deliberately unbounded.
- **Integration dependency:** Lane E (E2, E3 — every Browser-dependent capture
  phase), Lane F (F4 — checking holds on the same rule), Lane H (H6 re-argues
  the premise on hardware).

## 2. Image enumeration

- **Original file:** `lib/save/image_candidates.dart` (235 lines), with the
  slice-reassembly loop `SaveEngine._enumerateImages` in
  `lib/save/save_engine.dart`.
- **New location:** unchanged.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/image_candidates_test.dart` (per-image
  rules, width cluster, and the asserted superset property: everything final
  selection accepts, traversal already treated as relevant),
  `test/lazy_image_state_test.dart`, `test/image_enumeration_test.dart`
  (slice reassembly; an incomplete enumeration is never `complete`);
  integration — `integration_test/capture_integrity_test.dart`.
- **Device assumptions:** reads in the scroller's own coordinates, not the
  page's — the bridge's `metrics()` computes `originY` once per probe so an
  inner-scroller page and a document-scroller page report `documentTop` in the
  same coordinate system as `scrollY`. An unmeasured dimension is "not
  measured yet" during traversal and "too small" only on the settled page
  (`unknownSizeIsTooSmall` is the single difference between the two callers).
- **Integration dependency:** Lane E (E2).

## 3. Lazy-image settling

- **Original files:** `lib/browser/bridge_script.dart` (1196 lines —
  `hasSource`, `lazyAttr`, the per-image pending/broken facts) and
  `lib/save/save_engine.dart` (the paced scroll passes, lookahead,
  `_waitForPendingAssets`, quiet-period stop).
- **New location:** unchanged.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/lazy_image_state_test.dart` (an element
  with no source has not asked the network for anything: `complete` is true
  for loaded, failed *and* never-tried images, so "broken" must not swallow
  "not yet triggered"), `test/adaptive_scroll_test.dart` (fast over resolved
  regions, careful near pending content, no full asset-wait for an irrelevant
  image), `test/image_enumeration_test.dart`; integration —
  `integration_test/save_flow_test.dart`,
  `integration_test/capture_integrity_test.dart`.
  *Observation:* a doc comment in `test/lazy_image_state_test.dart` cites
  `integration_test/lazy_image_flow_test.dart`, which no longer exists; the
  comment is stale, the assertions are not. Recorded, not fixed — the file is
  frozen.
- **Device assumptions:** settle windows are load-bearing: an empty first read
  is never trusted (one settle window, a second read, and a still-empty answer
  is *inconclusive*, never "nothing there" — invariant D3 and PLAN §7 A5).
  Lazy loaders fire only when an element scrolls into view from above, so a
  pass that outran the loader is followed by a second pass. The lookahead must
  cover the whole prospective jump plus a margin.
- **Integration dependency:** Lane E (E2); the same settling discipline backs
  Lane F's discovery reads (F3, F4).

## 4. Decode budget

- **Original file:** `lib/reading/decode_budget.dart` (75 lines).
- **New location:** unchanged. It leaves `lib/reading/**` (a retiring V1
  directory) only when the reader call sites move at E5; the §9 inventory
  prescribes no move for it, so it stays put until then.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/decode_budget_test.dart`. Consumed
  under test via the readers in `test/document_reader_test.dart` and
  `test/reader_lifecycle_test.dart`.
- **Device assumptions:** never bounds a decode on unverified DOM dimensions —
  only sizes read back from the stored bytes (`dimensionsVerified`) may bound;
  unknown means "do not guess". Decoding wider than the file upscales at
  `(display / natural)²` memory cost for no detail; the 24-megapixel
  whole-image budget bounds the pathological single panel without touching
  ordinary reading.
- **Integration dependency:** Lane E (E5 — both readers through OfflineCopy).

## 5. FileStore

- **Original file:** `lib/storage/file_store.dart` (374 lines).
- **New location:** unchanged (§2 names it in Lane E's ported set).
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/file_store_test.dart`,
  `test/disk_safety_test.dart`, `test/recovery_test.dart`,
  `test/storage_format_test.dart`; shared harness — some fifty unit suites and
  every integration suite construct it as the storage root.
- **Device assumptions:** atomic commit (staging under `tmp/`, manifest
  written, then one rename — with a copy-and-delete fallback for cross-device
  renames); `.previous` restore so an interrupted replacement never costs a
  readable entry; startup staging sweep; **relative paths only** in the
  database, because the iOS app-container path contains a UUID that changes
  between installs.
- **Integration dependency:** Lane E (E2 writes OfflineCopy bytes through it;
  E5 reads through it), Lane H (recovery after Gate E).

## 6. Manifest

- **Original file:** `lib/storage/manifest.dart` (425 lines).
- **New location:** unchanged.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/manifest_test.dart`; heavily exercised
  by `test/recovery_test.dart`, `test/document_persistence_test.dart`,
  `test/file_store_test.dart` and the save/reader suites; integration —
  `integration_test/save_flow_test.dart`,
  `integration_test/offline_read_test.dart`,
  `integration_test/device_matrix_test.dart`,
  `integration_test/text_capture_test.dart`.
- **Device assumptions:** the manifest is versioned durable user data
  (schema 2) while the database is not: a version-1 manifest has no `artifact`
  field and is read as an image sequence — the only thing the app could
  produce when it wrote one; an unrecognised `artifact` resolves to
  `ArtifactFormat.unknown` and the reader says so; a stored manifest is never
  rewritten in place (the one exception, `writeManifest` for dimension repair,
  is itself atomic: temp file + rename). `ArtifactFormat` is the only field a
  reader or recovery may switch on.
- **Integration dependency:** Lane E (E2 provenance snapshot into OfflineCopy,
  E5 reading), recovery (§10, after Gate E).

## 7. Document model

- **Original file:** `lib/storage/document.dart` (263 lines).
- **New location:** unchanged.
- **Tests carried:** dedicated — `test/document_persistence_test.dart`
  (round-trip, clamping, unknown block types); consumed by
  `test/document_extraction_test.dart`, `test/document_save_test.dart`,
  `test/document_reader_test.dart`; integration —
  `integration_test/text_capture_test.dart`.
- **Intentional internal changes:** none.
- **Device assumptions:** no HTML, no script, no remote reference — typed
  blocks with plain text and flat offset-based emphasis ranges, clamped rather
  than trusted so a bad mark degrades to plain text instead of throwing inside
  a saved page. An unknown block type from a newer writer reads as a
  paragraph rather than vanishing. The block index is the reading-position
  anchor and is layout-independent.
- **Integration dependency:** Lane E (E2 writes it, E5 renders it).

## 8. Capture policy

- **Original file:** `lib/save/capture_policy.dart` (304 lines).
- **New location:** unchanged. Remains the only file in `lib/` that may name a
  host.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/capture_policy_test.dart` (matching
  rules including the lookalike hosts that must not match),
  `test/capture_restriction_test.dart` (every enforcement boundary),
  `test/asset_host_policy_test.dart` (the policy stops at the page boundary:
  an asset served from a restricted host is still fetched);
  guard — `test/repository_cleanliness_test.dart` asserts the constants are
  declared here and nowhere else.
- **Device assumptions:** judges pages, never assets; one file, and every
  boundary asks it for itself — direct start, enqueue, the queue pump, resume,
  retry, multi-entry continuation, top-level redirects, update checking,
  discovered-entry recording, and the save engine before it probes and again
  before it commits. Both save-engine checks run before a staging directory
  exists, which is what keeps `AssetFetcher` out of the policy entirely. A
  refusal is `StopReason.captureRestrictedForSite`, terminal and visible, and
  the one user-facing sentence is `kCaptureRestrictedMessage`.
- **Integration dependency:** Lane E (E2; E4's validation states it plainly —
  the policy is still evaluated on device when a DownloadRequest is consumed),
  Lane F (F3/F4 walks ask it per address).

## 9. Content detection

- **Original file:** `lib/save/content_detection.dart` (300 lines).
- **New location:** unchanged.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/content_detection_test.dart` (427
  lines of literal fixtures).
- **Device assumptions:** structural signals and measurements only — no
  hostname anywhere, in any form; low confidence is a real answer
  (`unknownWebContent` at `low` prints "Saved item"); a number in an address
  is not a structure — the page must declare a relationship before a sequence
  is claimed; a video classification requires all three guards (in the
  readable region, large relative to the measured viewport, and not already
  prose or image-dominant) because a false positive removes capture options
  from a page that could be saved.
- **Integration dependency:** Lane E (E2 mode resolution), Lane F (F3
  discovery reads shape and sequence).

## 10. Document extraction

- **Original file:** `lib/save/document_extraction.dart` (350 lines).
- **New location:** unchanged.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/document_extraction_test.dart`,
  `test/document_save_test.dart`; integration —
  `integration_test/text_capture_test.dart`.
- **Device assumptions:** the split is the component: the bridge measures and
  flags, this file decides, so the rule that determines what an offline copy
  contains is testable against literal fixtures rather than only through a
  live WebView. Named failures (`unreadable`, `noReadableContent`,
  `tooLittleText`) are distinct outcomes; text-only mode drops image blocks
  entirely rather than leaving placeholder holes; a repeated image URL reuses
  its asset instead of fetching twice; whitespace collapse clamps every mark.
- **Integration dependency:** Lane E (E2).

## 11. Stop conditions

- **Original file:** `lib/save/stop_conditions.dart` (334 lines).
- **New location:** unchanged.
- **Intentional internal changes:** none.
- **Tests carried:** `test/capture_policy_test.dart` and
  `test/capture_restriction_test.dart` exercise the `GateCheck` shape and the
  `captureRestrictedForSite` outcome; `test/save_scope_test.dart` exercises
  the `StopReason` vocabulary on terminal rows. **Listed gap:** no test calls
  `detectAccessGate`, `checkOrigin`, `checkRepeat` or `checkStructure`
  directly — the access-gate ordering (structural signals stand alone, phrase
  hints only corroborate an otherwise-empty document), origin comparison,
  canonical-loop detection and shape-change rules have no dedicated unit
  suite. The port must carry the file as is *and* this gap forward; closing it
  is its own task.
- **Device assumptions:** named outcomes only — "finished" and "the site
  stopped us" are different outcomes and live in different column values; the file
  detects and stops, never retries with different headers, never waits out a
  rate limit; origin, not host, is the boundary (`http` to `https` and a port
  change are different origins); a loop that changes the address while serving
  the same document is caught by the canonical check, not the URL check.
- **Integration dependency:** Lane E (E2/E3 — terminal rows carry these
  reasons), Lane F (F4 check outcomes).

## 12. Asset fetcher

- **Original file:** `lib/save/asset_fetcher.dart` (304 lines).
- **New location:** unchanged.
- **Intentional internal changes:** none. It must never import
  `capture_policy.dart`; the image-only MIME allow-list is a separate rule and
  stays.
- **Tests carried:** dedicated — `test/image_format_test.dart` (magic-number
  sniffing), `test/mime_extension_test.dart` (stored extension from verified
  MIME), `test/asset_host_policy_test.dart` (no policy at the asset boundary);
  shared — the save suites drive it end to end.
- **Device assumptions:** image bytes verified by magic number, never by
  `Content-Type` — servers return HTML error pages with a 200 and an image
  content type; the ISO base-media sniff (AVIF/HEIC/HEIF) exists because real
  image CDNs serve it and omitting it rejected every panel on such a site.
  Known hard limit, documented rather than worked around: iOS has no resource
  interception, so a site that is Referer-gated *and* cross-origin *and*
  CORS-closed has no working path and is recorded as unsupported. Stored
  dimensions come from the downloaded bytes; the page's DOM report is kept as
  diagnostics (`domWidth`/`domHeight`) because probe-time sizes are snapshots,
  not intrinsics.
- **Integration dependency:** Lane E (E2, E4).

## 13. Readers

- **Original files:** `lib/features/reader_screen.dart` (2507 lines),
  `lib/features/document_reader.dart` (461 lines).
- **New location:** unchanged for E1. E5 changes their *call sites* (opening
  through OfflineCopy); the §10 cleanup that deletes neighbouring V1 screens
  does not touch these two.
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/reader_lifecycle_test.dart`,
  `test/reader_navigation_test.dart`, `test/reader_bottom_controls_test.dart`,
  `test/reader_chrome_test.dart`, `test/finished_transition_test.dart`,
  `test/document_reader_test.dart`; integration —
  `integration_test/reading_flow_test.dart`,
  `integration_test/offline_read_test.dart`,
  `integration_test/device_matrix_test.dart`,
  `integration_test/foreground_multitasking_test.dart`.
- **Device assumptions:** position restore differs by artifact, and the
  difference is load-bearing. The image reader opens *at* its position —
  panel geometry comes from the manifest, so the offset is known before any
  image decodes. The document reader restores *to* its position, not *at* it:
  a paragraph has no offset until it has been laid out at this width, font and
  text scale, so it opens at the top and jumps on the first measurement — and
  its body is an eagerly built column precisely so every block offset is
  exact. Local files only, no remote fallback anywhere. E5's own validation
  line repeats it: position restore unchanged.
- **Integration dependency:** Lane E (E5), Lane D (D5's read action lands
  here).

## 14. Bridge script

- **Original file:** `lib/browser/bridge_script.dart` (1196 lines), reached
  through `lib/browser/browser_controller.dart` (1156 lines), the single file
  in `lib/` that imports the WebView plugin.
- **New location:** unchanged (`lib/browser/**` is Lane E's ported set).
- **Intentional internal changes:** none.
- **Tests carried:** dedicated unit — `test/bridge_element_text_test.dart`
  (the `elementText` / joined-text-nodes contract). **Listed gap (partial):**
  the rest of the measurement surface — `metrics()`, the probe shape, slicing,
  extraction, locators — has no unit suite; it is exercised only through the
  device-bound integration suites (`save_flow`, `text_capture`,
  `user_assist`, `update_check`, `capture_integrity`) and through the Dart
  halves that consume its output against literal fixtures. That split is by
  design (the JS measures, Dart decides), but it means bridge regressions
  surface on a device, not in `flutter test`.
- **Device assumptions:** the measurement surface both platforms agree on.
  `innerText` is the browser's own layout-defined answer to "what does this
  element say" — `textContent` glues adjacent visible strings into numbers
  that were never on the page, and the detached-clone fallback over-separates
  deliberately, because a split word stops matching while a glued number is
  confidently wrong. Everything positional in a probe derives from a single
  `metrics()` snapshot so no probe can mix two scrollers' coordinate systems.
  Every bridge call ships its own preamble, removing the whole class of "the
  script was not there yet" bugs; every call is bounded by a timeout.
- **Integration dependency:** Lane E (E2), Lane F (F3/F4 read links and
  hints through it).

## 15. Entry identity review

- **Original file:** `lib/library/entry_identity.dart` (214 lines).
- **New location:** **moved** — `lib/recognition/entry_identity.dart`, per §9
  ("moves to `lib/recognition/`, logic unchanged"). Executed with `git mv` in
  this task. Import-path edits that accompany the move, and nothing else:
  - inside the moved file, its one relative import became
    `../library/collection_identity.dart` (the dependency did not move; a
    relative import resolves from the importing file, so the path had to
    follow the move — the roadmap's own description of this worktree is that
    "its conflict surface is import paths only");
  - `lib/library/update_checker.dart` — import and re-export lines;
  - `test/entry_identity_test.dart` — package import line.
  No declaration, rule, constant, threshold or sentence changed.
- **Intentional internal changes:** none (the import line above is a path, not
  logic; `git diff` shows the move as a rename with that single line).
- **Tests carried:** dedicated — `test/entry_identity_test.dart` (269 lines),
  unchanged except the import path.
- **Device assumptions:** refuse and keep the contradiction — nothing repairs
  a number, because a wrong one silently ends discovery for the collection
  (everything real afterwards compares as already-held). Two ordered
  conditions: the source must demonstrably number addresses the way it numbers
  labels (one agreement is the entire evidence — this keeps opaque-id sites
  out of the net), and the label must be an extreme discontinuity (factor 5)
  against the run the addresses themselves spell out. Addresses are the
  reference because a text-extraction fault corrupts labels wholesale.
- **Integration dependency:** Lane F (F3 discovery records through it; F5
  refusal surfacing carries its concerns). Its current caller,
  `update_checker.dart`, retires at §10 after F3 + F4.

## 16. URL normalisation

- **Original file:** `lib/core/url_utils.dart` (176 lines).
- **New location:** unchanged. `lib/core/` is not a retiring directory; V2-D15
  keeps the same algorithms one level down (`url_key` becomes Location
  identity, `host + collection_key` becomes Source identity).
- **Intentional internal changes:** none.
- **Tests carried:** dedicated — `test/url_utils_test.dart`; consumed under
  test by `test/next_page_test.dart`, `test/safe_navigation_test.dart`,
  `test/browser_page_state_test.dart` and the shared fake browser
  (`test/helpers/fake_browser.dart`).
- **Device assumptions:** deliberately does **not** strip `www.` and does
  **not** unify `http`/`https` — both can merge genuinely distinct origins,
  and cookies are scheme-scoped. Fragments are identity-free
  (`pageIdentityKey`); tracking parameters are removed; the deny-listed path
  fragments keep a "next" link away from account and sign-in flows.
- **Integration dependency:** Lane F (F1 — the recognition fast path is built
  on this identity), Lane E (E2 — `url_key` writes), Lane C (C9 index keys).

---

## Gaps — components without a dedicated deterministic test

Recorded so the port cannot silently launder them into "covered":

1. **Stop conditions** (§11): `detectAccessGate`, `checkOrigin`, `checkRepeat`
   and `checkStructure` have no direct unit-test caller. Only the
   `StopReason` vocabulary and the policy-owned `checkCaptureSite` are
   exercised.
2. **Bridge script** (§14): unit coverage is `elementText` alone; the
   measurement surface is proven only on a device through the fixture
   integration suites.
3. **Lazy-image settling** (§3): covered, but one doc comment cites a deleted
   integration file; the stale reference is recorded here rather than edited,
   because the file is frozen.

Everything else in the inventory has at least one dedicated deterministic
suite, listed in its section.

---

## Signing

- **Date:** 2026-08-21
- **Base commit:** `60213c20522f72e8fc1899ecf054f8c96b1ba157`
- **Executed on branch:** `wt/v2-port-validation` (task E1)
- **The rule this document exists to enforce:** *if a ported component needs
  an internal change, that is a task with its own review, not a side effect of
  a call-site edit.*
