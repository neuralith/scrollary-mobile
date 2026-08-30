# Capability parity — what must survive a rewrite

This document exists because the V2 rewrite deleted user-facing capabilities
that nobody decided to delete, and every gate passed them through.

The cause was not carelessness. It was that every cleanup precondition in
[V2_ROADMAP.md](./V2_ROADMAP.md) §10 is a statement about **symbols and
mechanisms** — *"the new path owns X and passes Y"*, *"deleted subsystem has no
remaining caller"* — and none is a statement about what a person can do. A
capability can disappear entirely while satisfying all of them. It did, eight
times in one commit (`b0740eb`), whose message records the whole failure:
the roadmap authorised retiring two files on an engine-ownership precondition;
the commit retired those two files plus eight surfaces, and *"their tests
retire with them"*, which is why the suite stayed green.

## The rule

> A previous implementation may not be removed unless **either** a durable
> product decision explicitly retires the capability, **or** an equivalent V2
> surface exists, **is reachable from app launch**, and its parity test passes.

And its companion, which is what kept the suite green through eight deletions:

> Deleting a regression test requires naming its successor test, or the durable
> product decision that retired its behaviour.

Three things make this work where the roadmap's own safeguard did not:

- **Rows are written from the user's side.** *"Download ten entries and watch
  the count"* — never *"the queue owns terminal states"*. A row phrased as a
  mechanism can be satisfied by a deleted feature.
- **Reachability is part of the assertion.** Every parity test drives the real
  path from launch, not a widget mounted behind a synthetic button. Half the
  regressions found in the audit were working, tested code with nothing routed
  to it; a test that instantiates the widget directly passes throughout.
- **"The new path owns the domain" is not sufficient.** `recognition/check.dart`
  genuinely owns checking, which made `library_check.dart` deletable under the
  old rule — while the Library-wide *granularity* it provided had no owner at
  all and simply vanished.

## The contract

`Free/Pro`: the boundary is **where the user waits**, never what the app will
do (CLAUDE.md, "Free and Pro"). *Free* below means the capability itself is
never gated. *Device* marks the few rows whose behaviour only a real device can
prove; everything else is provable by fast deterministic tests, and rows are
expected to carry one.

| Capability (user's words) | Path from launch | Free/Pro | V2 owner | Parity test | Device |
|---|---|---|---|---|---|
| Save the page I'm reading | Browser → save action → **Save** | Free | `features/v2_save_flow.dart` | `test/v2_save_flow_test.dart` | — |
| Say which Collection a page belongs to | Browser → save → **Add to a Collection…** | Free | `recognition/adopt.dart` | `test/recognition/adopt_test.dart` | — |
| Add this site as another Source of a Collection | same, choose an existing Collection | Free | `recognition/adopt.dart` | `test/recognition/adopt_test.dart` | — |
| Start a Collection for the page I'm on | same, **New collection** → the save sheet itself: the detected name, its first Source, the range and the launch | Free | `features/v2_save_flow.dart` | `test/library_ui/save_panel_test.dart` | — |
| Correct the name Scrollary detected for it | same sheet, `collectionNameField` — prefilled, editable, blank refused in place | Free | `library_ui/save_scope_section.dart` | `test/library_ui/save_scope_section_test.dart` | — |
| See and change what a collection is saved as, without saving anything | Collection → menu → **What to save** (the row states the current answer) | Free | `library_ui/collection_actions.dart` | `test/v2_check_flow_test.dart` | — |
| Have the first save settle what a collection is saved as | save sheet → pick or accept the proposed mode → Start/Queue | Free | `features/v2_save_flow.dart` | `test/library_ui/save_panel_test.dart` | — |
| Download this entry | save sheet → **Download this entry** | Free | `features/v2_add_flow.dart` | `test/save_v2/add_flow_test.dart` | — |
| Have a collection keep saving as what I chose | anywhere a capture starts — save sheet, Library, after a check, a repair, another device | Free | `save/entry_capture.dart` | `test/save_v2/capture_preference_test.dart` | — |
| Download a number of entries I type | save sheet → **Entries from here** → count | Free | `library_ui/save_scope_section.dart` | `test/library_ui/save_scope_section_test.dart` | — |
| Download the next N even if the library doesn't know them | same, count > what is held | Free | `save/capture_journey.dart` | `test/save_v2/capture_journey_test.dart` | — |
| Get N entries on this device from a count of N | same | Free | `features/v2_add_flow.dart` | `test/save_v2/capture_journey_test.dart` | — |
| Download entries the library already has | save sheet → **Entries already in your library** | Free | `save/save_scope.dart` | `test/save_v2/save_scope_test.dart` | — |
| See how far a download has got | anywhere a run is visible | **Free** | `features/operation_progress.dart` | `test/library_ui/operation_progress_test.dart` | — |
| See images found and saved for the entry running | same | **Free** | `features/operation_progress.dart` | `test/library_ui/operation_progress_test.dart` | — |
| Stop a running download | Browser panel · Activity · entry menu | **Free** | `library_ui/entry_offline.dart` | `test/library_ui/activity_test.dart` | — |
| Stop a run that is still finding entries | Browser panel · Activity · save sheet | **Free** | `save/queue_runner.dart` | `test/save_v2/capture_journey_test.dart` | Reading a Source forward happens **inside** a download now (V2-D56), so the download's own Stop is this stop: it ends the capture at its next safe point and no further page is opened. There is no separate *stop finding* to press. |
| Retry something that failed | Library → Activity → **Retry** | **Free** | `library_ui/entry_offline.dart` | `test/library_ui/activity_test.dart` | — |
| Know when the app needs me | operation indicator → **Needs you** | **Free** | `features/operation_indicator.dart` | `test/library_ui/operation_indicator_test.dart` | — |
| See what a finished run actually did | Activity → run summary | **Free** | `library_ui/run_summary.dart` | `test/library_ui/run_summary_test.dart` | — |
| See the detail when something goes wrong | run summary → **Details** | **Free** | `library_ui/run_summary.dart` | `test/library_ui/run_summary_test.dart` | — |
| Check a Collection for new entries | Library → collection → **Check** | Free | `features/v2_check_flow.dart` | `test/v2_check_flow_test.dart` | — |
| Check every Collection at once | Library → **Check all collections** | Free | `features/library_check_flow.dart` | `test/library_ui/library_check_test.dart` | — |
| See which Collections have new entries | Library rows carry the state | Free | `library_ui/shelf_models.dart` | `test/library_ui/shelf_test.dart` | — |
| Be told honestly why a check could not finish | check result | Free | `features/v2_check_flow.dart` | `test/v2_check_flow_test.dart` | — |
| Be told when a Source stops listing something | check result | Free | `features/v2_check_flow.dart` | `test/v2_check_flow_test.dart` | — |
| Download the new entries a check found | Collection → **Download new** | Free | `library_ui/collection_screen.dart` | `test/library_ui/collection_test.dart` | — |
| Read the next entry from the reader | reader → **Next** | Free | `reading_v2/` | `test/library_ui/reader_navigation_test.dart` | — |
| Have a finished entry's download freed when I read on | reader → **Next**, after answering once per Collection | Free | `reading_v2/forward_transition.dart` | `test/reading_v2/forward_transition_test.dart`, `test/reading_v2/reader_cleanup_route_test.dart` | Asked once per Collection, on the first forward move where it has a consequence (V2-D59) |
| Be asked before a nearly-finished entry is called finished | reader → **Next** at or past 0.90 | Free | `reading_v2/forward_transition.dart` | `test/reading_v2/forward_transition_test.dart` | *Mark finished and continue* · *Continue without finishing* · *Cancel*; below 0.90 nothing is asked |
| Change or clear what happens to finished entries here | Collection menu → **Finished entries** | Free | `library_ui/collection_actions.dart` | `test/v2_check_flow_test.dart` | *Remove after finishing* · *Keep downloaded* · *Ask again next time* |
| Keep an entry I am reading out of a storage sweep | Storage → **Remove finished offline entries** | Free | `storage/cleanup.dart` | `test/reading_v2/reader_cleanup_route_test.dart` | The Entry open in the reader is skipped and kept, never failed |
| Open an entry at its source and land on it | entry menu → **Open at source** | Free | `features/open_in_browser.dart` | `test/open_in_browser_test.dart` | — |
| Keep how far through I am, on a page I have not downloaded | Browser, reading a known entry | Free | `reading_v2/source_reading.dart` | `test/library_ui/reading_progress_test.dart` | — |
| See how far through an entry I am | Library → collection rows | Free | `library_ui/collection_models.dart` | `test/library_ui/reading_progress_test.dart` | — |
| Not be asked what to save every single time | save sheet, after answering once | Free | `save/capture_preference.dart` | `test/library_ui/save_panel_test.dart` | — |
| Change what a Collection is saved as | Library → collection menu → **What to save** | Free | `library_ui/collection_actions.dart` | `test/v2_check_flow_test.dart` | — |
| Queue work without starting it | save sheet → **Queue only** | Free | `features/v2_save_flow.dart` | `test/library_ui/save_panel_test.dart` | — |
| Start what I queued, from where I am | Activity · Browser panel | **Free** | `library_ui/entry_offline.dart` | `test/activity_screen_test.dart` | — |
| Point at the next-entry control when the app can't find it | Browser → assist overlay | Free | `features/browser_forward_pages.dart` · `features/selection_overlay.dart` | `test/save_v2/next_control_assist_test.dart` · `integration_test/user_assist_test.dart` | **yes** |
| Point at a next control the site handles in script, with no address on it | Browser → assist overlay | Free | `save/page_hint.dart` (`DomLocator.activate`) | `test/save_v2/next_control_assist_test.dart` | The rule is applied by pressing the control; an ambiguous match is refused rather than pressed |
| Not have the same entry downloaded over and over | any multi-entry run | Free | `recognition/walk.dart` (`WalkStop.noForwardProgress`) | `test/recognition/walk_test.dart` | Judged on the landed address, so a source that circles is stopped rather than followed |
| Find my archived Collections | Library → **Show archived** | Free | `library_ui/shelf_screen.dart` | `test/library_ui/shelf_test.dart` | — |
| Dismiss a discovered entry I don't want | entry menu → **Remove from library** | Free | `library_ui/collection_actions.dart` | `test/library_ui/collection_test.dart` | — |
| Read a serialized collection as a sequence | Library → collection | Free | `library/entry_presentation.dart` | `test/library_ui/entry_presentation_test.dart` | — |
| See what the source actually called an entry | entry menu → **Details** | Free | `library_ui/entry_details.dart` | `test/library_ui/collection_test.dart` | — |
| Keep working while something runs | any screen, with Pro | **Pro** | `capability/foreground_gate.dart` | `test/foreground_gate_test.dart` | — |
| Sync my library across devices | Settings → Sync, with Pro | **Pro** | `features/v2_composition.dart` | `test/settings_sync_capability_test.dart` | — |

Two rows are guarantees rather than features, and both are pinned by tests
because both were lost once already:

- **Seeing what the device is doing is never paywalled.** Progress, counts,
  Stop, failures and *Needs you* are Free, always. Pro buys foreground
  multitasking — *where* the user waits — and nothing else about an operation.
- **Local library work never needs a network.** Following, organising,
  downloading, reading and checking all work with `SCROLLARY_SYNC_BASE_URL`
  undefined.

## Retired on purpose

These are gone by decision, and the decision is the authority. A future
contributor finding a gap here should read the decision before restoring
anything.

| Capability | Decision |
|---|---|
| A separate unplaced-entries view | V2-D29 |
| Undo on folder deletion | V2-D33 |
| Sync status furniture for Free devices | V2-D37 |
| Browsing silently expanding the library | V2-D40 |
| `CollectionDeletionService` as the deletion path | V2-D42 |
| Folder drill-down navigation | V2-D43 |
| Boot recovery rebuilding rows from disk | V2-D22 / I14 — the storage survey reports instead |
| A separate Archived screen | V2-D48 — archived Collections are a filter on the one Library page |
| V1's eleven-choice save preflight | V2-D49 — only states V2 can actually distinguish are offered |
| Undo on the finished-entry cleanup | V2-D59 — the same reasoning: V1 backed its notice with a six-second soft delete, V2 deletes outright, and the reversibility is the rule being asked once before anything is freed |
| Undo on a storage cleanup | V2-D33's reasoning — cleanup deletes packages outright, so the confirmation with real counts *is* the reversibility; a button that cannot restore would be a lie |
