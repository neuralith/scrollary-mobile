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
`Unrecognised` branch creates a **standalone Entry in the root Folder**. So a
webtoon chapter on a site the library did not already hold became a loose
item, with no Collection, no Source, and no way to attach it to one.

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
- **collectionIndex** — the address *is* the collection path, with an identity
  strong enough to key a Source.
- **unknownPage** — neither. A real answer: the user is asked, not guessed at.

Shape is not identity. It never merges anything, and it never overrides what
recognition found in the library.

## 3. The matrix

| Page | Recognition | Shape | What the sheet offers | What it writes |
|---|---|---|---|---|
| Entry in the library | `RecognisedLocation` | any | Collection · Entry · Source context; **Download this entry**; **Download entries…** (count) | queue rows only |
| Address on a known Source | `RecognisedSource` | entryPage / unknownPage | "Adds to *Collection*"; **Add & download this entry**; **Add & download…**; Follow | Entry + Location under that Collection, through `EntryReconciler` |
| Unknown site | `Unrecognised` | entryPage | **Add to a Collection…** → existing (adds this site as another Source) or new; then the count | Collection?/Source/Entry/Location in one transaction |
| Unknown site, listing | `Unrecognised` | collectionIndex | **Add this collection to your library** (create or attach); optional **Download entries…** after a check | Collection?/Source; no Entry for the index itself |
| Unknown site, ordinary page | `Unrecognised` | unknownPage | **Save as a standalone entry**; **Add to a Collection…** | standalone Entry + Location (I7) |

Rules that bind every row:

- **A serialized page never becomes standalone silently.** Standalone is
  offered, chosen, and never a fallback for "recognition could not tell".
- **The index page is never an Entry.** A listing is where a Source lives; it
  is not a unit of reading and no `Entry 0` is invented for it.
- **Folder is organisation.** It is asked for when a new Collection or a
  standalone Entry needs a home, and it never stands in for Collection
  identity.
- **Library membership and downloading are separate acts.** Following a
  Collection downloads nothing; downloading one Entry follows nothing. The
  sheet may offer both in one tap, but they remain two operations
  (PRODUCT.md §2.4).

## 4. How much

The count is `SaveScope.fixedCount` with a typed number, clamped by
`SaveLimits.forScope` to `SaveConfig.maxEntriesPerRun` — the V1 rule,
unchanged and still the only way a limit is built. There is no open-ended
scope.

`SaveScopePlanner` turns (start Entry, limits) into the (Entry, Location)
pairs to queue, walking the Collection's own order upward from the Entry the
user was on. It reads the library and nothing else: it opens no page. When
the library knows fewer Entries than were asked for, the plan is short and
says so — finding more is the update check, which is a separate, visible,
bounded and cancellable act, and the sheet offers it in those words.

Capture itself is unchanged: each planned save is one `save_queue` row against
`(Entry, Location)`, run by the V2 `QueueRunner` into an `OfflineCopy`.
Nothing here starts a run — a queued row waits for an explicit Start, as it
always has.

## 5. Cross-source equivalence

Entry reconciliation has exactly one implementation, `EntryReconciler`
(`lib/recognition/reconcile.dart`), used by `SourceDiscovery` and by every
save path. Equal ordinals merge only under `explicitNumericIndex`; 100 and
99.5 stay two Entries; no parseable number leaves the Entry unplaced. See
V2_ARCHITECTURE.md §4.3 and V2-D16 — this file adds no rule of its own, it
only makes sure the browser path obeys the same one.
