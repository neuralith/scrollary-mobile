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
| Unknown site | `Unrecognised` | entryPage | **Add to a Collection…** → existing (adds this site as another Source) or new; then the count | Collection?/Source/Entry/Location in one transaction |
| Known Source's own listing | `RecognisedSource` | collectionIndex | "there is no entry here to add"; **Check *Collection* for new entries**; Follow | nothing — the check writes what it finds |
| Unknown site, ordinary page | `Unrecognised` | unknownPage | **Save as a standalone entry**; **Add to a Collection…**; and, when the address could be a listing, **Add this site as a collection's source** | standalone Entry + Location (I7), or — for the third — Collection?/Source and **no Entry** |

Rules that bind every row:

- **A serialized page never becomes standalone silently.** Standalone is
  offered, chosen, and never a fallback for "recognition could not tell".
- **The index page is never an Entry.** A listing is where a Source lives; it
  is not a unit of reading and no `Entry 0` is invented for it. Whether an
  address *is* a listing is the library's answer or the user's — never the
  URL's.
- **Folder is organisation.** It is asked for when a new Collection or a
  standalone Entry needs a home, and it never stands in for Collection
  identity.
- **Library membership and downloading are separate acts.** Following a
  Collection downloads nothing; downloading one Entry follows nothing. The
  sheet may offer both in one tap, but they remain two operations
  (PRODUCT.md §2.4).
- **A count that may open a page is authorised before it opens one.** The
  count sheet asks *how much*; the start sheet asks *where you wait while it
  is found*. See §4.

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
| Opens a page | never | only for the ones the library is missing |
| Missing Entries | reported as a short plan | found by reading forward on this Source |
| Implemented by | `SaveScopePlanner` | `SourceWalk` (`lib/recognition/walk.dart`), then the planner |

The second is what people mean when they are reading entry 101 and ask for ten:
the library usually knows four of them, and stopping at four because the rest
had never been seen is the limitation this exists to remove. It is chosen in
the sheet (`SaveScopeChoice.discoverMissing`), because it opens the site — and
content-affecting source automation is always user-started, visible, bounded
and cancellable, exactly like the update check.

### What the sheet asks, in its own words

Three ranges, of which two take a count. The typed number means the same thing
in both, and the sheet says so instead of leaving it to be inferred:

| Range | Returns | The sentence under it |
|---|---|---|
| **This entry** | `currentPageOnly`, `discoverMissing: false` | "Only the page you are on." |
| **Entries from here** | `fixedCount`, `discoverMissing: true` | "Type how many to download from this page onward — up to *N*." |
| **Entries already in your library** | `fixedCount`, `discoverMissing: false` | "The same count, but only the ones your library already knows." |

The field asks it in its own label — **"How many entries, counting this
one?"** — so the inclusive count is stated where the number is typed rather
than left to be inferred from it. Under the field, the sentence that tells the
two counted ranges apart says it again in numbers. For *Entries from here*:

> 5 means this entry and the next four. If your library does not have the
> later ones yet, Scrollary opens this site and reads forward from this page
> to find them. Nothing else is downloaded, and you can stop it at any point.

and for *Entries already in your library*:

> 5 means this entry and the next four. Only entries your library already
> knows are queued, and this site is not opened — if it knows fewer than you
> ask for, that is what gets queued and Scrollary says so.

The ceiling stays where it always was — stated in the range's own line and
enforced by `SaveLimits.forScope` — and so does every part of the recovered
numeric interaction: digits only, a blank and a zero refused where they were
typed, and an OK bar for the number pad iOS gives no return key.

### The gate, because it navigates

A run that may open pages goes through `showStartOptionsSheet`
(`ForegroundGateAction.startEntrySave`) before anything is opened — the same
sheet, and the same three answers, as `startCollectionCheck`. It names the
bound in words:

> Download *N* entries from here? Scrollary downloads up to *N* entries, from
> this page onward — counting this one. For any your library does not have
> yet, it opens this site in the Browser and reads forward to find them, at
> most `kMaxWalkPages` pages. Nothing else is downloaded, and you can stop it
> at any point.

It is asked whenever the count is a claim about the Source *and* is more than
one, because whether a page has to be opened is what the walk finds out: a
sheet that appeared only once a gap was found would be asking permission after
the app had already gone to the site. A count of one is the page in front of
the user and opens nothing, and the library-only range opens nothing either —
neither is ever gated.

The gate decides **where the user waits**, never whether the work happens
(CLAUDE.md, "Free and Pro"). Backing out starts nothing and changes nothing,
and there is no second question anywhere on this path. When the user also asked
for *Start now*, the queue's own Start is authorised after the reading, through
`startQueuedDownloads` — the two acts stay two acts, and each is authorised
where it happens.

Reading forward is visible and stoppable in the compact running surface
(`features/running_operation_panel.dart`), beside *Downloading* and *Checking*
and drawn the same way: a label, an indeterminate bar and a Stop that ends it
at the next page boundary. That panel draws its two existing states over
controllers publishing exactly *is it running* and *stop it*, and the walk is
shown through the same pair — no third kind of status surface, and no control
that claims more than the walk knows. Entries already resolved stay in the
library.

The walk is bounded twice: by the typed count, and by `kMaxWalkPages` pages
opened. It follows only what the page's own links assert, through the same
`resolveNextPage` capture uses — a number in a URL never manufactures the
address after it. Every page it reads is reconciled through `EntryReconciler`
before anything is queued, so an Entry the Collection already holds at that
position gains a Location rather than a twin, and an address already held is
reused untouched. A next address that is not on this Source ends the walk.

Ending is never failure: `countReached` and `endOfSource` are both normal, and
"there were only six" is an answer about the Source. A walk that stops early —
a page that would not render, a next control only the user can point at, a
cancellation — keeps every Entry it had already resolved.

## 5. How much (the bound)

The count is `SaveScope.fixedCount` with a typed number, clamped by
`SaveLimits.forScope` to `SaveConfig.maxEntriesPerRun` — the V1 rule,
unchanged and still the only way a limit is built. There is no open-ended
scope.

`SaveScopePlanner` turns (start Entry, limits) into the (Entry, Location)
pairs to queue, walking the Collection's own order upward from the Entry the
user was on. It reads the library and nothing else: it opens no page. When the
library knows fewer Entries than were asked for, the plan is short and says so.

That is one of the two operations in §4 — *Entries already in your library* —
and it is not what a typed count means by default. The default is *Entries
from here*, where the count is a claim about the Source and what the library
is missing is found by reading that Source forward. A short plan is the
quieter range's honest answer, never the intended semantics of a count.

Capture itself is unchanged: each planned save is one `save_queue` row against
`(Entry, Location)`, run by the V2 `QueueRunner` into an `OfflineCopy`.
Nothing here starts a run — a queued row waits for an explicit Start, as it
always has.

## 6. Cross-source equivalence

Entry reconciliation has exactly one implementation, `EntryReconciler`
(`lib/recognition/reconcile.dart`), used by `SourceDiscovery` and by every
save path. Equal ordinals merge only under `explicitNumericIndex`; 100 and
99.5 stay two Entries; no parseable number leaves the Entry unplaced. See
V2_ARCHITECTURE.md §4.3 and V2-D16 — this file adds no rule of its own, it
only makes sure the browser path obeys the same one.
