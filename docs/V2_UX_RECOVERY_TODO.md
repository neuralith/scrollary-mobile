# V2 UX recovery — the reading and capture regressions, and their fixes

Ten items, worked in order. Each one names the **regression as the user meets
it**, the **root cause in the code**, and the **fix**, and is marked DONE only
once its focused tests pass. Nothing here redesigns V2: every fix is a missing
wire, a dropped piece of evidence, or a question asked twice.

The rule from `V2_CAPABILITY_PARITY.md` applies to everything below — a
capability is restored only when it is reachable from app launch and something
tests it.

| # | Item | State |
|---|---|---|
| 1 | Capture next N captures N | DONE |
| 2 | Open at Source brings the Browser into view | DONE |
| 3 | Entry number and title read from page evidence | DONE |
| 4 | Reading progress: Source and OfflineCopy | TODO |
| 5 | The Collection remembers what to capture | TODO |
| 6 | Queue only / Start now / Start in background | TODO |
| 7 | Queued work is visible and startable without scrolling | TODO |
| 8 | Each decision asked once | TODO |
| 9 | Tests that drive the journey, not the widget | TODO |
| 10 | The routine flow stays short | TODO |

---

## 1. Capture next N captures N

**Regression.** *Entries from here* walks the site, reports that it found the
entries, and captures fewer than were asked for — sometimes none.

**Root cause.** `v2_add_flow.dart::_queue` walks the Source, then throws the
walk's own answer away and **re-plans against the library** with
`SaveScopePlanner`. That planner walks a Collection's rows in ordinal order and
takes those with `ordinal >= start.ordinal`. A page the walk read that printed
no number reconciles to an Entry with `placement = unplaced` and `ordinal =
null` (`EntryReconciler`), so the replan cannot see it and queues nothing for
it. The walk did its job; the step after it discarded the result.

**Fix.** Queue the walk's **own** resolved entries — `WalkedEntry` already
carries `entryId` and `locationId` — appended after the library plan and
de-duplicated by Entry. The count then means captures, not discoveries, and no
Entry has to be placed to be downloaded (position is organisation, not
permission).

## 2. Open at Source brings the Browser into view

**Regression.** *Open at source* loads the page and leaves the user on the
Collection screen.

**Root cause.** `app.dart` wires `v2.openSource` to
`browserNavigatorProvider.request(url)` plus `shellTabRequestProvider.value =
1`. The Browser is a **tab inside the shell route**; Collection Detail, the
reader and Activity are pushed *above* it, so changing the tab underneath them
changes nothing the user can see. `open_in_browser.dart` documents exactly this
as "the step every call site was missing" and owns the correct sequence.

**Fix.** Route the wiring through `showBrowserSurfaceWith`, which pops back to
the shell and then selects the tab.

## 3. Entry number and title read from page evidence

**Regression.** Entries found by walking a Source arrive unnumbered and titled
with the raw document title, which then feeds item 1's failure.

**Root cause.** `BrowserForwardPageSource.read` calls `readPageShape(landed,
pageTitle: probe.title)` and drops `probe.pageHints` — the `h1`, the
`og:title` and the breadcrumb trail that `parseEntryNumber` already reads and
that `resolveCollectionIdentity` already uses for a title. The evidence was
gathered and discarded one line before it was needed. The walk then writes
`probe.title` verbatim as the Entry's title, site name and all.

**Fix.** Pass the hints through, and give the Entry the detected title when the
page volunteered one. Nothing site-specific: it is the same generic reading
every other path uses. Contradictory evidence still refuses —
`reviewEntryIdentities` is untouched.

## 4. Reading progress: Source and OfflineCopy

**Regression.** Reading at the Source records that the Entry was opened and
nothing about how far. Nothing in the app ever writes a `Measurement`, and
`EntryProgressRing` — which exists and is tested — is drawn on no screen.

**Root cause.** `MeasurementRepository.put` has no caller outside the sync pull
path. The library row list shows a read/unread word and no fraction.

**Fix.** Two halves, kept apart exactly as the model keeps them:

* **Source.** A measurement rule over the page's own geometry, and a meter that
  writes it against `(entry, source)` at the moments the app already has — the
  page is about to be left, the tab is being left, or the app is going away.
  Nothing is written for a page shorter than the viewport: there is no position
  to measure and none is invented.
* **OfflineCopy.** The anchor is already stored and restored. What was missing
  is the **fraction for display**, derived where it is honest — an image
  package's `anchorIndex / panels` — and absent where it is not.

Neither depends on the other, and neither requires a download: an Entry read at
its Source keeps its progress with no copy on the device.

## 5. The Collection remembers what to capture

**Regression.** *What to save* is asked on every save of every Entry, even the
five-hundredth from the same Collection.

**Root cause.** Capture mode is a queue-row column and nothing else. It is
chosen per save and forgotten per save.

**Fix.** Remember the user's explicit choice as that Collection's preference —
in `LocalSettingsStore`, keyed by Collection, so the frozen schema is untouched
— and prefer it over detection when the sheet opens. An Entry-level choice sets
the preference for *its own* Collection and no other. Changeable later from the
Collection.

## 6. Queue only / Start now / Start in background

**Regression.** The post-save choices are ambiguous, and *Start in Browser*
after *Add to queue* starts nothing.

**Root cause.** Starting was split across two sheets that do not know about
each other. `SaveScopeChoice.startNow` decides whether `startQueuedDownloads`
is called; `showStartOptionsSheet` — asked separately, before the run, to
authorise reading forward — returns `StartChoice.inBrowser`, which the save
flow answers by flipping the shell tab and nothing more. Choosing it after
*Add to queue* therefore shows the Browser and starts no work.

**Fix.** One decision with three unambiguous outcomes, taken in the sheet that
asks how many:

* **Queue only** — add the work, start nothing.
* **Start now** — add it and start, in the Browser, where the user watches.
* **Keep working while I read** — the same start through the existing
  foreground-multitasking gate, which is the one thing Pro buys. The operation
  is never gated; only where the user waits is.

## 7. Queued work is visible and startable without scrolling

**Regression.** *Start* sits inside Activity's scrolling list, below the
WAITING rows.

**Root cause.** The launch row is a child of the `ListView`.

**Fix.** Pin it above the list, so the count and the Start are on screen the
moment Activity opens however many rows there are. The count elsewhere is
already carried by the operation indicator, which is free and opens Activity.

## 8. Each decision asked once

**Regression.** A single *Start now* is answered by two further modals.

**Root cause.** The path asks four questions: the save sheet, the scope sheet
(*Add to queue* / *Start now*), `_authoriseReadingForward`'s gate sheet, and
then `_startQueuedDownloads`'s **second** gate sheet.

**Fix.** The scope sheet carries the gate's own rows (item 6), so the walk's
consent and the start are one answer; and the start it authorises passes that
answer through, so the queue does not ask again. `V2_SAVE_FLOW.md` already
claims "there is no second question anywhere on this path" — this makes that
true.

## 9. Tests that drive the journey, not the widget

The suites added for items 1–8 assert the orchestration, not the paint: N
captures from a count of N, a walk over unnumbered pages, the Browser's visible
destination, the ordinal reaching the Entry, a measurement written without a
download, a copy's fraction, queue-only versus start-now, the entitlement seam
untouched, Activity's Start present without scrolling, and the routine flow's
question count.

## 10. The routine flow stays short

For a Collection the app already knows, with a remembered preference, the sheet
is a line of context, the remembered mode as one line with a way to change it,
and the two capture choices. Progress stays a count, a bar and a Stop, with the
log behind *Details*.
