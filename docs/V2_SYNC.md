# V2 sync, backend boundary and client contract

> **Status: built and merged on `master`** — the backend (B1–B11), the sync
> engine (G1–G7) and the frozen contract below. This document owns the
> synchronisation model, the backend responsibility boundary, the shared API
> contract and the browser-extension contract including Download to Mobile.
> The extension itself is not built; everything else here describes running
> code.
>
> Domain and ownership: [V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) · Product:
> [PRODUCT.md](./PRODUCT.md) · Deferred: [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md)
> · Decisions: [DECISIONS.md](./DECISIONS.md).

## 1. What synchronisation promises

> **Local work is never blocked by synchronisation. Synchronisation is automatic,
> best-effort and resumable, and it is safe to interrupt at any point.**

Three separate guarantees, and the middle one is new in V2:

1. **Durable local state, always.** Every mutation commits locally and is visible
   before anything touches the network.
2. **Automatic convergence, best-effort.** Metadata sync runs on its own,
   opportunistically, without the user asking. It is not a user-started
   operation and it is not visible in normal use.
3. **Reliable continuation.** An interrupted sync resumes from where it stopped
   the next time the app has an execution opportunity. Nothing is lost by a kill,
   a crash, a dropped connection or a week offline.

**What it does not promise.** Permanent background execution. iOS and Android do
not offer it, so the product does not claim it. Sync runs when the app has a
reasonable opportunity; between those opportunities, local state is durable and
that is the guarantee that matters.

### 1.1 The rule this supersedes

V1 holds that *every network operation is user-started, visible and cancellable*.
That rule now applies to **content-affecting source automation only** — capture,
source traversal, update checking, anything that drives the browser. Lightweight
metadata synchronisation is exempt: it fetches no page, drives no browser, saves
no content, and is invisible when it succeeds. See
[DECISIONS.md](./DECISIONS.md) V2-D20.

## 2. When sync runs

Implemented in `lib/sync/scheduler.dart` (`SyncScheduler`) and
`lib/sync/retry.dart` (`RetryPolicy`) — roadmap G5–G6.

| Opportunity | Behaviour |
|---|---|
| App launch | Requested immediately; the run itself starts after a jittered delay (up to 3s) |
| App resume to foreground | Same jittered delay, skipped if the last opportunity was inside the last 2 minutes |
| Network reconnect while in front | Requested immediately (same jitter), and clears any backoff |
| A local mutation | Journalled immediately; the run is debounced up to 5s so a burst of edits becomes one push |
| Foreground idle | A tick every 15 minutes while the app is in front |
| Platform-supported background execution | Not hooked up. Nothing runs once the app is not in front — leaving the foreground cancels every timer |
| Manual *Sync now* | Runs immediately, with no jitter and no foreground check — the only trigger that does either |

Two more rules the scheduler holds:

- **Never two at once.** A run in flight absorbs every trigger that arrives
  during it into one follow-up; the follow-up itself is bounded to a single
  extra pass, so a steady trickle of local mutations cannot keep the loop
  turning indefinitely.
- **A failure waits longer each time.** Backoff starts at 30 seconds, doubles,
  and is capped at 30 minutes, with a subtractive jitter (up to 20% shaved off
  a step, so the ceiling stays the cap and nothing more). A success, a
  reconnect or *Sync now* resets it to zero. An unconfigured transport is
  recorded as a quiet no-op (`neverConfigured`) — never an error, never
  retried.

The product semantics in §1 are what must hold; the numbers above are the
current implementation and may be retuned without changing them.

## 3. Sync state the user can see

Routine success is silent. `Settings → Sync` shows, without any of it appearing
in the reader:

- last successful sync;
- current state — idle, syncing, offline, retrying, blocked;
- pending local change count;
- a failure that needs attention, in words that say what happened;
- **Sync now**.

Nothing about routine sync appears in the library or the reader. A failure that
the user can do nothing about is not an alert.

## 4. Mechanism

### 4.1 An outbox of intents, not dirty flags

A dirty flag records that a row differs from the server. It cannot record a
deletion, because the row is gone — and deletion is the operation with the most
careful semantics here. Changes are therefore recorded as **events at the moment
of their transaction**: append-only, ordered, each carrying a client mutation id
so a retry after an ambiguous failure is safe.

### 4.2 Three merge characters, and no more

Every synced field falls into one of three, and none of them requires values to
be *combined* — only chosen.

| Character | Merge | Applies to |
|---|---|---|
| **Scalar** | Last write wins on the row clock | Folder name and placement, Collection rename and lifecycle, preferred Source, Source lifecycle, reading state |
| **Set** | Add wins; removal only via tombstone | Sources of a Collection, Locations of an Entry, Entries of a Collection, Folder children |
| **Keyed scalar** | Last write wins per key | Measurements, keyed `(entry, source)` |

That is an add-wins set with tombstones plus per-field last-write-wins. **No CRDT
machinery, no vector clocks, no per-field version vectors, no three-way merge.**
It converges across a phone, a tablet and an extension because the rules are
per-record and order-independent, not because of any distributed-systems
apparatus. If a future field genuinely cannot be resolved by choosing, that is
the moment to revisit — not before.

### 4.3 Revisions and the cursor

The server assigns a **monotonic revision per library**. Every synced row and
every tombstone carries the revision at which it last changed. A client's cursor
is the highest revision it has seen. `GET /changes?cursor=<revision>` returns
creates, updates and tombstones in revision order.

### 4.4 Order of operations

**Pull before push**, then pull again if the push produced server-assigned
identity. Pulling first means a local mutation is applied on top of the server's
current view rather than racing it, and it is what lets provisional identity be
canonicalised before the mutations that reference it are sent.

### 4.5 Provisional identity canonicalisation

Offline, the client mints a local UUID and works normally. On the next sync it
submits the evidence it gathered. The server returns either canonical identity, a
merge into something already known, or `unresolved`.

- **Canonical returned** — the client records the server id beside its permanent
  local id. Nothing local is renamed.
- **Merged** — the client rewrites its references to point at the surviving local
  row and tombstones the duplicate locally. File paths, which depend on local
  ids, are untouched.
- **Unresolved** — a visible state, not an error. The Entry stays unplaced and
  readable.

### 4.6 Placement arbitration

Ordinal placement is **serialised by the server**, so two devices placing the
same unplaced Entry differently is detected centrally rather than resolved by a
clock. A losing placement comes back as a conflict the user can see, consistent
with the refusal posture everywhere else.

### 4.7 Reading state and completion

Last write wins on the reading clock. **Completion is a value, not a floor** —
highest-progress-wins looks safer and breaks *Mark as unread*, which exists
precisely to lower progress. Every reading write stamps its clock.

### 4.8 What never crosses the network

OfflineCopy and everything about it · reading anchors · browsing history · the
save queue and its runs · capture attempts and errors · page hints · per-Source
check timestamps · derived Collection pointers · favicons · settings.

## 5. Removal semantics

| Operation | Scope | Syncs | Tombstone | Effect on bytes |
|---|---|---|---|---|
| Remove offline copy | Device | No | No | Freed **here only** |
| Retract a Location a Source stopped listing | Source | No | No | None. Each device reconciles its own reading |
| Remove a Location by hand | User | Yes | Yes | None. Copies keep their provenance snapshot |
| Remove a Source | User | Yes | Yes | None. Its Locations go; Entries stay |
| Remove an Entry from the library | User | Yes | Yes | **Kept** on every device, surfaced as no longer in the library |
| Remove a Collection from the library | User | Yes | Yes | Same |
| Archive a Collection | User | Yes | No | None. Reversible |
| Delete a Folder | User | Yes | Yes | None. Children reparent to its parent |
| Forget source-derived discovery | Source | No | No | None |
| Delete the account | Server | — | — | None. Devices keep their libraries |

**A remote mutation never deletes local bytes** (invariant I14). A removal that
arrives from another device takes library rows and leaves the package on disk,
surfaced as content no longer in the library with an offer to free the space. A
device offline for weeks cannot object to a deletion, so it is never asked to
obey one destructively.

**An Entry whose last Location is gone** survives if it carries anything of the
user's — reading state, a measurement, an offline copy, a correction — and is
dropped if it was only ever a listing. That is `isDiscoveredOnlyEntry` at its
correct level: the rule for what a Source's own reading may retract.

Tombstone **retention policy** is deferred to
[V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md). The architecture supports
tombstones now; how long they are kept is a production decision.

## 6. Backend boundary

**Go + Fiber v3 + managed PostgreSQL.** One stateless API service. No object
storage, no cache tier, no queue, no broker — nothing V2 functionality needs.

### 6.1 The server owns

- Canonical identity for Folder, Collection, Source, Entry and Location
- **Identity arbitration** — the canonical answer to "which Collection and which
  Entry is this evidence about". The core logic, and the reason this is a service
  rather than a CRUD layer
- Ordinal placement arbitration and the record of user-made placements
- Folder organisation state
- Logical reading state and scoped measurements
- Revisions, the change cursor, tombstones
- Mutation idempotency
- DownloadRequest lifecycle

### 6.2 The server deliberately does not

| Not this | Why not |
|---|---|
| Fetch or read third-party pages | Changes what the product is; the entire store-policy position rests on the app only requesting pages the user navigated to |
| Store page content or downloaded bytes | Re-fetchable, large, and a different legal posture |
| Discover Collections or Sources on its own | Requires fetching. Clients see pages; the server sees evidence |
| Enrich metadata from third parties | Introduces claims no source made |
| Store browsing history | The library is what you track; browsing is not |
| Model OfflineCopy or capture state | Device-owned by construction |
| Anything between users | No sharing, no collaboration, no cross-user signal |

### 6.3 Server tables

Only synchronised concepts. **Not a copy of the mobile schema.**

`libraries` · `folders` · `collections` · `sources` · `entries` · `locations` ·
`reading_states` · `measurements` · `tombstones` · `download_requests` ·
`mutations` (idempotency ledger) · `library_revisions` (the monotonic counter).

No `offline_copies`. No `history`. No capture state. No save queue. No blobs.

`reading_states` is a separate table rather than columns on `entries` for a
concrete reason: reading updates are by far the most frequent mutation, and a
separate row means a separate revision — so marking something read does not bump
the Entry's metadata revision and force every other client to re-pull metadata
that did not change.

## 7. Download to Mobile

The extension does not capture. It creates an **intent**, and a device with a
capture engine fulfils it.

```
extension: "Download on mobile"
  → backend records a DownloadRequest        (intent only, no content)
  → mobile pulls it on its next sync
  → mobile claims it
  → mobile converts it into an ordinary local save task
  → mobile's existing capture policy and validation apply, unchanged
  → mobile reports a terminal state
```

| Field | Note |
|---|---|
| `entry_id` | Canonical. What to download |
| `location_id` | Optional preference. Absent means "the preferred Source" |
| `state` | `pending · claimed · completed · failed · cancelled` |
| `claimed_by_device`, `claimed_at` | Minimal targeting — see below |
| `idempotency_key` | Supplied by the requesting client |
| `created_by` | A client label, for the requester's own UI |

**Rules that keep it from becoming something else.**

- The backend **never fetches** the content. It records intent and nothing more.
- A DownloadRequest is **not** OfflineCopy state and must never be read as one.
  The server still does not know what any device holds.
- **Claiming is a conditional update** — `pending → claimed` succeeds for exactly
  one device, the same single-winner pattern V1 already uses for its queue.
- **Idempotent by construction**: at most one non-terminal request per
  `(library, entry)`. Pressing the button twice does not queue two saves.
- **Mobile still decides.** The restricted-site policy, capture-mode resolution,
  bounds and every stopping condition are evaluated on the device, exactly as for
  a save the user started there. A refusal is reported as a terminal state.
- **A failed download never changes library membership.** The Entry is exactly as
  it was.
- **Device targeting stays minimal.** Any device may claim. Full device
  management would drag account and authentication work into the foundation, and
  is deferred to [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md).

## 8. Shared contract

### 8.1 Representation

The API is the shared contract. **No cross-platform code package is proposed** —
a Dart package a JavaScript extension cannot consume would not solve the
divergence it exists to prevent.

**An OpenAPI document is the right boundary here**, and is a Lane A deliverable.
The justification is concrete rather than fashionable: three languages — Dart, Go
and later JavaScript — must agree on the same payloads, and the two most
divergence-prone parts of this design are *evidence submission* and *mutation
shape*, both of which are structured records with many optional fields. A single
schema that all three generate or validate against removes an entire class of
drift that would otherwise surface as silent duplicates in someone's library. It
is written once at Gate B and frozen; it is not a runtime dependency.

### 8.2 Operations

Authentication wrappers are Productization work. The table below is the frozen
contract's actual surface (`contracts/openapi.yaml`). Every entity write —
Folder, Collection, Source, Entry, Location, ReadingState, Measurement —
goes through the one `POST /mutations` envelope rather than a per-entity
route; placement and the download-request lifecycle are the only synchronous
endpoints outside that envelope, because both need server-side arbitration
(§4.6, §7) rather than a stored mutation.

| Operation | Purpose |
|---|---|
| `GET /healthz` | Liveness |
| `GET /version` | Build identity and whether the dev namespace is enabled |
| `POST /identity/arbitrate` | Submit evidence; receive canonical identity or `unresolved` |
| `POST /mutations` | Submit a batch of idempotent mutations from the outbox — the envelope for every entity write |
| `GET /changes?cursor=` | Incremental pull: creates, updates, tombstones, in revision order |
| `POST /entries/{id}/placement` | Ordinal placement, arbitrated centrally |
| `POST /download-requests` | Create a Download-to-Mobile intent |
| `POST /download-requests/{id}/claim` · `/resolve` | Device claim and terminal report |

### 8.3 Client responsibilities

| Stays on the client, always | Moves to the server |
|---|---|
| Page detection and content-shape measurement | Collection identity resolution |
| Capture and capture-mode resolution | Entry equivalence and ordinal placement |
| The restricted-site capture policy | Normalisation used for deduplication |
| The completion policy | Conflict arbitration where central serialisation is needed |
| The display-label vocabulary | |

### 8.4 Extension capability matrix

Everything below except identity arbitration, placement and the
DownloadRequest lifecycle is one `entity_type` inside the `POST /mutations`
envelope (§8.2); the matrix names the entity a mutation carries, not a
separate endpoint.

| Operation | Mobile | Extension |
|---|---|---|
| Authenticate | Optional | **Required** |
| Submit evidence, receive identity (`POST /identity/arbitrate`) | ✓ | ✓ |
| `collection` mutation — follow, archive | ✓ | ✓ |
| `folder` mutation — create, rename, move | ✓ | ✓ |
| `source` mutation — add, lifecycle, preferred | ✓ | ✓ |
| `location` mutation — record a Location | ✓ | ✓ |
| `readingState` mutation — record access, set read state | ✓ | ✓ |
| `measurement` mutation — scoped `(entry, source)` progress | ✓ | Only if honestly observable |
| Place an unplaced Entry (`POST /entries/{id}/placement`) | ✓ | ✓ |
| Pull changes (`GET /changes?cursor=`) | ✓ | ✓ |
| **Create a DownloadRequest** (`POST /download-requests`) | ✓ | ✓ |
| **Capture / download content** | ✓ | **No** |

The extension does not capture because doing so would mean re-implementing the
restricted-site policy, the media rules, magic-number asset validation, manifest
writing and the atomic commit in JavaScript — a second safety-critical
implementation of exactly the parts that most need to exist once.

## 9. Development-only access

Production authentication is deferred
([V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md)). The functionality build needs
only enough for several development clients to address the same test library.

**Mechanism: an explicit development library namespace.** A client sends a
`X-Scrollary-Library` header naming a library; the server creates it on first use.

It must be, and is:

- **clearly development-only** — the server refuses to start with it enabled
  unless an explicit `SCROLLARY_DEV_MODE` flag is set;
- **not pretending to be security** — it authenticates nothing and is documented
  as authenticating nothing;
- **easy to remove** — one middleware, one config flag, one header;
- **non-distorting** — `library_id` is a real column the production account model
  will populate. Nothing about the domain changes when real authentication
  arrives.
