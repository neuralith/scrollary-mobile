# V2 architecture — domain, ownership, local model

> **Status: built, merged and composed on `master`.** This document owns the
> V2 domain model, its invariants, the state-ownership matrix and the local
> (device) architecture — `lib/domain` and `lib/data` implement it as
> described below, and `lib/features/v2_composition.dart` plus `lib/app.dart`
> wire it up as the app a user runs; the V1 library screens, queue, update
> checker and `CollectionDeletionService` have been retired.
>
> **The real-system harness proves this design against a real service.**
> `tool/e2e/run.sh` and `test/e2e/` run the suite over a real Go service and a
> real PostgreSQL, through the app's real repositories, including the
> no-outbound invariant (`test/e2e/h4_download_to_mobile_test.dart`,
> `test/e2e/support/e2e_support.dart`).
>
> Product intent: [PRODUCT.md](./PRODUCT.md) · Sync, backend boundary and client
> contract: [V2_SYNC.md](./V2_SYNC.md) · Sequencing:
> [V2_ROADMAP.md](./V2_ROADMAP.md) · Deferred work:
> [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md) · Decisions:
> [DECISIONS.md](./DECISIONS.md).
>
> [ARCHITECTURE.md](./ARCHITECTURE.md) remains the record of V1 as it was
> built, for historical reference; it is no longer the authority on current
> running behaviour.

## 1. The axiom being replaced

V1 has one load-bearing axiom: **an Entry is a URL.** It is not a field, it is
the identity of the row — `UNIQUE(collection_id, url_key)`, every lookup, the
discovery observation set, the file path, the manifest, the deletion matcher. One
rung up, `UNIQUE(host, collection_key)` means **a Collection is a site path**, so
a Collection cannot outlive its site.

V2 replaces both. The *algorithms* survive and move down one level:

| V1 concept | V2 role | Change |
|---|---|---|
| `normalizeUrl` → `url_key` | **Location** identity | None — same function, same tests |
| `collectionFingerprint` → `collection_key` | **Source** identity | None |
| `parseEntryNumber` | Source-reported number on a Location | Never Entry identity |
| `entry_identity.dart` review | Cross-source equivalence refusal | Scope widens, posture identical |
| `ObservedEntryWindow` | Per-**Source** retraction evidence | Scope narrows to one Source |
| `isDiscoveredOnlyEntry` | What a Source's own reading may retract | No longer the library boundary |

## 2. The domain

```
Library
└── Folder (root, system)            user organisation, a tree
    ├── Folder "Weekly"              user-created
    │   ├── Collection               a logical work
    │   │   ├── Source A   tr  active · preferred
    │   │   ├── Source B   en  active
    │   │   ├── Source C   —   dead → Source A
    │   │   └── Entry (ordinal 101)  logical unit, carries reading state
    │   │       ├── Location on A    a URL
    │   │       ├── Location on B    a URL
    │   │       ├── Measurement      scoped to a Source rendering
    │   │       └── OfflineCopy      device-local bytes + provenance
    │   └── Entry (standalone)       no Collection, owns its Locations
    └── Folder "Reference"

History                              device-local, never synced
DownloadRequest                      an intent, not content
```

### 2.1 Folder

A **Folder** is user organisation and nothing else. It carries no source
identity, no content relationship, and no Sources are ever attached to it.

- One **system root Folder** per library. `parent_id` is NULL only for the root.
  A device mints its own root locally (`FolderRepository.ensureRoot`) with no
  outbox intent — there is nothing to negotiate about a fact the library has
  only one of — and the first pull that meets the server's root maps it onto
  that local row rather than treating it as an unrelated create (V2-D39).
- User Folders nest via `parent_id`. Hierarchy is supported by the schema from
  day one; a nested-folder UI is not required to ship with it.
- Folders contain **Collections** and **standalone Entries**. Nothing else.
- An Entry inside a Collection has **no Folder membership of its own** — it is
  where its Collection is.

**Why a root Folder rather than a nullable placement plus an `Unfiled` folder.**
Two candidate models were considered: nullable `folder_id` meaning "library
root", or `folder_id NOT NULL` with a system `Unfiled` folder. A single system
root beats both. Every item then has exactly one parent, "move to folder" is
always the same operation with the same shape, every placement syncs as a value
rather than sometimes as a null, and no query needs a null branch. "At the
library root" simply means "in the root Folder", so nothing is lost. And with a
root present, a separate `Unfiled` folder would be a second name for the same
place.

**Folder deletion is conservative.** Deleting a Folder **reparents its children
to the deleted Folder's parent**. It never cascades into Collections or Entries,
and it never deletes content. Destroying a subtree is not offered as a side
effect of tidying.

### 2.2 Collection

A **Collection** is a logical work — a group of related Entries. It has **no URL
and no host**; those belong to its Sources.

- A Collection in the library **is followed**. Following is the user
  authorisation that lets Scrollary keep it current while the user reads.
- `archived` is how a user stops following without losing anything. Reversible.
- It carries an **ordering basis**, which decides whether cross-source Entry
  merging is available at all (§4.3).
- It names one **preferred Source**. Preference is a pointer on the Collection,
  not a flag on each Source, so there is exactly one place the answer lives.

### 2.3 Source

A **Source** is *this Collection, as published on one site*.

| Field | Note |
|---|---|
| `host`, `path_key` | Source identity. `path_key` is today's `collectionFingerprint` output |
| `language` | A translation is a Source, **not** a separate Collection |
| `lifecycle` | `active · dormant · dead · resolvedInto` |
| `resolved_into_source_id` | Set when a site moves; the old row stays and points forward |
| `first_seen`, `last_seen` | Evidence, not user state |

Active alternatives and historical predecessors are **the same structure with
different lifecycle**. A site that comes back is a state change, not a row moved
between tables. There is no separate source-history table.

### 2.4 Entry

An **Entry** is one logical unit of reading. It carries the reading state.

- `ordinal` — its position in the Collection's own sequence. Nullable: NULL means
  **unplaced**, a real and visible state.
- `collection_id` NULL means **standalone**. A standalone Entry is a first-class
  library item, owns its Locations directly, and lives in a Folder. It is never
  wrapped in a Collection of one.
- `placement` — `placed · unplaced · userPlaced`, so a position the user chose is
  distinguishable from one the app derived.

### 2.5 Location

A **Location** is *this Entry, at one URL, on one Source*.

- `url_key` is `normalizeUrl(url)` and is **unique within the library**. One URL
  is one place. This is what makes recognition a single indexed lookup.
- `source_id` is NULL for a standalone Entry's Location.
- Carries the source-reported label and number as **evidence** — never as
  identity.
- `lifecycle` — `active · retracted`. Retraction is source-scoped (§6.2).

### 2.6 Measurement

A progress reading, **scoped to the rendering it was taken against** — keyed by
`(entry, source)`.

A fraction measured against one Source's rendering is not an approximation of
another's; it is a fact about a different thing. So a measurement carries its
scope and the app never invents a number for a Source it has not measured. No
confidence scale is introduced; scope replaces it.

The **anchor** — an index and offset inside a specific artifact — is not here. It
lives on the OfflineCopy, because it is meaningless without the bytes it indexes.

### 2.7 OfflineCopy

Device-local bytes. **Never synced, in either direction.**

- One active copy per Entry per device. A re-download replaces it through the
  existing atomic commit-with-restore path.
- **Provenance is stored as values, not references**: the Location URL, the
  Source name, host and language, and the capture time, copied at capture. A
  Source can die and a Location can be retracted without orphaning a copy already
  on a device, and the copy can still say where it came from.
- Holds the reading anchor, the artifact format, the manifest reference, the
  stored path, byte size and integrity state.

### 2.8 History

Device-local, never synced. Everything the user reads that the library does not
claim. One tap promotes an item into the library. Cloud sync is not cloud
browsing history.

### 2.9 DownloadRequest

An **intent**, created remotely and consumed by a device. It is not content and
it is not OfflineCopy state. Full contract in [V2_SYNC.md](./V2_SYNC.md) §7.

## 3. Invariants

Numbered so tasks and tests can cite them.

| # | Invariant |
|---|---|
| **I1** | Exactly one root Folder per library. `parent_id IS NULL` ⟺ `kind = root` |
| **I2** | The Folder tree has no cycles |
| **I3** | An Entry has a Folder **iff** it has no Collection: `(collection_id IS NULL) = (folder_id IS NOT NULL)` |
| **I4** | Every Collection has a Folder |
| **I5** | Deleting a Folder reparents its children; it never deletes a Collection or an Entry |
| **I6** | `url_key` is unique within a library. One URL is one Location |
| **I7** | A Location belongs to a Source **iff** its Entry belongs to a Collection |
| **I8** | An Entry's `ordinal` is unique within its Collection when not NULL |
| **I9** | A Collection's preferred Source, when set, belongs to that Collection |
| **I10** | Reading state exists for an Entry regardless of Collection, Location count or OfflineCopy |
| **I11** | Nothing about an OfflineCopy is ever sent to the server or received from it |
| **I12** | A Measurement names the Source it was measured against |
| **I13** | At most one active OfflineCopy per Entry per device |
| **I14** | A remote mutation never deletes local bytes |
| **I15** | A Source's own reading may retract only that Source's Locations |
| **I16** | Completion is never inferred from a source read |
| **I17** | A DownloadRequest never carries or implies content, and its failure never changes library membership |

## 4. Identity

### 4.1 Four identities, deliberately distinct

| Identity | Of | Key | Assigned by |
|---|---|---|---|
| Canonical | Collection, Entry, Folder, Source, Location | Opaque server id | **Server**, from client-submitted evidence |
| Provisional | The same, while offline | Locally minted UUID | **Device**, reconciled on next sync |
| Source identity | Source | `host + path_key` | Client, deterministic |
| Location identity | Location | `url_key` | Client, deterministic |

Local UUIDs are **permanent primary keys**; a server id sits beside them and is
never written over one. File paths and manifests depend on local ids.

### 4.2 Arbitration, and what it is not

The client reads the page and submits **evidence** — URL, label, observed
numbering, page hints, host. The server decides which Collection and which Entry
that evidence is about and returns canonical identity.

**The server never makes an outbound request.** Arbitrating over evidence
clients gathered is a different thing from fetching pages, and the distinction is
load-bearing for the product's whole position.

The hot path stays local:

| Case | Answered by | Cost |
|---|---|---|
| `url_key` matches a known Location | Local index | One lookup, no network |
| Plausible new Entry of a followed Collection | Local, provisionally | Ordinal placement |
| Unknown | Server arbitration | One round trip, deferrable |

**What arbitration cannot answer.** It resolves evidence against Sources the
server already holds — `url_key`, then `(host, path_key)`. A genuinely new host
has neither, so the answer is `unresolved`, and no amount of matching titles
changes that: deciding that two differently hosted works are the same one is
the merge §4.3 refuses to make on a guess. That question is put to the user
instead, by the save flow, and their answer creates the Source
(docs/V2_SAVE_FLOW.md, V2-D45). Automatic cross-host matching is not
implemented and is not planned.

### 4.3 Cross-source equivalence, and where it is refused

Merging Entries across Sources needs something to key on. **Only an explicit
numeric ordering basis provides it.** The model states which mode a Collection is
in rather than degrading silently:

| Ordering basis | Cross-source Entry merging |
|---|---|
| `explicitNumericIndex` | **Available.** Equal ordinals merge |
| `publicationDate` · `detectedNextLink` · `discoveryOrder` | **Not available.** Sources coexist and are readable; Entries are not merged |
| `userDefinedManualOrder` | User-assisted placement only |

One implementation decides this for every caller: `EntryReconciler`
(`lib/recognition/reconcile.dart`), used by source discovery, by the update
check and by every save. A page saved from the browser on a Source the library
already holds goes through the same equivalence as a page found by reading that
Source's listing — the entry point differs, the rule does not.

Where merging is available, the rules are conservative:

- Equal ordinals → the same Entry.
- Different ordinals (100 against 99.5) → **two Entries**. Not merged, both
  visible, mergeable by the user later.
- No parseable ordinal, or a numbering restart that makes one ambiguous → the
  Entry is **unplaced**, holding its Location, visible and readable, offered to
  the user to place.

This is the posture `lib/library/entry_identity.dart` already takes inside a
single Source: ask whether two independent readings contradict each other, and
when they do, **stop and keep the contradiction** rather than repairing it. No
"drop the last digit", no "prefer the URL". Widening its scope is not a new idea.

## 5. State ownership

Four owners. Every field names one.

| Owner | Means | Syncs |
|---|---|---|
| **User** | The person decided it or did it | **Yes** |
| **Source** | A site said so; rediscoverable by reading it again | Yes, as evidence — never as truth |
| **Device** | True of this installation only | **Never** |
| **Server** | Assigned centrally so clients agree | Authoritative |

### 5.1 The matrix

| State | Owner | Local | Server | Sync behaviour |
|---|---|---|---|---|
| Folder tree, names, order | User | ✓ | ✓ | Scalar LWW; placement is a value |
| Collection membership (following) | User | ✓ | ✓ | Presence; archive is a scalar |
| Collection name / rename | User | ✓ | ✓ | Scalar LWW |
| Collection ordering basis, detected title | Source | ✓ | ✓ | Certainty only ever raised |
| Preferred Source | User | ✓ | ✓ | Scalar LWW |
| Source set of a Collection | User | ✓ | ✓ | Add-wins set; removal by tombstone |
| Source host, path key, language | Source | ✓ | ✓ | Immutable identity once assigned |
| Source lifecycle | User / Source | ✓ | ✓ | Scalar LWW |
| Entry existence, ordinal, placement | User / Server | ✓ | ✓ | Placement arbitrated centrally |
| Entry title, source number, label | Source | ✓ | ✓ | Fill-if-null; never overwritten |
| Location set of an Entry | Source | ✓ | ✓ | Add-wins set; retraction is source-scoped and local |
| Reading state | User | ✓ | ✓ | Scalar LWW on its own clock |
| Measurement `(entry, source)` | User | ✓ | ✓ | Keyed scalar LWW |
| Reading anchor | **Device** | ✓ | ✗ | Never |
| OfflineCopy, provenance, bytes, path, size | **Device** | ✓ | ✗ | Never |
| Capture attempts, errors, save queue, runs | **Device** | ✓ | ✗ | Never |
| Browsing history | **Device** | ✓ | ✗ | Never |
| Page hints | **Device** | ✓ | ✗ | Never |
| Per-Source check timestamps and results | **Device** | ✓ | ✗ | Never |
| Derived Collection pointers, unread counts | **Device** | ✓ | ✗ | Recomputed, never synced |
| Favicons | **Device** | ✓ | ✗ | Never |
| DownloadRequest | User | ✓ | ✓ | Lifecycle; device claims and acknowledges |
| Outbox, sync cursor, provisional map | **Device** | ✓ | ✗ | Never |
| Canonical ids, row revisions | **Server** | ✓ (cached) | ✓ | Assigned |

### 5.2 Two things V1 mixed, now separated

- **Download state sat inside library state.** `save_status`, `content_path`,
  `byte_size`, `artifact_format` and `offline_removed_at` were columns on the
  Entry row. They move wholesale to OfflineCopy, and the Entry stops knowing
  whether anything was downloaded.
- **Progress was one number pretending to be portable.** Reading *state* is on
  the Entry and syncs. A *measurement* carries its Source scope. The *anchor* is
  on the OfflineCopy and never leaves the device.

## 6. Local architecture

### 6.1 Local-first, without qualification for user state

```
user action
  → local transaction commits
  → UI reads local state
  → intent appended to the outbox
                          ⋮   independently, automatically, retryably
                 drain outbox → server
                 pull changes → reconcile through local guards
```

Every action completes against the device and is visible immediately. Offline,
the library, reading, organisation, downloaded content and local mutations all
keep working, and nothing is rolled back by a network failure.

The one deliberate exception is identity **assignment**, which is
server-authoritative when reachable and provisional when not — and even that
never blocks the action.

### 6.2 Three rules carried from V1, because they were learned expensively

- **Remote changes enter through repositories, never the DAO.** V1's reading
  writes are read-modify-write behind a serialised queue built specifically to
  stop a stale in-flight write clobbering a newer one. A sync path that bypasses
  it reintroduces that race, and it will appear to work.
- **Derived caches are recomputed after a batch, never synced.**
- **Reconciliation re-runs local refusals.** V1's `forgetDiscoveredEntry`
  re-reads the row *and the queue* inside the transaction that deletes it. That
  refusal is exactly as necessary when the request arrives from another device.
  **Sync the intent; re-run the guard.**

### 6.3 Recognition indexes

Recognition is the hot path, so the local store carries:

- `url_key` → Location, unique, indexed. One lookup, offline.
- `(host, path_key)` → Source, unique, indexed.
- `(collection_id, ordinal)` → Entry, unique where ordinal is not null.

These are the same indexes V1 already creates, pointed at the new levels.

### 6.4 Local tables

Designed from the domain rather than one table per noun.

| Table | Owner | Notes |
|---|---|---|
| `folders` | User | `parent_id` NULL only for root; `kind`, `name`, `sort_key` |
| `collections` | User | `folder_id NOT NULL`, `preferred_source_id`, `lifecycle`, ordering basis |
| `sources` | Source | `UNIQUE(collection_id, host, path_key)`, language, lifecycle, `resolved_into_source_id` |
| `entries` | User | `collection_id` nullable, `folder_id` nullable, CHECK enforcing **I3**, `ordinal`, `placement` |
| `locations` | Source | `UNIQUE(url_key)`, `entry_id`, `source_id` nullable, source label and number, lifecycle |
| `reading_states` | User | One row per Entry, own clock. **Separate table so the hot mutation does not bump Entry metadata revisions** |
| `measurements` | User | `PRIMARY KEY(entry_id, source_id)`, fraction, observed at |
| `offline_copies` | **Device** | One active per Entry; provenance as values; anchor; artifact; path; bytes |
| `download_requests` | User | Mirrored from the server, plus this device's own claim state (`local_save_task_id`) |
| `history` | **Device** | Unchanged in spirit from V1's `browsing_history` |
| `outbox` | **Device** | Append-only, ordered, mutation ids |
| `sync_state` | **Device** | Cursor, last-success and last-attempt time, last error |
| `save_queue` | **Device** | Ported from V1's `queue_tasks`, retargeted to `(entry, location)` |
| `page_hints`, `saved_sites`, `favicons`, `settings` | **Device** | Carried over unchanged |

**Server ids are nullable columns on each synced table**, never a separate
mapping table and never written over the local primary key.

**`save_runs` is deliberately absent.** It would be the resume record of a
Browser-driven traversal, and that orchestration does not exist in V2 yet (see
the header of `lib/data/schema.dart` and `lib/save/entry_capture.dart` for the
seam it waits on). Writing the table before its only writer would be a guessed
shape with no caller.

**`sync_state` has no pending-count column.** The count Settings shows is a
live read of unsent `outbox` rows, not a cached number — there is nothing to
keep in sync with the outbox draining.

**There is no local `tombstones` table.** A device's own deletions are outbox
`delete` rows, which *are* the record until the push lands; a remote
tombstone is applied by deleting the local row outright (guarded by
`tombstoneWins` against a racing local write), so there is nothing for the
device to remember afterwards. The server's `tombstones` table is what a
client that was offline needs to catch up on; a client that is caught up needs
none of its own.

## 7. What does not change from V1

The floor for the rewrite. None of this is up for revision:

- Capture and source traversal stay **explicit, visible, bounded and
  cancellable**. Save scopes stay bounded by a number the user typed.
- The restricted-site capture policy stays in one file, asked at every boundary,
  judging pages and never assets.
- Audio and video are never saved; the asset fetcher stays image-bytes-only by
  magic number.
- App-private storage only; no export to shared storage.
- A completed Entry is 100% read, enforced on write and on display.
- `CompletionPolicy` is unchanged: the only automatic route to `completed` is the
  measured threshold plus its dwell, in Scrollary's own reader.
- The manifest stays versioned; stored manifests are never rewritten in place;
  an unrecognised artifact resolves to `unknown` and says so.
- `AppPalette` is the only source of colour.
- `entry_labels.dart` stays the only producer of user-facing nouns.
- Nothing site-specific ships.

**One rule is deliberately split** — see [PRODUCT.md](./PRODUCT.md) §6.2 and
[DECISIONS.md](./DECISIONS.md) V2-D20: content-affecting automation stays
user-started; lightweight metadata synchronisation is automatic.
