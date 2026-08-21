# Terminology

> The canonical model, the contextual display labels, and the old → new rename
> inventory. This is the authority; if another document disagrees with it, this
> one is right.

## 1. The canonical model

| Concept | Meaning | Physical |
|---|---|---|
| **Library** | Everything the user has saved. Not a table — a view over collections plus standalone entries. | — |
| **Collection** | A related group of entries: a sequential publication, a dated feed, a multi-page document, or a group the user made by hand. | `collections` |
| **Entry** | One independently readable saved unit. **May belong to no collection.** | `entries` (`collection_id` nullable) |
| **Page / Section** | A structural part inside an entry. Pages are real pagination or image pages; sections are logical subdivisions of long prose. | the entry's `manifest.json` |

`Entry` and `Collection` are the only nouns used in code. Screens print a
contextual label instead — see §2.

## 2. Contextual display labels

Produced only by `lib/library/entry_labels.dart`. No screen may assemble its own
noun.

Available: **Article · Post · Chapter · Episode · Part · Page · Item · Saved item**

Rules, all enforced in `labelsFor`:

1. Confidence below `medium` → **Item** / **Saved item**. Always.
2. `Chapter` requires long prose *and* a source-declared sequence. A number in a
   URL is not evidence of anything.
3. `Page` requires a pagination control that states a numeric range. Arriving
   from the web is not evidence of a page.
4. Image-dominant content gets **Episode** only when the source declares an
   order, and **Item** otherwise. There is no path from "mostly images" to any
   genre.
5. `Article`, `Post`, `Item` and `Saved item` never take a number.
6. The user can correct the detected kind, from **Entry details → Change
   content type**. `entries.content_kind_is_user_set` stops a later save from
   overwriting the correction.
7. Correcting the kind changes the **label only**. It cannot reach
   `entries.artifact_format`, so relabelling an image package as an article
   never makes the reader try to parse it as a document. What a thing is
   *called* and what its bytes *are* are different facts — see
   ARCHITECTURE.md §3.1.

## 3. Rename inventory

### Domain model

| Old | New |
|---|---|
| `LibraryItem` / `library_items` | `Collection` / `collections` |
| `Chapter` / `chapters` | `Entry` / `entries` |
| `SeriesGroup` | `LibraryCollection` (collection-or-standalone shelf item) |
| `SeriesRepository` | `CollectionRepository` |
| `SeriesIdentity` / `SeriesConfidence` | `CollectionIdentity` / `IdentityConfidence` |
| `SeriesHints` | `PageHints` |
| `SeriesReadingState` | `CollectionReadingState` |
| `ContinueEntry` | `ResumePoint` |
| `SeriesCleanupPref` | `CollectionCleanupPreference` |
| `ChapterLayout` / `ChapterSort` / `ChapterProgressRing` | `EntryLayout` / `EntrySort` / `EntryProgressRing` |
| `chapterDisplayLabel` / `kChapterNoun` | `entryDisplayLabel` + `EntryLabels` |
| `parseChapterNumber` / `chapterLabelFrom` | `parseEntryNumber` / `sourceMarkerFrom` |
| `seriesFingerprint` | `collectionFingerprint` |

### Saving

| Old | New |
|---|---|
| `CaptureJobController` / `capture_jobs` | `SaveRunController` / `save_runs` |
| `CaptureEngine` / `CaptureState` / `CaptureProgress` | `SaveEngine` / `SaveState` / `SaveProgress` |
| `CapturePreflight` / `CaptureConfig` / `CaptureOrigin` | `SavePreflight` / `SaveConfig` / `SaveOrigin` |
| `CaptureRangeMode {currentChapter, fixedCount, untilEnd}` | `SaveScope {currentPageOnly, selectedEntries, fixedCount}` + `SaveLimits` (the open-ended range was removed: its real ceiling was invisible to the user, and with no field to type one into it saved exactly one entry) |
| `AssetDownloader` / `AssetEntry` | `AssetFetcher` / `EntryAsset` |
| `SaveState.downloading` | `SaveState.fetchingAssets` |
| `SiteRule` / `site_rule_rows` / `RuleScope` | `UserPageHint` / `user_page_hints` / `HintScope` |
| `RulesScreen` | `PageHintsScreen` |

### Columns

| Old | New |
|---|---|
| `chapters.library_item_id` | `entries.collection_id` **(nullable)** |
| `chapters.capture_status` / `captured_at` / `capture_error` | `entries.save_status` / `saved_at` / `save_error` |
| `chapters.sequence` | `entries.entry_order` |
| `chapters.chapter_number` / `chapter_label` | `entries.entry_number` / `source_marker` |
| `chapters.progress_image_index` / `progress_offset_in_image` | `entries.progress_page_index` / `progress_offset_in_page` |
| `chapters.detected_image_count` / `stored_image_count` | `entries.detected_asset_count` / `stored_asset_count` |
| `library_items.series_key` / `series_url` | `collections.collection_key` / `collection_index_url` |
| `library_items.last_opened_chapter_id` / `last_completed_chapter_id` | `collections.last_opened_entry_id` / `last_completed_entry_id` |
| `library_items.finished_cleanup` | `collections.cleanup_preference` |
| `capture_jobs.range_mode` | `save_runs.scope` |
| `save_runs.include_images` / `queue_tasks.include_images` | `capture_mode` + `capture_mode_is_user_set` (a boolean could not say "an ordered image sequence" and "an article with pictures" are different) |
| `ReadingPosition.imageIndex` / `offsetInImage` | `anchorIndex` / `offsetInAnchor` (the anchor indexes a panel *or* a block) |
| `queue_tasks.chapter_limit` | `queue_tasks.entry_limit` |

### Files

`lib/capture/` → `lib/save/` · `capture_job.dart` → `save_run.dart` ·
`capture_engine.dart` → `save_engine.dart` · `capture_state.dart` →
`save_state.dart` · `capture_preflight.dart` → `save_preflight.dart` ·
`asset_downloader.dart` → `asset_fetcher.dart` · `site_rule.dart` →
`page_hint.dart` · `rule_repository.dart` → `page_hint_repository.dart` ·
`series_repository.dart` → `collection_repository.dart` · `series_identity.dart`
→ `collection_identity.dart` · `series_detail_screen.dart` →
`collection_detail_screen.dart` · `chapter_actions.dart` → `entry_actions.dart` ·
`chapter_details_sheet.dart` → `entry_details_sheet.dart` · `capture_panel.dart`
→ `save_panel.dart` · `capture_range_sheet.dart` → `save_scope_sheet.dart` ·
`capture_queue_ui.dart` → `save_queue_ui.dart` · `browser_capture_state.dart` →
`browser_save_state.dart` · `continue_entry.dart` → `resume_point.dart` ·
`rules_screen.dart` → `page_hints_screen.dart`

New: `lib/library/content_shape.dart` · `lib/library/entry_labels.dart` ·
`lib/save/content_detection.dart` · `lib/save/stop_conditions.dart` ·
`lib/save/capture_mode.dart` · `lib/save/document_extraction.dart` ·
`lib/storage/document.dart` · `lib/storage/recovery.dart` ·
`lib/features/document_reader.dart`

### Deleted with no replacement

`CollectionRepository.backfillExistingSaves` + `BackfillReport` (regrouped
pre-grouping captures) · `repairEntrySourceUrls` · `repairCompletedProgress` ·
`lib/storage/manifest_repair.dart` + `repairManifestDimensions` ·
`SavedSitesRepository.seedDefaultIfNeeded` + `kDefaultSavedSiteUrl` +
`kSavedSiteSeedKey` + `SavedSites.is_default` · the whole `onUpgrade` chain for
schema versions 2–12 · `integration_test/live_*.dart` (six files naming
third-party sites and copyrighted series titles).

## 4. No compatibility layer

There are no typedef aliases, no deprecated forwarding classes, no re-exporting
files, no `entry => chapter` extension getters, no old route names and no old
serialised field names under new Dart names. The neutral model is the
implementation.
