# V2 save flow — what the user is asked, and what it writes

The save sheet is where a page becomes library. This document is the decision
matrix it implements, and the reason each branch exists. It is the contract
between `lib/recognition/` (what do we know), `lib/features/v2_save_flow.dart`
(what do we ask) and `lib/save/` (what do we queue).

## 1. The regression this replaces

V1 asked two questions on the way in — *which collection is this?* and *how
much of it do you want?* — and the V2 rewrite lost both. Commit `b0740eb`
("retire the V1 queue and save run") removed `save_scope_sheet.dart`, the save
panel and the collection-name panel along with the V1 queue they were wired
to. The V2 sheet that replaced them offers one button, for one page, and its
`Unrecognised` branch creates a **standalone Entry in the root Folder**. So one
numbered Entry of a serialized work, read on a site the library did not already
hold, became a loose item — no Collection, no Source, and no way to attach it to
one.

Two things were lost, and they are one journey:

| Lost | Restored as |
|---|---|
| Collection context before capture: create, choose, correct the name | §3 below — `LibraryAdoption` (`lib/recognition/adopt.dart`) |
| "How many entries?" with a typed count | §4 below — `SaveScope`/`SaveLimits` (unchanged) + `SaveScopePlanner` (`lib/save/save_scope.dart`) |

## 2. What the page is, structurally

`readPageShape` (`lib/recognition/page_kind.dart`) answers this from the
address and the page's own words, with the helpers that already existed —
`parseEntryNumber` and `collectionFingerprint` — and nothing site-specific.

- **entryPage** — a number was printed, or the address sits below a collection
  path that is not itself.
- **collectionIndex** — the address *is* a Source's own path, **as the library
  reports it**. Nothing else produces this answer.
- **unknownPage** — neither. A real answer: the user is asked, not guessed at.

Shape is not identity. It never merges anything, and it never overrides what
recognition found in the library.

**Why a listing is never claimed from the address alone.** `example.com/about`
and `example.com/series/quiet-harbour` have the same shape: a path with no
entry number and nothing deeper under it. An app that reads the second as a
listing reads the first as one too, and puts *add this collection to your
library* in front of someone reading a privacy policy. So the claim requires
the library's own word — the address is the `path_key` of a Source it already
holds — and on a site nothing is known about, `PageShape.couldBeListing` marks
the possibility and the sheet **offers** it as one answer among three instead
of announcing it.

## 3. The matrix

| Page | Recognition | Shape | What the sheet offers | What it writes |
|---|---|---|---|---|
| Entry in the library | `RecognisedLocation` | any | Collection · Entry · Source context; **Download this entry**; **Download entries…** (count) | queue rows only |
| Address on a known Source | `RecognisedSource` | entryPage / unknownPage | "Adds to *Collection*"; **Add & download this entry**; **Add & download…**; Follow | Entry + Location under that Collection, through `EntryReconciler` |
| Unknown site | `Unrecognised` | entryPage | **Add to a Collection…** → the picker: an existing Collection (this site becomes another Source of it) or **New collection**, which goes straight to the sheet that names it and asks the count | Collection?/Source/Entry/Location in one transaction |
| Known Source's own listing | `RecognisedSource` | collectionIndex | "there is no entry here to add"; **Check *Collection* for new entries**; Follow | nothing — the check writes what it finds |
| Unknown site, ordinary page | `Unrecognised` | unknownPage | **Save as a standalone entry**; **Add to a Collection…**; and, when the address could be a listing, **Add this site as a collection's source** | standalone Entry + Location (I7), or — for the third — Collection?/Source and **no Entry** |

Rules that bind every row:

- **A serialized page never becomes standalone silently.** Standalone is
  offered, chosen, and never a fallback for "recognition could not tell".
- **The index page is never an Entry.** A listing is where a Source lives; it
  is not a unit of reading and no `Entry 0` is invented for it. Whether an
  address *is* a listing is the library's answer or the user's — never the
  URL's.
- **Folder is organisation, and the save flow does not ask for it.** A new
  Collection and a standalone Entry are created in the root Folder; moving one
  is a Library action (`library_ui/folder_actions.dart`,
  `library_ui/collection_actions.dart`). Folder never stands in for Collection
  identity, and putting the question on the way in would be a third answer to
  give before anything is saved.
- **Library membership and downloading are separate acts.** Following a
  Collection downloads nothing; downloading one Entry follows nothing. The
  sheet may offer both in one tap, but they remain two operations
  (PRODUCT.md §2.4).
- **A count that may open a page is authorised before it opens one.** The
  save sheet asks *how much* and, in the rows directly under it, *where you
  wait while it is found* (V2-D52). See §4.
- **It is one sheet** (V2-D62): an identity line, the range block, the capture
  line and the launch, in that order. There is no *Download this entry* /
  *Download entries…* pair, and nothing opens after it. A listing has no range
  at all, and a standalone Entry keeps its single download because it has no
  Collection order to count along.
- **A Collection the user is starting is named on that same sheet** (V2-D57).
  The picker is still where *which Collection* is answered — the ones the
  library already holds are visible before another is started — and it is the
  only modal on that path: what it answers hands the save sheet back with the
  name field, the range and the launch on it. The exception is a listing,
  which queues nothing and so still names it in the picker.

## 4. How much, and how far

**What a typed count means.** It counts the Entry in front of the user as the
first one. Ten, from entry 101, means 101 through 110 — not 101 plus ten more.
The sheet says "from this page onward" and the planner walks the Collection's
order from the starting Entry inclusive; both halves have meant this since the
count was restored, and nothing below changes it.

Two operations answer that count, and they are not the same question:

| | **Download the ones I have** | **Download the next N from here** |
|---|---|---|
| The count is a claim about | the library | the **Source** |
| Opens a page | never | one per Entry, while the downloading happens |
| Missing Entries | reported as a short plan | found as the download reaches them |
| Implemented by | `SaveScopePlanner` | `SourceCaptureJourney` (`lib/save/capture_journey.dart`) over `SourceWalk` |

**The second is one sequential journey, not a survey followed by a download**
(V2-D56). The entry in front of the user is queued — it is the only one whose
identity is already known — and the runner then captures it, reads the page it
is on for the address after it, captures that, and carries on:

```text
capture this entry → find the next → capture it → find the next → …
```

Nothing resolves the range first. A count of a hundred used to be a hundred
pages opened before the first byte was kept and a hundred opened again to keep
it; now each page is opened once, identified, and captured where it stands —
`SourceWalk.forward`'s `onEntry` hands each Entry over on the page the walk has
just opened, and the capture reads that page rather than asking the site for it
a second time (`pageAlreadyLoaded`).

**What gets captured is what the walk resolved**, as it stands — the Entry a
`WalkedEntry` names. Not a plan derived from the library: the planner takes a
Collection's rows in ordinal order, and a page that printed no number, or any
Collection whose ordering basis does not support cross-source merging, leaves
the walked Entry with no position at all (`EntryReconciler`). Those Entries are
real, addressed and downloadable — position is organisation, not permission —
and a plan could not see them, so a count the Source had just satisfied came
back with nothing queued for them. The count means **captures**, not
discoveries.

The second is what people mean when they are reading entry 101 and ask for ten:
the library usually knows four of them, and stopping at four because the rest
had never been seen is the limitation this exists to remove. It is chosen in
the sheet (`SaveScopeChoice.discoverMissing`), because it opens the site — and
content-affecting source automation is always user-started, visible, bounded
and cancellable, exactly like the update check.

### What the sheet asks, in its own words

**Two rows, one of which takes a count** (V2-D65). Each is one line, and the
count sits on the row it belongs to:

| Range | Returns |
|---|---|
| **This entry** | `currentPageOnly`, `discoverMissing: false` |
| **Entries from here** `[ N ]` | `fixedCount`, `discoverMissing: true` |

*Entries already in your library* is **not offered while saving**. It answers a
different question — queue what is already known, open nothing — and nobody
reaches for it on the page in front of them. `SaveScopePlanner` still
implements it (§6) for the paths that use it.

One sentence under the counted row carries everything the three descriptions
used to carry between them:

> Counts this entry as the first, so 5 means this one and the next four — up
> to *N*. One page at a time, nothing else downloaded, and you can stop at any
> point.

That is the inclusive count stated where the number is typed, the ceiling as a
number the user can see, and what the operation does and does not do. The
ceiling is still enforced by `SaveLimits.forScope`, and so is every part of the
recovered
numeric interaction: digits only, a blank and a zero refused where they were
typed, and an OK bar for the number pad iOS gives no return key.

### Naming a Collection that does not exist yet

For *New collection*, the top of the range block on the save sheet is where the
Collection is named (V2-D57, V2-D62). `SaveScopeController` carries a
`NewCollectionNaming`, and the block gains two rows above *How much*:

| | |
|---|---|
| `collectionNameField` | the detected title, editable, **not** autofocused — the common answer is *yes*, and a keyboard over the ranges would make confirming it cost a dismissal |
| `newCollectionSourceFact` | `First source · reading.example.com` — the site about to become the Collection's first Source, named rather than referred to |
| then | the three ranges, the count, the capture line and the launch, unchanged |

The trimmed name comes back on `SaveScopeChoice.collectionName` and is what
`v2AddAndDownload` is given as `newCollectionName`. A blank one is refused
where it was typed, and it is checked before the count. The count field keeps
the OK bar to itself: an alphabetic keyboard has a return key, and a number
pad does not.

### The launch, asked once

**How much** and **what happens next** are one sheet and one answer, and since
V2-D62 so is **what to save**.
`SaveScopeChoice` carries a `SaveStartMode`, and it has exactly three values:

| Launch | What happens |
|---|---|
| **Queue only** | The row is added and, for a count about the Source, the journey is arranged. Nothing starts, and no page is opened. |
| **Start now** | Added and started, with the Browser in front of the user. One authorisation runs the whole operation — Activity is where a run is *watched*, never a second Start it has to be given. |
| **Start and keep using Scrollary** | The same start, leaving the user where they are. |

The rows are the foreground gate's own — `ForegroundStartActions`, the same
widget `startCollectionCheck` uses — supplied to the sheet by
`v2_save_flow.dart`, because `lib/library_ui/` may not reach that boundary and
the boundary must not be described twice. The chosen answer travels with the
Start as `StartWhere`, so `startQueuedDownloads` and the shell's
`_startQueuedDownloads` are *told* rather than asking again.

**What this replaced, and why.** The path used to ask four questions about one
intention across three surfaces: the save sheet, a *scope sheet* after it with
*Add to queue* / *Start now*, a gate sheet before the run asking where the user
would wait, and the queue's own gate sheet asking it a second time. The scope
sheet went too (V2-D62); what is left is one surface. One route through them was broken outright
— *Add to queue* followed by *Start in Browser* brought the Browser forward and
started nothing, because the second sheet's answer only flipped the shell tab
while whether anything ran had already been settled by the first.

The gate decides **where the user waits**, never whether the work happens
(CLAUDE.md, "Free and Pro"). *Queue only* is a complete answer that needs no
capability at all, the visible-Browser start is fully functional without one,
and dismissing the sheet starts nothing and changes nothing.

**Consent for the reading still comes first**, and it is where the count is
typed — before anything is opened. The sentence under the field names the
site, the ceiling, that nothing else is downloaded and that it can be stopped;
a count of one opens nothing, and the library-only range opens nothing either.

Reading forward is not a state of its own any more, because it never happens on
its own: it happens between one entry of a download and the next. So the
compact running surface (`features/running_operation_panel.dart`) shows
*Downloading* for the whole operation, with the counts and one Stop — and that
Stop ends the journey, not merely the page it was on. No further address is
opened and no further row is written. The save sheet carries the same stop,
because the panel is docked exactly where the sheet sits and a control the user
must dismiss the sheet to reach is not reachable while the thing it stops is
running.

The journey is bounded twice: by the typed count, and by the pages it may open
— one per Entry, so the ceiling is the count itself rather than
`kMaxWalkPages`, which stays the bound for a walk that resolves without
capturing. It follows only what the page's own links assert, through the same
`resolveNextPage` capture uses — a number in a URL never manufactures the
address after it. Every page it reads is reconciled through `EntryReconciler`
before it is captured, so an Entry the Collection already holds at that
position gains a Location rather than a twin, and an address already held is
reused untouched. A next address that is not on this Source ends the journey.

Ending is never failure: `countReached` and `endOfSource` are both normal, and
"there were only six" is an answer about the Source — said in the run summary
as *6 of 20 entries downloaded · No next entry found*. A journey that stops
early — a page that would not render, a next control only the user can point
at, a cancellation — keeps every Entry it had already captured.

## 5. How much (the bound)

The count is `SaveScope.fixedCount` with a typed number, clamped by
`SaveLimits.forScope` to `SaveConfig.maxEntriesPerRun` — the V1 rule,
unchanged and still the only way a limit is built. There is no open-ended
scope.

`SaveScopePlanner` turns (start Entry, limits) into the (Entry, Location)
pairs to queue, walking the Collection's own order upward from the Entry the
user was on. It reads the library and nothing else: it opens no page. When the
library knows fewer Entries than were asked for, the plan is short and says so.

That is one of the two operations in §4 — *the ones the library already has* —
and it is not what a typed count means on the save sheet, which offers only
*Entries from here*: the count is a claim about the Source, and what the
library is missing is found by reading that Source forward. The planner's
answer is still what a count of one and every non-Browser path resolve to.

Capture itself is unchanged: each save is one `save_queue` row against
`(Entry, Location)`, run by the V2 `QueueRunner` into an `OfflineCopy` —
whether the row was planned from the library or written by a journey a step at
a time. Nothing here starts a run: a queued row waits for an explicit Start, as
it always has, and a journey waits with it.

## 6. Cross-source equivalence

Entry reconciliation has exactly one implementation, `EntryReconciler`
(`lib/recognition/reconcile.dart`), used by `SourceDiscovery` and by every
save path. Equal ordinals merge only under `explicitNumericIndex`; 100 and
99.5 stay two Entries; no parseable number leaves the Entry unplaced. See
V2_ARCHITECTURE.md §4.3 and V2-D16 — this file adds no rule of its own, it
only makes sure the browser path obeys the same one.
