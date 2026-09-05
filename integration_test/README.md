# Device suites

Eleven suites that need a simulator, an emulator or a device, because what they
prove cannot be proved on a host: a real WebView, real compositing, real
platform insets, real bytes on a real filesystem.

They run against the in-process fixture in `tool/fixture/`, served **inside the
app process on the device**. Nothing here reaches a third-party site, and no
hostname is compiled in.

```bash
flutter test integration_test -d <device-id>          # all of them
flutter test integration_test/save_flow_test.dart -d <device-id>
```

Per file is usually what you want: a whole-suite run is long, and one failure in
the middle is easier to read on its own.

## What each one proves

| Suite | The question only a device answers |
|---|---|
| `occlusion_gate_test.dart` | Does a **painted but fully covered** WebView keep rendering, scrolling and running JavaScript? The premise the whole foreground design rests on. |
| `save_flow_test.dart` | The V2 save: the sheet queues, nothing captures until an explicit Start, a launch closes the sheet and leaves the Browser usable while the run goes on behind it (V2-D67), one Start drains the queue, real PNG bytes land in order, a cancel stops without a false success. |
| `capture_integrity_test.dart` | The bridge's per-call image cap and slice reassembly, coordinates when an inner element is the scroller, and `HTMLImageElement.complete` across every lazy/broken/loaded shape. |
| `text_capture_test.dart` | Text and text+images capture: what the extractor keeps, what it drops, and a document package read back with the source gone. |
| `offline_read_test.dart` | Capture online, destroy the origin, read entirely from disk. Partial entries warn; deleted files degrade without touching the Entry; the image reader opens *at* its anchor and the document reader restores *to* it. |
| `reading_flow_test.dart` | Reading state across a restart, Continue Reading, mark read / unread, and a re-capture that preserves all of it. |
| `update_check_test.dart` | A source-scoped check discovers Entries and downloads nothing; one ordinary check reads one Source and never picks one for you. |
| `activity_indicator_test.dart` | Where the pill actually lands against the platform's own insets and the shell's chrome — a simulated padding is a number someone typed; a notch is not. |
| `foreground_multitasking_test.dart` | The product claim and its control arm: with the capability a capture continues under the Reader; without it, it holds and resumes whole. |
| `device_matrix_test.dart` | The hardware matrix under a watchdog: the check race, terminal-state quiescence, one-Entry-one-copy, a covered capture on a real source, a queue that drains from the Library tab, and a soak. |
| `user_assist_test.dart` | The premise of user-assisted next-page selection, on real DOMs. Its four "ask the user" cases are written and **skipped** — see below. |

## The shared boot

`support/v2_harness.dart` builds **the production composition**, assembled the
way `lib/main.dart`'s `AppStartup._open` assembles it: one `AppDatabase`, one
`LibraryDatabase`, the repositories over it, a `QueueRunner` over
`EntryCaptureService` over `SaveEnginePageCaptureSource` over the ported
`SaveEngine`, and a `CheckController` over the recognition pipeline. The only
differences from `main()` are the database names, the store folder, and two
observation hooks.

Two things there are worth knowing before you change a suite.

**The engine observation is a production seam, not scaffolding.** `SaveEngine`
already publishes `onProgress` and `onLog`; `main()` passes neither. The harness
passes both, which is how a suite can still assert on
`SaveState.waitingForBrowser` — the hold the whole foreground claim turns on —
now that `QueueRunner` publishes only *running* and *not running*. Reading a
state the engine already publishes is not weakening an assertion; adding a flag
to `lib/` to read it would be.

**`openPage` is not `BrowserController.loadAndWait`.** The Browser boots on
Browser Home, a local surface drawn *over* the still-mounted WebView. Loading
straight into the controller leaves the page rendering behind an overlay, with
the save control describing a page the user cannot see. `openPage` goes through
`BrowserNavigator`, which is what the whole app goes through, and the drainer
reveals the website surface before it loads.

## The one substitution, and why

`FixtureOriginObservations` supplies a listing origin to the update check.

`BrowserSourceObservationSource.observe` reconstructs the first page of a
Source's listing as `'https://${source.host}${source.pathKey}'`. A Source's
identity is `(host, path_key)` (V2-D15) and carries **neither the scheme nor the
port**, so there is no way to name an origin that is not default-port HTTPS —
including this project's own fixture, which is `http://127.0.0.1:<port>`.

The wrapper substitutes exactly that one string and delegates everything else to
the production implementation: the navigation, the landed-URL policy boundary,
the settled-page probe, the listing extraction and the ordering-confidence rule
all run for real. **Delete it in the same change that lets a Source name its own
origin.**

## Restarting the app — and why nothing here does

V1's suites closed the database and rebuilt the app mid-test to prove a position
or a row survived a relaunch. Three shapes of that were tried here and none of
them holds:

- pumping an empty tree between the two apps unmounts the `InAppWebView` on its
  own, which trips the plugin's `AndroidFindInteractionController was used after
  being disposed` and takes the connection to the app down with it;
- closing the databases and reopening them without rebuilding the tree
  deadlocks — drift keys its connection by database name, and a close a live
  query stream is holding open leaves the next handle over the same name waiting
  forever;
- closing them *and* rebuilding the tree hangs on iOS and crashes the app on
  Android, for both reasons at once.

So durability is asserted through `V2App.freshLibraryReads()` — repositories
built *after* the write — which proves the value reached the database rather
than living in the object that wrote it. That is weaker than a cold start and
the headers say so. The cold-start claim is what a separate `flutter test`
invocation makes for free, since each one installs the app fresh.

**One boot per `testWidgets`, and no second one inside it.** The same three
shapes fail whether a suite calls the second boot a relaunch or not, so a case
that needs a fresh app is a *case*: the framework tears the tree down between
them, and the next one opens its own database over its own tag. `device_matrix`
was the one file that broke this rule — seven scenarios in a single
`testWidgets` — and six of them were reporting on the harness rather than on
the product. It is a `testWidgets` per scenario now.

## Shutting down — the tree before the database

**A shutdown from inside a case must pass its tester.** A mounted
`ProviderScope` holds the six query streams `_libraryTicks` subscribes to, and
`LibraryDatabase.close()` over the background isolate `driftDatabase` opens
does not return while they are live. Measured on the simulator: with the tree
up the close was still unfinished at 90 s; unmounted first it finished in
14 ms. So it is not a slow close and a longer bound does not help —
`V2App.shutdown(tester: tester)` pumps the tree away first.

Most suites never meet this. They shut down from a suite-level `tearDown`,
which runs *after* the binding has torn the tree down, so their streams are
already gone; `shutdown()` with no tester keeps that path exactly as it was.
`device_matrix` is the only file that shuts down within a case, through
`quiesce`.

This is the one place the "pumping an empty tree unmounts the `InAppWebView`"
hazard above is deliberately accepted: it happens at the very end of a case,
where the framework unmounts a moment later anyway. It is proven on iOS.
**Unverified on Android** — if it trips the plugin there, `_closeQuietly`'s
bound is still the backstop and the unmount is what to gate.

**A teardown may only touch the app its own case booted.** `app` is one field
shared by every case, which is right for a body — it runs after its own boot —
and wrong for a teardown, which runs whether the body reached a boot or not. A
case that skips on an unmet precondition returns before booting, and reaching
for `app` there finds the *previous* case's, whose database that case already
closed. `device_matrix` keeps `bootedThisCase` for exactly this, and quiescing
nothing is what a case that booted nothing does.

### What now fails rather than merely printing

Both of the above were reported for a whole run and nothing failed on them.
Reporting and judging are separate jobs here, and each keeps its own:

- `_closeQuietly` still bounds its wait and moves on — right for a run in
  progress, wrong as an outcome — but it **returns whether it closed**, and
  `quiesce` asserts that. A database that never closes is now a red case, not
  one line of output.
- `DeviceHarness.scenario` still catches a teardown throw into a note so the
  table can print in full, and `matrixCase` now **fails on any note beginning
  `teardown problem`**. The row is still reported either way.

## Skips, and what each one is waiting for

Nothing here is skipped to go green.

- **`user_assist_test.dart`, four cases** — a named absence in `lib/`. The
  judgement survived the port (`resolveNextPage`, `PageHintRepository`,
  `BrowserController.selections` are all still here) but nothing *asks*:
  `QueueRunner` holds no pending selection, `EntryCaptureService` has no
  selection path, and `operation_indicator.dart`'s `_needsUser` is hard-wired
  `false`. The five cases that establish the premise run today.
- **`reading_flow_test.dart`, one case** — a defect: a re-capture discards the
  reading anchor.

## Defects this suite found

Each is written up in full where it bites, with a reproduction.

| Where | What |
|---|---|
| `lib/data/offline_copy_repository.dart:35` | `recordCopy` inserts a fresh copy row with a null anchor, so a re-capture sends the reader back to the top. V1 had `carryReading` for exactly this and still unit-tests it. |
| `lib/library_ui/collection_actions.dart:179` | The Entry action sheet is a non-scrolling `Column` in a `showModalBottomSheet` with no `isScrollControlled`, so on a shorter screen it overflows and its lower actions are unreachable. |
| `lib/features/source_observation_browser.dart:36` | A Source's listing address is rebuilt as `https://{host}{pathKey}`, which cannot express a scheme or a port. See "The one substitution" above. |

Two more it found are fixed, and stay listed so a reader knows which suite
would notice them coming back: `DeviceCapacityController.refresh` writing
`state` after its scope was disposed, and a root Source (`path_key = '/'`)
recognising none of its own `/entry/N` addresses as members.

Two were defects in **this harness** rather than in `lib/`, and are fixed with
a guard each — see "Shutting down" above: a close under a mounted tree that
never returned, and a skipped case quiescing the previous case's shut-down app.

## What a simulator and an emulator cannot answer

Thermal behaviour, energy, real occlusion compositing on production silicon,
VoiceOver and TalkBack over a covered WebView, and renderer termination under a
genuine memory warning. Those are `docs/FOREGROUND_MULTITASKING_PLAN.md`'s
V-10 … V-13 and D-2 … D-5, and they need hardware. A green run here is evidence
about the app's logic and the platform's compositing, not about the device's
thermal envelope.
