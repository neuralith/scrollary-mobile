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
| Download this entry | save sheet → **Download this entry** | Free | `features/v2_add_flow.dart` | `test/save_v2/add_flow_test.dart` | — |
| Download a number of entries I type | save sheet → **Entries from here** → count | Free | `library_ui/save_scope_sheet.dart` | `test/library_ui/save_scope_sheet_test.dart` | — |
| Download the next N even if the library doesn't know them | same, count > what is held | Free | `recognition/walk.dart` | `test/recognition/walk_test.dart` | — |
| Download entries the library already has | save sheet → **Entries already in your library** | Free | `save/save_scope.dart` | `test/save_v2/save_scope_test.dart` | — |
| See how far a download has got | anywhere a run is visible | **Free** | `features/operation_progress.dart` | `test/library_ui/operation_progress_test.dart` | — |
| See images found and saved for the entry running | same | **Free** | `features/operation_progress.dart` | `test/library_ui/operation_progress_test.dart` | — |
| Stop a running download | Browser panel · Activity · entry menu | **Free** | `library_ui/entry_offline.dart` | `test/library_ui/activity_test.dart` | — |
| Stop a run that is still finding entries | Browser panel · save sheet | **Free** | `features/v2_adoption_providers.dart` | `test/recognition/walk_test.dart` | — |
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
| Point at the next-entry control when the app can't find it | Browser → assist overlay | Free | `features/selection_overlay.dart` | `integration_test/user_assist_test.dart` | **yes** |
| Find my archived Collections | Library → **Show archived** | Free | `library_ui/shelf_screen.dart` | `test/library_ui/shelf_test.dart` | — |
| Dismiss a discovered entry I don't want | entry menu → **Remove from library** | Free | `library_ui/collection_actions.dart` | `test/library_ui/collection_test.dart` | — |
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
