# Decision log

> Durable product and architecture decisions. A decision here is **settled** — it
> is revisited only by adding a superseding record, never by editing one away.
> Anything genuinely open lives in [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md)
> or §Open below, and must **not** be written elsewhere as though decided.

The V2 direction: **a recognition-driven, cross-platform personal reading
library.** You read; Scrollary recognises what it is and keeps your library
current; reading state follows the logical Entry; downloading is an optional
per-device capability.

Product: [PRODUCT.md](./PRODUCT.md) · Domain:
[V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) · Sync and backend:
[V2_SYNC.md](./V2_SYNC.md) · Plan: [V2_ROADMAP.md](./V2_ROADMAP.md).

---

## Still in force from the first V2 pass

**V2-D1 · No store release until the V2 library and sync work ships.**
Every remaining V1 release blocker is external — accessibility passes, Android
hardware, legal URLs, console and trademark work. Consequence: there are no
released users, so V2 starts from a fresh database and the V1 schema rule needs
no revision. A migration system is required before the first store build, not
before V2 code.

**V2-D5 · A removal on one device never destroys bytes on another.**
Library removal syncs as metadata. Bytes are freed only by a local action. A
device that has been offline for weeks cannot object to a deletion, so it is
never asked to obey one destructively. Invariant I14.

**V2-D6 · Reading progress is last-write-wins; completion is revertible.**
Highest-progress-wins breaks *Mark as unread*, which exists to lower progress.
Completion is a value, not a floor.

**V2-D7 · Sync's relation to the paid boundary is deferred.**
Binding regardless of the answer: local writes and the outbox are never gated;
`lib/capability/` stays the only entitlement reader; any gate may sit only on the
network drain. Moved to [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md).

**V2-D8 · The backend holds library metadata in plaintext.**
Identity arbitration needs to compute over it and clients need to display it.
Consequence: the privacy audit and both store declarations must be redone before
release. Downloaded bytes are never uploaded.

**V2-D9 · Opening an Entry at its source records access; completion stays explicit.**
Sets first-opened and last-read. Never infers completion. `CompletionPolicy` is
unchanged. Invariant I16.

**V2-D10 · Documentation stays flat; V2 documents sit beside the as-built ones.**

**V2-D11 · Sign-out keeps everything on the device.**
Tokens clear, the drain stops, rows and downloads and the outbox all stay.

**V2-D3 · Accounts are optional — now scoped to mobile.**
The mobile app is the complete product with no account, permanently. Amended by
V2-D19: the extension requires one by nature.

---

## Superseded by the first-principles pass

**V2-D2 · Library membership = user state attached to a row.**
→ Superseded by **V2-D13**. Following a Collection is a single explicit act and a
cleaner boundary than a derived property of seventeen columns. The predicate
survives with its real job (V2-D15).

**V2-D4 · One canonical source per Collection, mutable, previous retained.**
→ Superseded by **V2-D14**. A mutable single pointer with a history list was a
workaround for a schema that could not hold a set. It was diff-minimisation, not
design.

**Keep the V1 schema; add columns to `onCreate`.**
→ Superseded by **V2-D26**.

**One Entry table with three column groups.**
→ Superseded by **V2-D15** and **V2-D22**.

**Phase 1 delivers library-first inside the V1 tables.**
→ Superseded by **V2-D12**. That work would be thrown away by the rewrite.

---

## V2 final

### V2-D12 · Broader rewrite, with a defended port-as-is boundary

New product, domain, data and application structure. Device-validated low-level
components are **ported as files, not as intentions** — call sites change,
internals do not.

*Why.* `update_checker.dart` and `save_run.dart` assume one Source per Collection
and URL-scoped traversal; the queue's unit of work and the three large screens are
built on the V1 shape. Keeping the V1 tables would carry URL-as-Entry-identity
into every query, sync record and client contract, because that axiom is in the
primary keys.

*The risk, recorded once.* V1 encodes behaviour that was expensive to find and is
invisible in the source — why `requestAnimationFrame` is the only honest
covered-rendering signal, scroller-coordinate image reads, lazy settling, the
decode budget's unverified-dimensions rule, atomic commit with
interrupted-replacement restore, single-winner cancellation.
`FOREGROUND_MULTITASKING_PLAN.md §7` is a list of assumptions that failed on
hardware. Re-deriving them re-opens bugs no test will catch, because the tests
were written *after* the discoveries. The port inventory in
[V2_ROADMAP.md](./V2_ROADMAP.md) is what contains that risk.

### V2-D13 · Following a Collection is the authorising act

A Collection in the library **is followed**. Following licenses Scrollary to keep
it current from the user's reading. Reading an Entry of a followed Collection
updates the library; anything else lands in device-local history with a one-tap
promotion. Archive is how following stops, and it preserves everything.

*Why.* One explicit act at the Collection level, inherited by every Entry beneath
it, rather than a derived property. It also keeps the library curated while the
recognition loop is real.

### V2-D14 · A Collection has a set of Sources, with lifecycle

A **Source** is this Collection on one site: host, path key, language, lifecycle
(`active · dormant · dead · resolvedInto`). Active alternatives and dead
predecessors are the same structure at different times — a site returning is a
state change, not a row moved between tables. No separate source-history table.
Preference is a single pointer on the Collection.

### V2-D15 · An Entry is not a URL; the V1 keys move down one level

`url_key` becomes **Location** identity, unchanged. `host + collection_key`
becomes **Source** identity, unchanged. `normalizeUrl`,
`collectionFingerprint` and `parseEntryNumber` keep their behaviour and their
tests. `isDiscoveredOnlyEntry` stops being the library boundary and becomes what
it was written for: **the rule for what a Source's own reading may retract**.

### V2-D16 · Cross-source equivalence is by ordinal, and is gated by ordering basis

Available only for `explicitNumericIndex`. Equal ordinals merge; different
ordinals stay two Entries; unparseable or ambiguous ones stay **unplaced** —
visible, readable, offered to the user. Date-ordered, next-link and
discovery-ordered Collections may hold several Sources but their Entries are not
merged.

*Why.* Reliability over pretending every website can be normalised. This is the
posture `entry_identity.dart` already takes within one Source: stop and keep the
contradiction rather than repair it.

### V2-D17 · A translation is a Source of the same Collection

Language belongs to the Source. Reading Entry 101 anywhere marks 101 read — you
read the work once, and the app can say which language you read it in.

### V2-D18 · Measurement scope replaces progress confidence

Reading *state* is on the Entry and syncs. A *measurement* is keyed
`(entry, source)` and carries the rendering it was taken against. The *anchor*
lives on the OfflineCopy and never leaves the device.

*Why.* A fraction measured against one Source's rendering is not an
approximation of another's — it is a fact about a different thing. No
precise/estimated/observed taxonomy is needed. Whether an approximation may ever
be *shown* across Sources is deferred to Productization; the architecture does
not assume it.

### V2-D19 · The extension requires an account, and tracks rather than captures

It exists to put things into a library shared with a phone, so it is inherently a
sync client. Mobile stays fully usable without an account.

It does not capture: capture would mean re-implementing the restricted-site
policy, the media rules, magic-number asset validation, manifest writing and the
atomic commit in JavaScript — a second safety-critical implementation of the
parts that most need to exist once.

### V2-D20 · Metadata synchronisation is automatic; the blanket network rule is split

The V1 rule that *every network operation is user-started, visible and
cancellable* now applies to **content-affecting source automation only** —
capture, source traversal, update checking, anything that drives the browser.

**Lightweight metadata synchronisation is exempt.** It is automatic,
opportunistic, non-blocking, retryable, resumed after connectivity returns, safe
to interrupt, and background-capable where a platform allows it. It fetches no
page, drives no browser and stores no content.

*Not promised:* permanent background execution. No mobile platform offers it.
What is promised is durable local state plus reliable continuation.

### V2-D21 · Folder is user organisation, with a single system root

A Folder holds Collections and standalone Entries. Hierarchy is in the schema
from day one; a nested-folder UI is not required to ship with it. Folder state
syncs. Sources are never attached to Folders.

**A single system root Folder**, rather than a nullable placement or a separate
`Unfiled` folder. Every item then has exactly one parent, "move to folder" is
always the same operation, every placement syncs as a value rather than sometimes
as a null, and no query needs a null branch. "At the library root" means "in the
root Folder".

**Deletion is conservative**: children reparent to the deleted Folder's parent.
It never cascades into Collections or Entries.

An Entry inside a Collection has no Folder membership of its own. A standalone
Entry has one directly and is never wrapped in a Collection of one.

### V2-D22 · OfflineCopy is a device-local entity carrying a provenance snapshot

Bytes captured from one Location, on one device, at one time, in one format. One
active copy per Entry per device; a re-download replaces it through the existing
atomic path. **Provenance is stored as values, not references** — the Location
URL, the Source name, host and language, the capture time — so a Source dying or
a Location being retracted cannot orphan a copy already on a device.

Nothing about an OfflineCopy is ever sent to or received from the server.

### V2-D23 · Backend is Go + Fiber v3 + managed PostgreSQL, one stateless service

The entity graph is genuinely relational and the core server job — identity
arbitration — is logic rather than CRUD, which is the part least worth expressing
through someone else's abstraction. No Redis, no queues, no brokers, no object
storage, no orchestration: nothing V2 functionality needs.

### V2-D24 · Identity arbitration is server-side, and the server never fetches pages

Clients inspect pages and submit **evidence**; the server returns canonical
identity or `unresolved`. Offline clients mint provisional identity and
canonicalise on the next sync.

**The server makes no outbound request.** Arbitrating over evidence clients
gathered is a different thing from fetching pages, and the distinction carries
the product's whole position.

The hot path stays local: a known `url_key` resolves through a local index with
no round trip.

### V2-D25 · Download to Mobile is an intent, fulfilled by a device

The extension creates a **DownloadRequest**. The backend records it and never
fetches content. A device claims it through a single-winner conditional update,
converts it into an ordinary local save task, and applies its own capture policy
and validation unchanged. Terminal state is reported back.

A DownloadRequest is not OfflineCopy state. At most one non-terminal request per
`(library, entry)`, so pressing the button twice does not queue two saves. A
failure never changes library membership. Device targeting stays minimal —
anything more drags account work into the foundation.

### V2-D26 · A fresh V2 schema, with no V1 migration

There are no released users (V2-D1). The local database is designed from the
domain, not from V1 tables. Development databases are reset by hand. No
compatibility layer, no dual-write, no V1 reader.

### V2-D27 · An OpenAPI document is the shared contract boundary

Three languages — Dart, Go, and later JavaScript — must agree on the same
payloads, and the two most divergence-prone parts of this design are *evidence
submission* and *mutation shape*, both structured records with many optional
fields. One schema all three validate against removes a class of drift that would
otherwise surface as silent duplicates in someone's library. Written once at Gate
B and frozen. Not a runtime dependency, and not adopted for any other reason.

### V2-D28 · A development library namespace stands in for authentication

The functionality build needs only enough for several development clients to
address the same test library: an `X-Scrollary-Library` header, behind an
explicit `SCROLLARY_DEV_MODE` flag the server refuses to start without.

It is labelled development-only, authenticates nothing and says so, is one
middleware to remove, and distorts nothing — `library_id` is a real column the
production account model will populate.

### V2-D29 · An unplaced Entry surfaces inside its own Collection's list (resolves O-B)

A NEEDS PLACEMENT section sits at the end of the Collection's **one** Entry
list (`lib/library_ui/collection_screen.dart`), not in a separate view. Both
halves of the list draw the same row widget with the same actions; the
section label and a one-line explanation are the only difference a placed and
an unplaced Entry get.

*Why.* D3's rule is one list, availability as row state — a second,
download-oriented list was already refused for the same reason. An unplaced
Entry is exactly as real and readable as a placed one; giving it a separate
screen would make it feel like a queue rather than a library item waiting on
one fact.

### V2-D30 · Measurement tombstones are scoped by `source_id`

A Measurement is keyed `(entry, source)` (I12), so its tombstone names the
Source too — `tombstones.source_id` on the backend
(`scrollary-backend/migrations/0001_init.up.sql`,
`internal/domain/tombstone.go`). Every other tombstone kind leaves it empty.

*Why.* An unscoped measurement tombstone would read as "drop every measurement
for this Entry", deleting readings taken on Sources nobody touched. The scope
is part of the tombstone's identity, not an afterthought on top of it — two
scoped deletions of one Entry are two tombstones, never one overwriting the
other.

### V2-D31 · Revisions are allocated inside the write transaction; the feed reads from one snapshot

The library's next revision is allocated inside the same transaction that
writes the row it belongs to (`scrollary-backend/internal/storage/postgres/state.go`,
`sync.go`), and `GET /changes` reads the head and every row it returns from one
repeatable-read snapshot.

*Why.* A revision handed out before its row commits, or a feed read that mixes
snapshots mid-page, both create a window where a puller sees a later revision
without having received an earlier one — and once its cursor has moved past
that gap, nothing asks it to go back. Allocating inside the transaction and
reading from one snapshot closes both windows by construction rather than by
convention.

### V2-D32 · `applyRemote*` uses `insertOnConflictUpdate`, never `insertOrReplace`

Every pulled-row writer in `lib/data/*_repository.dart` upserts with
`insertOnConflictUpdate`.

*Why.* SQLite's `INSERT OR REPLACE` is a `DELETE` followed by an `INSERT` when
a conflict exists, and the schema's `ON DELETE CASCADE` foreign keys
(Locations, Measurements, the save queue and more, all keyed off `entries.id`
and similar) would fire on the delete half — silently destroying children of a
row a pull only meant to refresh.

### V2-D33 · Folder delete is confirm-with-counts; no optimistic Undo

Deleting a Folder shows what it holds and where its children will land, then
asks for confirmation (`lib/library_ui/folder_actions.dart`). There is no
Undo affordance the way a removed queue row gets one.

*Why.* Undo elsewhere works by restoring an `orderIndex` on a row that never
left the database. A deleted Folder's children have already been reparented
and, for the Folder row itself, restoring it would mean minting a new
identity — sync would see a create, not the row that was there a moment ago.
Asking first, with real counts, is the honest version of reversibility here;
pretending to undo it is not.

### V2-D34 · Device label is random, opaque, minted once, never hardware-derived

`lib/sync/device_label.dart` mints an opaque `device-<8 hex chars>` label on
first use, stores it in local settings and never rewrites it. Nothing about it
comes from a device name, model or platform identifier.

*Why.* The label exists only so a claim can say which of a user's own devices
took a download (V2_SYNC.md §7); device targeting stays deliberately minimal
(V2-D25), so the label needs no permission, no dependency and no capability
beyond naming a record. Deriving it from hardware would make it an
identifier in substance even though the product makes no use of it as one.

### V2-D35 · A Download-to-Mobile request for an Entry this device does not hold is never claimed

`lib/sync/download_intent.dart` selects only the pending requests for Entries
this library holds and can reach before it claims anything.

*Why.* Claiming is single-winner (V2-D25): burning the one claim on an Entry
this device cannot even attempt would take the request away from a device
that could fulfil it, with no way to give it back. Leaving it alone costs
nothing — the next device to pull sees the same pending request.

### V2-D36 · Sync scheduler and retry constants

`lib/sync/scheduler.dart` (`SyncSchedule`) and `lib/sync/retry.dart`
(`RetryPolicy`) fix the numbers behind V2_SYNC.md §2: start jitter up to 3s,
a 15-minute foreground tick, a 2-minute minimum resume interval, a 5-second
mutation debounce, and retry backoff from 30s doubling to a 30-minute cap with
a subtractive 0.2 jitter fraction. A run in flight absorbs every trigger into
one follow-up; nothing runs while the app is backgrounded; an unconfigured
transport is a quiet no-op; manual *Sync now* bypasses jitter and the
foreground check.

*Why recorded here rather than left as code comments.* These are product
commitments as much as implementation choices — the 15-minute tick in
particular trades off battery and traffic against how stale a second device's
view is allowed to feel, and retuning it should be a deliberate decision, not
a side effect of an unrelated change.

### V2-D37 · Cloud sync is a Pro capability, gated only at the network drain

`lib/capability/entitlement.dart` (`cloudSyncAvailableFor`) answers whether
this device may use the cloud service; `ForegroundMultitasking.cloudSyncAvailable`
carries that answer to the composition, and `SyncComposition.resolve` in
`lib/features/v2_composition.dart` is the one place it is asked — the closure
handed to `SyncScheduler` as its transport, re-evaluated on every opportunity
rather than latched at startup. A capability gained while the app is running
nudges the scheduler the same way a network reconnect does; losing it needs no
nudge, because the resolver starts answering null and the next opportunity is
a quiet no-op.

Nothing else moves. Local writes, the outbox and every read stay ungated
(V2-D7): a Free device's outbox keeps journaling exactly as a Pro device's
does. `Settings → Sync` shows a locked *Cloud sync* row and nothing else for a
Free device — no pending count, no state sentence, no *Sync now* — because
that furniture would describe a drain that is not going to run
(`lib/features/settings_screen.dart`).

*The accepted cost, recorded once.* A device that never upgrades keeps
recording sync intents into an outbox that never drains. Nothing prunes it and
nothing caps it — the outbox is by-design unbounded on a permanently-Free
device. That is a deliberate consequence of the gate sitting on the network
drain and nowhere else (V2-D7), not an oversight; a retention or compaction
policy for it is Productization work ([V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md)
P2, P3).

### V2-D38 · Pull defers parent-less rows to a fixpoint; soft references land null and fill later

`lib/sync/pull.dart` holds back a row whose parent is not local yet, retries
every held-back row after each later page and again at the end of the run,
and pins the persisted cursor at `min(page's last revision, lowest deferred
revision − 1)` so an interrupted run always re-offers the first row it could
not apply. What is still waiting once the feed reaches head is treated as an
orphan — the parent exists nowhere in the feed — and is dropped, counted, and
allowed to fall behind the cursor rather than pin it forever.

A **soft reference** — `preferred_source_id` on a Collection,
`resolved_into_source_id` on a Source — does not hold the row back the way a
hard parent (a Collection's Folder, an Entry's Collection) does. The row
applies with the pointer left null and is retried only to fill that pointer
in; it is never counted as an orphan for a reference that never resolves,
because the row it names is already real without it.

*A known limit.* A page just fetched can still be behind a row that landed on
the server between the last page's fetch and the moment the run decides it is
at head, so the run confirms with one more fetch before calling anything an
orphan (`confirmedHead` in `pullAll`). That narrows the window to one
uncertain page rather than the whole run, but does not close it to zero — a
row created on the exact page boundary between the confirming fetch and the
decision remains a live possibility this design accepts rather than
eliminates. See [V2_SYNC.md](./V2_SYNC.md) §4.3.

### V2-D39 · A device's root Folder is mapped onto the server's at the first pull, journaling no outbox intent

`FolderRepository.ensureRoot` (`lib/data/folder_repository.dart`) inserts the
one local root Folder a device needs before it can place anything, and does
not append an outbox row for it — there is no "create the root" intent to
send, because a device's root and the library's root are the same fact
(I1) and not something one device gets to originate. When `lib/sync/pull.dart`
meets the server's root Folder for the first time, it maps it onto the local
root rather than treating it as an unrelated create (`_applyFolder`,
`kind == 'root'`).

*Why.* The server's identity model has exactly one root per library
(V2-D21). A device that minted its own root locally and then received the
server's would either hold two roots or need special-case reconciliation the
day it first syncs. Recognising the root by its kind, once, avoids both.

### V2-D40 · Browsing recognises into the library only through a followed Collection or a standalone Entry

`recordCompletedVisit` (`lib/features/v2_composition.dart`) is the one place
a completed, user-initiated navigation is turned into either a library write
or a history row (roadmap F6). It asks the recogniser
(`lib/recognition/recognise.dart`) what the page is, and only a
`RecognisedLocation` whose `authorisesLibraryUpdate` is true — a standalone
Entry's Location, or one on a followed Collection — records access
(`recordAccess`, never completion: I16, V2-D9). A page on a *known* Source
whose Collection has stopped being followed, and anything the recogniser does
not know at all, is device-local history and nothing else.

*Why.* Following is the sole authorising act (V2-D13). A page that happens to
match a Source the library once followed must not silently re-expand a
library the user chose to stop keeping current — that would make Archive a
suggestion rather than a decision. Browsing alone never creates a Collection,
an Entry or a Location; the only route from history into the library is the
one-tap promotion the user makes.

### V2-D41 · Placement is a local write when no sync service is configured or reachable

`placementSubmitFor` (`lib/features/v2_composition.dart`) applies a placement
locally (`localPlacementSubmit`) whenever this build carries no service
address, or the device is not currently entitled to use the one it carries
(`v2.sync.resolve() == null`) — the same gate the sync drain asks, asked
again at the moment a placement is submitted, so the two can never disagree
about whether this device has a service. Only when a service is both
configured and reachable does placement go through `PlacementService` for
server-side arbitration.

*Why.* Server arbitration exists because two devices placing the same
unplaced Entry differently is a contradiction only a second device can create
(§4.6). A device with no reachable service has no second device to
contradict, so applying the position the user typed, locally, and journaling
the same intent a synced device would send is not a lesser behaviour — it is
the correct one for the situation, consistent with V2-D7.

### V2-D42 · Collection removal reaches every device; archiving stops only queued downloads

*Remove from library*, at Collection scope, removes the Collection and its
Entries library-wide and leaves every device's downloaded bytes untouched
(I14) — `_removeCollectionFromLibrary` in `lib/library_ui/collection_actions.dart`.
*Archive* stops following without removing anything, and additionally cancels
this Collection's **queued** downloads (`cancelWaitingDownloadsOf`, filtered
to `SaveTaskState.queued`); a download already running is left to finish,
because archiving is not a stop and this app never offers a stop that does
not stop.

The V1 `CollectionDeletionService` (`lib/library/collection_deletion.dart`) is
retired; its file-and-row transaction is superseded by the V2 repository path
above plus the OfflineCopy cascade (I14).

---

### V2-D43 · The Library is one page; Folders are collapsible sections on it

The first Library shelf drew one Folder per screen and navigated into a Folder
(the "flat-first" reading of V2-D21 / O-A). In use that made the home screen a
folder browser: the Collections were a level down, and the app-level doors —
Settings, Activity, device storage — had no header to live in.

The Library is the home screen and it is **one page**: Continue Reading, then
the Collections and standalone Entries at the root listed directly, then every
Folder as a section on the same page with its contents drawn in place. A
section expands and collapses; the state is session memory only, never
persisted and never synced. A Folder inside a Folder is a section inside a
section. Nothing has to be in a Folder, and making one is a Library-menu action
rather than a header button. The model is unchanged — single system root,
conservative delete, Folder state syncs (V2-D21).

### V2-D44 · A page's shape is read structurally, and an uncertain serialized page is never silently standalone

Recognition answers *which rows do we hold for this address*. It deliberately
says nothing about what the page **is**, and for a long time the save flow
inherited that silence: anything recognition could not place became a
standalone Entry in the root Folder. One numbered Entry of a serialized work,
read on a site the library did not already hold, was reduced to a loose item
with no Collection, no Source, and no way to attach it to one.

`readPageShape` (`lib/recognition/page_kind.dart`) answers the missing question
from structure alone — a printed number by `parseEntryNumber`, or an address
sitting below a collection path by `collectionFingerprint` — with no hostname,
selector or site list. Its three answers are entry page, collection index and
*did not say*, and the third is a real answer: the user is asked which
Collection this belongs to, rather than having the question resolved by
writing a loose Entry.

The **collection index** answer is deliberately the narrowest of the three: it
is returned only when the caller can name the Source path this address is, so
in practice only for a site the library already holds. An address alone cannot
separate a work's listing from an about page — both are a path with no number
and nothing under it — and an app that guesses offers *add this collection to
your library* over a privacy policy. Where the shape merely allows it, the
sheet offers adding the site as a Source as one answer among three, and asserts
nothing. Standalone stays a first-class outcome (I3) and stays
available; it is chosen, never defaulted to. A collection index page never
becomes an Entry at all — a listing is where a Source lives.

### V2-D45 · Collection identity across sites is the user's answer, never inferred from a title

V2-D16 settled how two Sources of one Collection reconcile *once both exist*.
It left open how the second Source comes to exist at all, and the implemented
answer was: it cannot. Arbitration resolves `(host, path_key)` against Sources
the server already holds, so a genuinely new host is always `unresolved` —
correctly, because matching two differently hosted works by title similarity is
exactly the wrong merge V2-D16 refuses to make.

So the second Source is created by the person who knows. The save sheet offers
the Collections the library already holds, filtered by the detected title as a
*suggestion*, and the user taps one: *add this site as another Source of that
Collection*. Nothing auto-selects, and a detected title never matches anything
on its own. `LibraryAdoption` (`lib/recognition/adopt.dart`) is that operation,
and it writes Collection, Source, Entry and Location together rather than
creating a standalone Entry and repairing it afterwards. A `(host, path_key)`
that already belongs to another Collection is refused in words, never moved:
a site that relocates is a lifecycle change (V2-D14), not a reparenting.

Automatic cross-host matching remains unimplemented and is not claimed
anywhere. Reliability over false universality (PRODUCT.md §5.3).

### V2-D46 · "How many entries" comes back, on the bound it always had

`SaveScope` and `SaveLimits` survived the V1 retirement untouched in
`core/config.dart` — and were left with no caller, because the sheet that asked
the question was retired with the V1 queue in `b0740eb`. The restored sheet
asks it again and builds its limit the only way the codebase permits, through
`SaveLimits.forScope`, clamped to `SaveConfig.maxEntriesPerRun`. There is still
no open-ended scope, the default is still the one page in front of the user,
and the typed count is still a number the person chose and can see.

What changed is what a count *means* in V2. V1 walked from page to page as it
saved. V2 separates the two acts that were folded together there: finding
entries is the update check — visible, bounded, cancellable, and the only thing
that opens a page — while `SaveScopePlanner` (`lib/save/save_scope.dart`) turns
a count into queue rows over Entries the library already holds. A plan shorter
than the count asked for is reported as short, never padded with an address
nobody has seen. Library membership, Entry existence and OfflineCopy stay three
separate facts (PRODUCT.md §2.3): following downloads nothing, and downloading
follows nothing.

### V2-D47 · A typed count is a claim about the Source, and reading one forward is gated like a check

V2-D46 restored the question and left the answer where the V2 rewrite had put
it: a count was planned against Entries the library already held, so ten from
entry 101 queued the four the library happened to know and reported the
shortfall. That is a truthful answer to a question nobody asked. A person
reading entry 101 who asks for ten means 101 through 110 — a claim about the
**Source**, not about the library — and the library not having seen 105 yet is
the reason they asked.

So the count sheet returns which of the two it is
(`SaveScopeChoice.discoverMissing`). *Entries from here* is the default sense
of a count and is answered by `SourceWalk` (`lib/recognition/walk.dart`):
reading forward along the Source the reader is on, from the Entry in front of
them, reconciling each page through `EntryReconciler` before anything is
queued. *Entries already in your library* keeps the quieter answer, plans
against `SaveScopePlanner` alone and opens nothing. Both count the Entry the
user is on as the first one, and the sheet says so in words.

Three properties hold the line, and none of them is new:

- **The walk follows only what a page asserts.** The next address is whatever
  `resolveNextPage` reads from the page's own links — the resolver capture
  already uses. A number in a URL never manufactures the address after it, and
  an address that leaves the Source ends the walk (V2-D15, V2-D44).
- **It is bounded twice and it stops rather than guesses.** The typed count,
  clamped by `SaveLimits.forScope` as it always was, and `kMaxWalkPages` pages
  opened. End of chain, an unreadable page, a next control only the user can
  identify and a cancellation are each a named stop, and every Entry already
  resolved stays in the library. "There were only six" is an answer about the
  Source, not a failure.
- **It is gated exactly as the update check is**, through
  `showStartOptionsSheet` with `ForegroundGateAction.startEntrySave`, because
  it navigates. The question is asked before the run rather than at the first
  missing Entry — whether a page has to be opened is what the walk finds out,
  and asking afterwards would be asking permission after the fact. A count of
  one, and the library-only range, open nothing and are never gated. The gate
  decides where the user waits and never whether the work happens; nothing on
  this path is capped, truncated or slowed by it.

Finding Entries and downloading them stay two acts (PRODUCT.md §2.4): the walk
writes Entries and Locations and queues rows, and not a byte is captured until
the explicit Start.

### V2-D48 · Archiving marks a Collection; it does not move it to another screen

V1 had an Archived screen. V2 has one Library page (V2-D43), so archiving
writes `lifecycle` and the row keeps its place with an *Archived* chip. Nothing
is hidden, so nothing has to be gone looking for — which is what "archived
content remains discoverable" actually requires. A second screen would be a
second place for the same rows to be, kept in step by hand.

### V2-D49 · The save preflight offers only the states V2 can tell apart

V1 classified six already-saved states and offered eleven choices, several of
them resumes. V2's capture has no resume: a re-save reads the page from the
start. So the preflight asks one question in two forms — *already downloaded,
download again?* and *this copy is incomplete, download again?*, the second
naming how many images are missing — and offers nothing else.

Offering a recovery the engine cannot perform is worse than not offering one.
The V1 choices that described a resume are not restored, and
`unknownEntryEstimate` is not restored either: an estimate for a Collection
nothing has been downloaded from is a guess wearing an estimate's clothes, so
the sheet says nothing about size instead.

### V2-D50 · A Collection's check state is session memory

V1 persisted four check columns per Collection. V2 keeps the same information
— *Not checked yet · Checking · N new · Checked ‹when› · Check failed*, the
vocabulary `checkLook()` already had — in memory for as long as the app runs,
for the reason V2-D43 gives for collapsed Folders: the schema is frozen at
version 1 with no migration path, and a check is cheap to repeat.

*Not checked yet* on a fresh launch is honest, and is exactly what a user who
has not checked since launching should see. A reading that concluded nothing
never stamps a time: "Checked 2 minutes ago" over a site that would not load is
the same lie the old single sentence told.

## Open

Only items that are genuinely undecided **and** not already deferred to
Productization.

| # | Question | Blocks |
|---|---|---|
| O-A | ~~Whether the nested-folder UI ships in the first functional release, or only flat folders over the hierarchical schema~~ Resolved by V2-D43: nested Folders are drawn in place as sections of the one Library page | Closed |

Everything else previously open — authentication, monetization, tombstone
retention, cross-device unreadable Sources, cross-source progress presentation,
privacy and store declarations — is deferred deliberately and lives in
[V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md).

### V2-D51 · A count means captures, and the walk's own answer is what gets queued

`v2AddAndDownload` planned against the library, walked the Source for the
shortfall, and then **re-planned against the library** to decide what to queue.
That looks equivalent and is not. `SaveScopePlanner` takes a Collection's rows
in ordinal order from the starting Entry, and `EntryReconciler` writes an Entry
with no position whenever the page printed no number *or* the Collection's
ordering basis does not support cross-source merging (V2-D16). Those Entries
are real, addressed and downloadable — position is organisation, not permission
— and the re-plan could not see them, so a count the Source had just satisfied
came back with nothing queued for them.

A `WalkedEntry` already names the Entry and the Location. Those are the
targets: the library's plan first, then the walk's own entries, de-duplicated
by Entry so a merge is not a second row. The count means **captures**, not
discoveries, and `test/save_v2/capture_journey_test.dart` asserts it as
OfflineCopies on the device rather than as rows in a queue.

### V2-D52 · One launch decision, carried to the thing that starts

Starting was split across two sheets that did not know about each other:
`SaveScopeChoice.startNow` decided whether the queue's Start was called, and a
separate `showStartOptionsSheet` — asked to authorise the reading — returned an
answer the save flow could only honour by flipping the shell tab. *Add to
queue* followed by *Start in Browser* therefore showed the user the Browser and
started nothing, and a user who chose *Start now* was asked twice more where
they would like to wait.

The sheet that asks *how many* now asks *and what happens next*, with three
values on `SaveStartMode`: **Queue only**, **Start now**, **Start and keep
using Scrollary**. The rows are the foreground gate's own widget, supplied by
`features/v2_save_flow.dart` because `lib/library_ui/` may not import
`capability/`; the answer travels to the Start as `StartWhere`, so nothing asks
again. Consent for opening the site is unchanged and still comes first — it is
the sentence under the count, before anything is opened.

### V2-D53 · A Collection remembers what it is saved as; the page still decides

Capture mode was a queue-row column, so *What to save* was asked identically on
the first entry of a work and the five-hundredth. `CapturePreferenceStore`
keeps the user's **explicit** answer per Collection in the settings table —
which documents itself as the home for a preference that would otherwise be a
column, a migration and a registry entry, and which keeps the schema frozen.

Three rules make it safe. It records only a choice the user made, because a
detected mode is the page's answer about that page. It never forces one:
`CaptureCapabilities.resolve` — which already described itself as "the one
place a stale collection preference is stopped from forcing an impossible
save" — falls back on a page that cannot honour it, and the preference is left
alone, because it was an answer about the work. And a standalone save writes no
preference at all, so an Entry-specific choice cannot redefine a Collection it
has nothing to do with. *Ask each time*, on the Collection menu, stays
expressible: there is no safest capture mode, so no answer has to remain a
statable one.

### V2-D54 · Reading at a Source is measured; reading a copy is anchored

V2 has had a Measurement model keyed `(entry, source)` since Gate C and nothing
in the app ever wrote one — `MeasurementRepository.put`'s only caller was the
sync *pull* path, so every measurement a device held had been taken somewhere
else. Reading an Entry on its own site recorded that it had been opened and
nothing about how far, and `EntryProgressRing` existed, was tested, and was
drawn on no screen.

`SourceReadingMeter` writes a Measurement from the page's own geometry, for the
Entry the composition has just recognised. It refuses a page no taller than the
viewport — that page has no position to be at, and a figure for it would be a
claim about a reading nobody can observe — refuses a probe of an address it is
not watching, and never lowers a stored fraction, because a reload and a scroll
back to check a name are not un-reading. It is never taken while automation
owns the Browser: a capture scrolls to the bottom to enumerate a page, and
counting that as a reading would mark an Entry read by downloading it.

The OfflineCopy half is unchanged in what it stores — the anchor, an index into
*these* bytes — and now *derives* the fraction from the panel count the
manifest already carries, so a reopened image reader shows the right percentage
on its first frame instead of 0% until it has measured itself. A document keeps
0: a paragraph has no height until it is laid out at this width.

### V2-D55 · Inside a Collection, an Entry's position is its identity

Every row in a Collection printed the whole title a site had written for the
page. On a serialized work whose site titles its pages with the work's own name
that produced a list where the only thing that varied was three digits at the
far right of four otherwise identical lines — noise, and worse, it made an
ordered work look unordered.

`library/entry_presentation.dart` is the one rule, and it takes an
[EntryContext] because the same Entry needs different things said about it in
different places. **Inside the Collection** the work is named at the top of the
screen, so the row leads with the position — `101`, `99.5` — and carries the
Entry's own title underneath only when that title says something the position
and the work's name have not. **Across the library** — Continue Reading,
Activity, a search result — nothing above the row says which work this is, so
the row names itself: `Quiet Harbour · 101`. There is deliberately no global
rule that strips a Collection's name; a caller says where it is drawing.

**Two removals, both narrow, and neither touches a stored row.** The work's
name goes only as a whole token, so `"Quietly"` keeps every letter. A marker
goes only when it names *this Entry's own number*: `"Part 101"` leaves Entry
101 and stays on Entry 7, because on Entry 7 the 101 is something the title
knows and the row does not. What survives both is returned as the site wrote
it, so `"Part 101 — The Quiet Night"` becomes `"The Quiet Night"` and
`"Prologue"` stays `"Prologue"`.

**Nothing is deleted to make the row quieter.** *Entry details*
(`library_ui/entry_details.dart`) is the record: the stored title verbatim,
what the source printed, the position, the address, the Source, whether the
Collection can be read elsewhere, the reading state and whether this device
holds a copy — the four independent facts as four lines, and no verb on the
sheet at all. A presentation rule with no way back to the evidence is a
deletion wearing tidiness as a disguise.

Identity, ordering and reconciliation are untouched: `_bySequence` already
sorted by ordinal, `entries.ordinal` is unchanged, and one Entry read from two
Sources is still one row.

### V2-D56 · *The next N from here* is one sequential journey, not a survey then a download

`v2AddAndDownload` answered a count about the Source in two phases: walk the
Source until N Entries were resolved, write them all into the library and the
queue, then capture them one by one. Both phases open every page. A count of a
hundred was a hundred page loads during which nothing was downloaded, followed
by a hundred more to download them — and the user, who had asked to capture the
next hundred *from the entry they were reading*, watched a browser move through
the whole range before the first byte was kept.

The two phases are now interleaved, and the alternation is
`save/capture_journey.dart`:

```text
capture this entry → find the next → capture it → find the next → …
```

Four things follow from that order, and they are the point of it:

- **The entry in front of the user is captured first**, before any address
  after it has been so much as resolved. It is the only one whose identity was
  already known, so it is also the only row the sheet writes.
- **Discovery is one step, taken when it is needed.** `SourceWalk.forward`
  gained an `onEntry` hook that is awaited as each Entry is resolved — *on the
  page the walk has just opened* — and the walk goes no further until it
  answers. Everything about which Entry a page is stays `EntryReconciler`'s.
- **One page load per Entry.** The walk opens the page to find out which Entry
  it is; the capture then reads that same loaded page
  (`PageCaptureSource.capturePage`'s `pageAlreadyLoaded`, asserted against the
  browser's own address rather than trusted). The flag is never inferred: a
  page the *user* has been reading has been scrolled, and the engine scrolls
  downward from where it finds the page.
- **The bound is the number the user typed.** `QueueRunner` is told the
  journey's count, so *Entry 4 of 20* is true from the first entry rather than
  derived from a queue that only ever holds the step being taken, and a run
  that ends at sixteen says *16 of 20* with the reason underneath.

**Ending early is an answer.** A Source with nothing published after its
sixteenth entry ends the journey with sixteen captures and a sentence about the
Source (`RunSummary.endNote`) — not a failure, and nothing between seventeen
and twenty is invented.

**One operation, one stop.** Stopping the running download ends the journey: no
further page is opened and no further row is written. The separate *stop
finding entries* control went with the separate phase it stopped —
`SourceWalkCancellation` and the panel's *Finding entries* state are gone,
because reading forward is no longer a state the app is ever in on its own.
What replaces them is the download's own Stop, on the panel, in Activity and in
the save sheet that started it (docs/V2_CAPABILITY_PARITY.md).

This supersedes the second half of V2-D51. Its rule survives intact — **a count
means captures, not discoveries, and what the walk resolved is what gets
captured** — but "the plan first, then the walk's entries appended, then the
queue" is not how the count is answered any more, because there is no longer a
moment at which the whole range is known.

*Queue only* still queues and starts nothing: it writes the one row and holds
the journey on the runner, in memory, exactly as the Start authorisation is
held in memory (`queue_repository.dart`). A relaunch has neither.

### V2-D57 · Starting a Collection is the picker, then one sheet

New Collection creation from the Entry save flow uses the existing Collection
picker first, then one combined Collection-name + save-scope sheet. Naming and
scope are not separate modal steps.

The path it replaces had three surfaces between *Add to a Collection…* and the
thing that saves: the picker's list, the picker's own naming state, and the
scope sheet. The middle one held a single text field, and the sheet after it
opened by printing that field's value back — *From Quiet Harbour, starting at
this page.* A whole screen for one answer that the next screen states as a
fact is a step, not a question.

So the header line becomes the field. `showSaveScopeSheet` takes a
[NewCollectionNaming] — the suggested name and the host about to become the
Collection's first Source — draws `collectionNameField` where the subtitle was,
states `First source · host` under it rather than saying "this site" without
naming it, and returns the trimmed answer on `SaveScopeChoice.collectionName`.
A blank name is refused where it was typed, exactly as a blank count is, and
identity is validated before the number: complaining about the count under a
nameless Collection would answer the second question first.

**The picker stays, and stays first.** Skipping it is what would make this
unsafe: the Collections the user already holds must be visible before another
is started, or a work they already have from one site quietly becomes a second
Collection when they save it from another — the duplicate V2-D45 exists to
prevent. What changed is only what *New collection* costs after the list has
been seen. `showCollectionPicker` gained `confirmNameHere`, and the flag is
answered by whether a sheet follows: a listing is not an Entry, nothing follows
it, and it still names the Collection in the picker as it always did.

Nothing about the write changed. `LibraryAdoption.createCollection` is still
called once, after every answer is collected, and still writes Collection,
Source, Entry and Location in one transaction — the four surfaces before it
never wrote anything, which is what made the collapse a question of order
alone. Folder is not asked here and root remains the answer (V2-D21).

The other rule this keeps is the one that decides which collapse was allowed.
The picker's list and its name field are still never on screen together:
"naming a new Collection and picking an existing one are two answers to the
same question, and offering both at once is how a tap lands on the wrong one."
Moving the field to the next surface honours that; putting it beside the list
would not.

### V2-D58 · A Collection's capture preference is resolved at the capture seam

V2-D53 gave a Collection a standing answer to *what to save*, and the only
thing that ever read it was the Browser's save sheet. The read lived in
`_V2SavePanelState`, so it applied to exactly one surface: a Collection kept as
*Images only* was captured as images when the save started on the page, and
detected afresh when it started anywhere else — *Download for offline* from the
Library, the bar after a check, the reader's repair of a partial copy, a
download requested by another device.

V1 did not have this problem, and the reason is where it put the fallback. Its
run resolved `requestedCaptureMode ?? the collection's preferred mode` per
entry, inside the loop that captured them, so every capture went through it
whatever had started the save. V2 moved that decision up into a widget.

It moves back down. `EntryCaptureService.capture` — the one seam every capture
passes through, whatever wrote the row — resolves:

```dart
final requestedMode =
    captureMode ?? await capturePreferences.of(entry.collectionId);
```

and `CapturePreferenceStore` is a **required** collaborator, so a construction
site cannot quietly omit it and lose the behaviour again on the paths it was
lost on before.

Four properties make this safe rather than merely convenient:

* **An explicit mode wins.** A person answering on the page outranks a standing
  answer about the work, so a row that names a mode is untouched.
* **A standalone Entry inherits nothing.** No Collection, no fallback —
  inventing one would be an instruction from nowhere (I3).
* **It is not a person's choice.** `captureModeIsUserSet` is not set by this,
  so the manifest still distinguishes "somebody chose this" from "this is what
  the work is normally saved as".
* **The page still decides.** The preference arrives as `requestedMode`, the
  same input an explicit choice arrives as, and `CaptureCapabilities.resolve`
  inside the engine is what says whether this page can honour it. A Collection
  kept as text still falls back, with an explanation, on an entry that has none.

**Resolved at capture, never copied onto the row.** The alternative — reading
the preference at each `enqueue` — would need every call site to remember to do
it, would miss the next one added, and would freeze the answer that happened to
be in force when the row was written. Rows wait for an explicit Start, so the
answer that counts is the one in force when the capture actually runs.

Two questions this deliberately does not answer: whether accepting an
already-preselected mode should count as choosing it (today only an explicit
tap remembers), and whether deleting a Collection should delete its
`capture_mode.<id>` setting (today the key is orphaned, harmless, and never
reused).
