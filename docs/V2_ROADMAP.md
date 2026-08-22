# V2 roadmap — worktree-aware execution plan

> **Two programmes.** *V2 Functionality* is this document. *V2 Productization* —
> authentication, monetization, deployment, legal, store — is
> [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md) and is deliberately not mixed in.
>
> Designed for parallel agentic development with Git worktrees. Every task names
> what it owns, what it must not touch, and what it may run alongside.
>
> Domain: [V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) · Sync and contract:
> [V2_SYNC.md](./V2_SYNC.md) · Decisions: [DECISIONS.md](./DECISIONS.md).

## 1. Classification

- **Foundation** — later work is wrong or must be redone without it.
- **Functionality** — required for the product to work correctly.
- **Integration** — proves lanes agree.
- **Hardening** — device validation, cleanup, regression.
- **Productization** — not here. See the other document.

## 2. Directory ownership

New V2 code lives in new directories so lanes do not collide, and V1 directories
retire at defined cleanup points (§10). No `v2/` prefix — these are the
permanent names.

| Directory | Lane | Contents |
|---|---|---|
| `scrollary-backend/**` | B | Go service, schema, migrations |
| `contracts/**` | A | OpenAPI document, shared vocabularies |
| `lib/domain/**` | C | Entities, invariants, pure rules |
| `lib/data/**` | C | Local schema, DAO, repositories, outbox |
| `lib/recognition/**` | F | URL → identity, evidence, discovery, checking |
| `lib/sync/**` | G | Outbox drain, pull, reconcile, scheduling |
| `lib/library_ui/**` | D | Folder, Collection, Entry presentation |
| `lib/save/**`, `lib/browser/**`, `lib/storage/file_store.dart`, `manifest.dart`, `document.dart`, `lib/features/reader_screen.dart`, `document_reader.dart` | E | **Ported.** Internals frozen; call sites change |
| `lib/library/**`, `lib/storage/database.dart`, `lib/reading/**`, `lib/queue/**`, `lib/features/**` (library screens) | — | **V1, retiring.** Deleted at §10 cleanup points |

### 2.1 Shared files that must stay serial

Never edited by two lanes at once. Changes to these are scheduled, not
opportunistic:

`pubspec.yaml` · `lib/main.dart` · `lib/app.dart` · `lib/providers.dart` ·
`contracts/openapi.yaml` (Lane A owns) · `scrollary-backend/migrations/**` (Lane B owns) ·
`lib/data/schema.dart` (Lane C owns) · every file in `docs/`.

## 3. Lanes

| Lane | Owns | Serialisation |
|---|---|---|
| **A · Domain & Contracts** | Entity semantics, OpenAPI, evidence payloads, error vocabulary, contract change protocol | **Highly serial.** One agent. Everything depends on it |
| **B · Backend** | Fiber service, Postgres schema, identity arbitration, change feed, mutations, download requests | Parallel internally after B4 |
| **C · Mobile Domain & Persistence** | Domain models, local schema, repositories, recognition indexes, outbox storage | Schema file is serial; repositories parallelise |
| **D · Mobile Library UX** | Folder UI, Collection and Entry presentation, source presentation, sync status | Starts after Gate C |
| **E · Capture & Save Integration** | Port execution, capture retargeted to `(Entry, Location)`, queue unit, OfflineCopy writes, download-request consumption | Starts after Gate C |
| **F · Recognition, Source & Update** | Recognition pipeline, evidence extraction, source-scoped discovery, preferred-source checking, placement | Starts after Gate C |
| **G · Sync** | Push, pull, reconcile, canonicalisation, scheduling, retry | Starts after Gate B **and** Gate C |
| **H · Integration & Regression** | Fixtures, end-to-end scenarios, device validation, V1 cleanup | Continuous from Phase 2 |

## 4. Gates

A gate is a merge prerequisite, not a ceremony. Nothing downstream starts until
the gate artefact is on `master`.

| Gate | Artefact | Unblocks |
|---|---|---|
| **Gate A · Domain accepted** | `V2_ARCHITECTURE.md` §2–§5 merged, invariants I1–I17 fixed | B, C |
| **Gate B · Contract frozen** | `contracts/openapi.yaml` merged; evidence and mutation payloads fixed | B6–B11, G |
| **Gate C · Local persistence stable** | C1–C2 merged, invariant tests green, schema frozen | D, E, F |
| **Gate D · Capture integration stable** | E1–E3 merged, port checklist signed off, fixture capture green | E4 |
| **Gate E · Local-first sync end to end** | H2 and H3 green | Extension work, cleanup passes |

**Gate A is passed.** This document set is the artefact.

**Gate D has passed at host/fixture level** — E1–E3 are merged and the port
checklist is signed off; device validation (H6) is still pending.

## 5. Phases and maximum useful parallelism

Agent counts are deliberately conservative. Two tasks that would repeatedly edit
the same central file are kept serial even when they look independent.

| Phase | Prerequisites | Max useful agents | Worktrees | Parallel tasks | Must stay serial | Integration gate |
|---|---|---|---|---|---|---|
| **0 · Domain & contract** | — | **1** | `wt/v2-contracts` | — | A1, A2, A3, A4 all in one lane | Gate A, then Gate B |
| **1 · Foundations** | Gate A | **3** | `wt/v2-backend-foundation`, `wt/v2-mobile-domain`, `wt/v2-port-validation` | B1–B4 · C1–C2 · E1 | `lib/data/schema.dart` (C only); `scrollary-backend/migrations` (B only) | Gate C |
| **2 · Core functionality** | Gate B, Gate C | **5** | `wt/v2-backend-api`, `wt/v2-mobile-repos`, `wt/v2-recognition`, `wt/v2-capture`, `wt/v2-library-ux` | B5–B9 · C3–C10 · F1–F3 · E2–E3 · D1–D3 | `providers.dart` composition (scheduled, one agent at a time) | Gate D |
| **3 · Sync** | Phase 2 core merged | **3** | `wt/v2-sync-push`, `wt/v2-sync-pull`, `wt/v2-backend-feed` | G1 · G2–G4 · B6–B7 hardening | G3 canonicalisation touches every repository — serial | Gate E |
| **4 · Download to Mobile & remaining UX** | Gate D, Gate E | **3** | `wt/v2-download-intent`, `wt/v2-library-ux-2`, `wt/v2-sync-scheduling` | B10, E4 · D4–D7 · G5–G7 | — | — |
| **5 · Integration, cleanup, device** | Phase 4 merged | **2** | `wt/v2-e2e`, `wt/v2-cleanup` | H1–H4 · H5 | H6 device validation is one operator, one device | Release gate |

**Do not run more agents than the table allows.** Higher numbers would mean two
agents editing the same schema, contract or provider graph, and the merge cost
exceeds the parallel gain.

**Sequencing note.** Phase 4 (B10, E4, D4–D7, G5–G7) merged ahead of Gate E:
none of that work depended on the end-to-end harness to be correct on its own
terms, and holding it for H2/H3 would have idled three worktrees against a gate
that only the harness itself can close. Gate E remains open — it is what
Phase 5's `wt/v2-e2e` is closing now.

## 6. Dependency graph

```
A1 Domain model  ─────────────────────────────┐
   │                                          │
   ├──> A2 OpenAPI contract ──┐               │
   │                          │               │
   ├──> B1..B4 backend        │               │
   │    foundation ───┐       │               │
   │                  │       │               │
   ├──> C1..C2 mobile │       │               │
   │    schema+domain─┼───┐   │               │
   │                  │   │   │               │
   └──> E1 port       │   │   │               │
        inventory ────┼───┼───┼──┐            │
                      │   │   │  │            │
             [Gate C] ┴───┘   │  │            │
                  │           │  │            │
      ┌───────────┼───────────┼──┼────────────┘
      │           │           │  │
      v           v           v  v
   C3..C10     F1..F3      E2..E3   D1..D3
   repos       recognition capture  library UX
      │           │           │        │
      └─────┬─────┴───────────┘        │
            │                          │
   [Gate B] ┴──> B5..B9 backend API    │
                    │                  │
                    v                  │
              G1..G4 sync engine       │
                    │                  │
              [Gate E] ─────────────┬──┘
                    │               │
                    v               v
          B10 + E4 download     D4..D7 UX
          intent                    │
                    └───────┬───────┘
                            v
                    H1..H4 end-to-end
                            │
                            v
                    H5 cleanup · H6 device
                            │
                            v
                   ┌──────────────────┐
                   │ V2 PRODUCTIZATION│  (separate programme)
                   └──────────────────┘
```

**Critical path:** A1 → A2 → C1/C2 → Gate C → C3–C10 → Gate B satisfied → G1–G4 →
Gate E → H2/H3. Everything else hangs off it.

## 7. Tasks

Columns: **ID · outcome · scope · depends · owns · parallel-safe with · validation
· class**. "Owns" means exclusive write access for the duration of the worktree.

### Lane A — Domain & Contracts · one agent, always

| ID | Outcome | Scope | Depends | Owns | Validation | Class |
|---|---|---|---|---|---|---|
| **A1** | Domain model, invariants I1–I17, ownership matrix fixed | `docs/V2_*`, `PRODUCT.md`, `DECISIONS.md` | — | `docs/**` | Docs consistency, guard tests | Foundation · **done** |
| **A2** | OpenAPI document for evidence, mutations, changes, download requests | `contracts/openapi.yaml` | A1 | `contracts/**` | Schema lints; example payloads validate | Foundation · **done** |
| **A3** | Shared refusal and error vocabulary — named reasons, not free text | `contracts/errors.yaml` | A2 | `contracts/**` | Enumerated, no duplicates | Foundation · **done** |
| **A4** | Evidence payload spec: what a client submits and what it must never invent | `contracts/evidence.yaml` | A2 | `contracts/**` | Round-trip examples from real fixtures | Foundation · **done** |
| **A5** | Contract change protocol: how a lane requests a change without forking it | `contracts/README.md` | A2 | `contracts/**` | — | Foundation · **done** |

### Lane B — Backend

| ID | Outcome | Scope | Depends | Owns | Parallel with | Validation | Class |
|---|---|---|---|---|---|---|---|
| **B1** | Fiber v3 app boots; config boundary; `/healthz` | `scrollary-backend/cmd`, `scrollary-backend/internal/config`, `internal/api` | A1 | `scrollary-backend/**` | C1, E1 | `go build`, `go test` | Foundation · **done** |
| **B2** | Go domain types + invariant tests | `scrollary-backend/internal/domain` | A1 | `scrollary-backend/**` | C1, E1 | `go test ./internal/domain` | Foundation · **done** |
| **B3** | Storage interfaces + in-memory implementation | `scrollary-backend/internal/storage` | B2 | `scrollary-backend/**` | C1, E1 | `go test ./internal/storage` | Foundation · **done** |
| **B4** | Fresh Postgres schema as migrations | `scrollary-backend/migrations` | B2 | `scrollary-backend/migrations` | C2, E1 | Schema-shape test parses SQL and asserts every domain table and constraint | Foundation · **done** |
| **B5** | Postgres repository over pgx | `scrollary-backend/internal/storage/postgres` | B4, Gate B | `scrollary-backend/**` | C3+, F1+ | Integration tests, skipped without `DATABASE_URL` | Functionality · **done** |
| **B6** | Revision counter and `GET /changes` feed | `internal/api`, `internal/sync` | B5 | `scrollary-backend/**` | C, F, E | Cursor tests over interleaved creates, updates, tombstones | Functionality · **done** |
| **B7** | `POST /mutations` with the idempotency ledger | same | B5 | `scrollary-backend/**` | C, F, E | Duplicate mutation ids produce one effect | Functionality · **done** |
| **B8** | Identity arbitration: evidence → canonical or `unresolved` | `internal/identity` | B5, A4 | `scrollary-backend/**` | C, F, E | Convergence tests **including the cases that must not merge** | Functionality · **done** |
| **B9** | Ordinal placement arbitration | `internal/identity` | B8 | `scrollary-backend/**` | C, F, E | Two-device conflicting placement detected centrally | Functionality · **done** |
| **B10** | DownloadRequest create, claim, resolve | `internal/api` | B7 | `scrollary-backend/**` | D, G | Single-winner claim; at most one non-terminal per `(library, entry)` | Functionality · **done** |
| **B11** | Dev library namespace middleware behind `SCROLLARY_DEV_MODE` | `internal/api` | B1 | `scrollary-backend/**` | anything | Server refuses to start without the flag | Functionality · **done** |

### Lane C — Mobile Domain & Persistence

| ID | Outcome | Scope | Depends | Owns | Parallel with | Validation | Class |
|---|---|---|---|---|---|---|---|
| **C1** | Domain entities and pure rules | `lib/domain/**` | A1 | `lib/domain/**` | B1–B4, E1 | Invariant unit tests I1–I17 | Foundation · **done** |
| **C2** | Fresh local schema with CHECK constraints for I3, I6, I8 | `lib/data/schema.dart` | C1 | `lib/data/schema.dart` **exclusively** | B4, E1 | Clean-schema test; constraint-violation tests | Foundation · **done** |
| **C3** | Folder repository: create, rename, move, delete-with-reparent | `lib/data/folder_*` | Gate C | those files | C4–C10 | Reparent never deletes content; cycle refusal | Functionality · **done** |
| **C4** | Collection + Source repository: follow, archive, preferred, lifecycle | `lib/data/collection_*` | Gate C | those files | C3, C5–C10 | Lifecycle transitions; `resolvedInto` chains | Functionality · **done** |
| **C5** | Entry + Location repository, placement and unplaced | `lib/data/entry_*` | Gate C | those files | C3, C4, C6+ | I6 uniqueness; unplaced round-trip | Functionality · **done** |
| **C6** | Reading-state repository, serialised, own clock | `lib/data/reading_*` | C5 | those files | C3, C4, C7+ | Concurrent-write ordering, ported from V1's queue tests | Functionality · **done** |
| **C7** | Measurement repository, scoped `(entry, source)` | `lib/data/measurement_*` | C5 | those files | C3–C6, C8+ | Scope never dropped | Functionality · **done** |
| **C8** | OfflineCopy repository with provenance snapshot | `lib/data/offline_*` | C5 | those files | C3–C7 | Provenance survives Source deletion; I13 | Functionality · **done** |
| **C9** | Local recognition indexes | `lib/data/recognition_index.dart` | C5 | that file | C3–C8 | Single-lookup benchmark; offline correctness | Functionality · **done** |
| **C10** | Outbox storage and `sync_state` | `lib/data/outbox_*` | C2 | those files | C3–C9 | Every repository write produces exactly one entry | Foundation · **done** |

### Lane D — Mobile Library UX · after Gate C

| ID | Outcome | Depends | Owns | Validation | Class |
|---|---|---|---|---|---|
| **D1** | Library shelf over the Folder tree | Gate C | `lib/library_ui/shelf_*` | Widget tests; empty and deep-nesting states | Functionality · **done** |
| **D2** | Folder management: create, rename, move, delete | C3 | `lib/library_ui/folder_*` | Delete shows reparent, never data loss | Functionality · **done** |
| **D3** | Collection detail: **one** Entry list, availability as row state | C4, C5 | `lib/library_ui/collection_*` | No separate download-oriented list exists | Functionality · **done** |
| **D4** | Source presentation and preferred-source switch | C4 | `lib/library_ui/source_*` | Dead sources shown honestly | Functionality · **done** |
| **D5** | Entry actions: read, open at source, download, remove offline, remove from library | C5, C8 | `lib/library_ui/entry_*` | Each verb's blast radius matches PRODUCT.md §2.4 | Functionality · **done** |
| **D6** | Unplaced Entry surface and placement action | C5, B9 | `lib/library_ui/placement_*` | Refusal is visible, never silent | Functionality · **done** |
| **D7** | Sync status in Settings, invisible when healthy | G7 | `lib/library_ui/sync_status_*` | Nothing appears in the reader | Functionality · **done** |

### Lane E — Capture & Save Integration · after Gate C

| ID | Outcome | Depends | Owns | Validation | Class |
|---|---|---|---|---|---|
| **E1** | **Port inventory executed and checklist signed** (§9) | A1 | `docs/V2_PORT_CHECKLIST.md` + moves | Ported tests green **unchanged** | Foundation · **done** |
| **E2** | Capture retargeted to `(Entry, Location)`; writes OfflineCopy | Gate C, E1 | `lib/save/**` call sites | Fixture capture; byte and provenance integrity | Functionality · **done** |
| **E3** | New queue unit of work | E2 | `lib/save/queue_*` | Single-winner cancellation preserved | Functionality · **done** |
| **E4** | DownloadRequest consumption → local queue | Gate D, B10 | `lib/save/download_intent_*` | Capture policy still evaluated on device; failure leaves membership intact | Functionality · **done** |
| **E5** | Offline reader reads through OfflineCopy | E2 | reader call sites | Position restore unchanged | Functionality · **done** |

### Lane F — Recognition, Source & Update · after Gate C

| ID | Outcome | Depends | Owns | Validation | Class |
|---|---|---|---|---|---|
| **F1** | Recognition pipeline with the local fast path | C9 | `lib/recognition/recognise_*` | Known URL resolves with no network | Functionality · **done** |
| **F2** | Evidence extraction and submission | A4, F1 | `lib/recognition/evidence_*` | Payloads validate against `contracts/evidence.yaml` | Functionality · **done** |
| **F3** | Source-scoped discovery; `ObservedEntryWindow` per Source | C4, C5 | `lib/recognition/discovery_*` | I15: Source A never retracts Source B | Functionality · **done** |
| **F4** | Preferred-source update checking; explicit check-other-sources | F3 | `lib/recognition/check_*` | One Source per ordinary check | Functionality · **done** |
| **F5** | Cross-source placement and refusal surfacing | B9, F3 | `lib/recognition/placement_*` | 100 vs 99.5 stays two Entries | Functionality · **done** |
| **F6** | History capture and promote-to-library | C3, F1 | `lib/recognition/history_*` | Unfollowed reading never expands the synced library | Functionality · **done** |

### Lane G — Sync · after Gate B and Gate C

| ID | Outcome | Depends | Owns | Validation | Class |
|---|---|---|---|---|---|
| **G1** | Outbox drain (push) with mutation ids | C10, B7 | `lib/sync/push_*` | Duplicate submission is idempotent | Functionality · **done** |
| **G2** | Change-feed pull, applied **through repositories** | B6, C3–C8 | `lib/sync/pull_*` | Never writes the DAO directly; batch in one transaction | Functionality · **done** |
| **G3** | Provisional identity canonicalisation | B8, G1, G2 | `lib/sync/identity_*` | **Serial** — touches every repository. Local ids never rewritten | Functionality · **done** |
| **G4** | Merge rules: scalar LWW, add-wins sets, keyed scalars | G2 | `lib/sync/merge_*` | Every row of `V2_SYNC.md §4.2` | Functionality · **done** |
| **G5** | Automatic scheduling: launch, resume, reconnect, idle, manual | G1, G2 | `lib/sync/scheduler_*` | Nothing runs while the app is not in front, beyond platform-supported windows | Functionality · **done** |
| **G6** | Retry, backoff, interruption safety | G5 | `lib/sync/retry_*` | Kill at every step leaves recoverable state | Functionality · **done** |
| **G7** | Sync status state for Settings | G5 | `lib/sync/status_*` | Healthy sync produces no UI event | Functionality · **done** |

### Lane H — Integration & Regression

| ID | Outcome | Depends | Validation | Class |
|---|---|---|---|---|
| **H1** | Fixture server gains multi-source scenarios | Gate C | Two Sources of one Collection, one dead, one renumbering | Integration · **done** |
| **H2** | End-to-end: client action → backend → phone library | Gate E prerequisites | Runs against a real Postgres and the fixture server | Integration |
| **H3** | End-to-end: phone offline mutation → reconnect → second client | H2 | Includes interrupted pull and duplicate mutation | Integration |
| **H4** | End-to-end: Download to Mobile → local queue → capture → OfflineCopy | E4, B10 | **Asserts the backend made no outbound request** | Integration |
| **H5** | V1 cleanup passes (§10) | Per cutover | Deleted subsystem has no remaining caller | Hardening |
| **H6** | Device validation re-run | H2–H4 | `FOREGROUND_MULTITASKING_PLAN.md §4a` programme, re-argued not assumed | Hardening |

## 8. Tasks that must not be parallelised

| Task | Why |
|---|---|
| **A1–A5** — the whole contract lane | Every other lane reads it. Two authors produce two contracts |
| **C2** — `lib/data/schema.dart` | One file, every entity. Concurrent edits guarantee conflicts |
| **B4** — `scrollary-backend/migrations` | Ordered, append-only. Two agents produce two migration `0002`s |
| **G3** — provisional canonicalisation | Touches every repository to rewrite references |
| **`providers.dart` composition** | The graph everything registers into. Schedule it, one agent at a time |
| **D3** — Collection detail | The largest single screen. Splitting it across agents produces four half-designs |
| **B8/B9** — arbitration rules | The one place identity is decided. A second copy is the bug this design exists to prevent |

Do not manufacture independence by duplicating logic. If two tasks want the same
rule, the rule has one owner and the other task waits.

## 9. Port-as-is inventory

Executed as task **E1**, recorded in `docs/V2_PORT_CHECKLIST.md`. For every
component: original file · new location if moved · **intentional internal changes,
ideally none** · tests carried · device assumptions · integration dependency.

| Component | Files | Device knowledge it encodes |
|---|---|---|
| Browser surface policy and render guards | `lib/browser/browser_surface_policy.dart`, guards in `browser_controller.dart`, `save_engine.dart`, `update_checker.dart` | `requestAnimationFrame` is the only honest covered-rendering signal; a WebView reports a full viewport and accepts scrolling while undrawn |
| Image enumeration | `lib/save/image_candidates.dart` | Reads in the scroller's own coordinates, not the page's |
| Lazy-image settling | `lib/browser/bridge_script.dart`, `lib/save/save_engine.dart` | Settle windows; an empty first read is never trusted |
| Decode budget | `lib/reading/decode_budget.dart` | Never bounds on unverified DOM dimensions |
| FileStore | `lib/storage/file_store.dart` | Atomic commit, `.previous` restore, staging sweep |
| Manifest | `lib/storage/manifest.dart` | Versioned; unrecognised artifact resolves to `unknown` |
| Document model | `lib/storage/document.dart` | No HTML, no script, no remote reference |
| Capture policy | `lib/save/capture_policy.dart` | Judges pages never assets; one file, six boundaries |
| Content detection | `lib/save/content_detection.dart` | Structural signals only; phrase hints never stand alone |
| Document extraction | `lib/save/document_extraction.dart` | Judgement in Dart, testable against literal fixtures |
| Stop conditions | `lib/save/stop_conditions.dart` | Named outcomes; "finished" ≠ "the site stopped us" |
| Asset fetcher | `lib/save/asset_fetcher.dart` | Image bytes by magic number, never `Content-Type` |
| Readers | `lib/features/reader_screen.dart`, `document_reader.dart` | Position restore; document restores *to* its position, not *at* it |
| Bridge script | `lib/browser/bridge_script.dart` | Measurement surface both platforms agree on |
| Entry identity review | `lib/library/entry_identity.dart` | Refuse and keep the contradiction; **moves to `lib/recognition/`, logic unchanged** |
| URL normalisation | `lib/core/url_utils.dart` | Does not strip `www.`, does not unify scheme — deliberate |

**Rule for this inventory:** if a ported component needs an internal change, that
is a task with its own review, not a side effect of a call-site edit.

## 10. V1 cleanup points

Old code is deleted at defined cutovers, never opportunistically, and never
before the replacement passes validation.

| Cutover | Delete | Precondition |
|---|---|---|
| **After Gate C** | Nothing yet | Two schemas coexist briefly; the app still runs on V1 |
| **After D3 + E5 merge** | `lib/features/collection_detail_screen.dart`, `library_screen.dart`, `library_check_ui.dart` | New library UX passes widget tests and the reader opens through OfflineCopy |
| **After E2 + E3 merge** | `lib/queue/task_queue.dart`, `lib/save/save_run.dart` orchestration | New queue unit passes; single-winner cancellation preserved |
| **After F3 + F4 merge** | `lib/library/update_checker.dart`, `lib/library/library_check.dart` | Source-scoped discovery green on fixtures |
| **After C3–C8 merge** | `lib/storage/database.dart`, `lib/library/collection_repository.dart`, `lib/library/collection_deletion.dart`, `lib/reading/reading_repository.dart`, `lib/storage/cleanup.dart` | All repository tests green; no remaining caller |
| **After Gate E** | `lib/storage/recovery.dart` V1 path | Recovery rebuilt against OfflineCopy |

Each cleanup task states: *the old path may be deleted because the new path owns
X and passes Y.* Never *"it looks unused"*.

## 11. Validation per lane

| Lane | Required |
|---|---|
| **A** | Contract examples validate; error vocabulary has no duplicates |
| **B** | `go build ./...`, `go vet ./...`, `gofmt -l` clean, `go test ./...`; Postgres integration tests skipped without `DATABASE_URL`; schema-shape test parses migrations |
| **C** | Invariant tests I1–I17; clean-schema test; constraint-violation tests; deletion and transaction tests |
| **D** | Widget tests per surface; the existing palette and header guards still pass |
| **E** | **Ported tests green unchanged**; fixture capture suites; byte and provenance integrity; device tests where the component demands one |
| **F** | Source-scoped retraction; identity refusal cases; recognition fast-path correctness offline |
| **G** | Offline mutation → reconnect; duplicate mutation; interrupted pull; provisional canonicalisation; Folder moves; deletion conflicts; DownloadRequest delivery |
| **H** | The three end-to-end scenarios, plus **an assertion that the backend never made an outbound request** |

## 12. Status

**Historical — this section once listed the next worktrees to start when Gate
A had just passed and Phase 0 was the frontier.** That plan has since been
carried out: every lane below merged to `master`, phase by phase, in the order
§5 sequenced them. It is kept here as a status readout, updated in place,
rather than deleted — the worktree plan it replaces is history, not a
document a future contributor should read as current.

**Merged, lane by lane:** A1–A5 · B1–B11 · C1–C10 · D1–D7 · E1–E5 · F1–F6 ·
G1–G7 · H1. Gates A through D have passed — Gate D at host/fixture level, with
device validation (H6) still pending (§4).

**In integration, not yet on `master`:**

- **The composition branch** — wiring the V2 screens in `lib/library_ui` up as
  the running app in place of V1's, and the V1 cleanup passes that follow
  (§10). Phase 4 (B10, E4, D4–D7, G5–G7) landed ahead of this and ahead of
  Gate E (§5's sequencing note); the cutover itself has not.
- **The end-to-end harness, H2–H4.** H1 is merged; H2 and H3 are Gate E's own
  artefact and are the immediate next work in `wt/v2-e2e`.
- **H5 cleanup and H6 device validation**, which depend on the two items
  above.

---

## Appendix · What the backend foundation already delivers

Merged as part of the architecture task, so Phase 1's Lane B starts from working
ground rather than an empty directory:

- Go module, Fiber v3 boot, config boundary, `/healthz` and `/version`
- Domain types for Folder, Collection, Source, Entry, Location, ReadingState,
  Measurement, DownloadRequest, with invariant enforcement
- Storage interfaces plus an in-memory implementation
- The fresh PostgreSQL schema as migration `0001`
- A schema-shape test that parses the migration and asserts every domain table,
  key constraint and index the domain requires
- `go test ./...` green with no database and no network
