# Scrollary workspace — structure and cross-cutting rules

This directory is a plain workspace (no git repository at this level) holding two products and their shared contract:

- `scrollary-mobile/` — the Flutter app. **All product and engineering rules
  live in [scrollary-mobile/CLAUDE.md](scrollary-mobile/CLAUDE.md); read it
  before touching anything under that directory.**
- `scrollary-backend/` — the V2 synchronisation service (Go + Fiber v3 +
  PostgreSQL). See `scrollary-backend/README.md`.
- `docs/` — the documentation set, **for both halves**, indexed by
  [docs/README.md](docs/README.md). It lives here rather than inside either
  repository because most of it describes the two together; neither repository
  carries a `docs/` directory of its own.
- The shared API contract is frozen at Gate B. Canonical copy:
  `scrollary-mobile/contracts/`; `scrollary-backend/contracts/` is a vendored
  snapshot that must be updated in the same change. Changes go through the
  protocol in `contracts/README.md`, never through a lane edit.

## Cross-cutting rules

- Flutter commands run from `scrollary-mobile/`; Go commands from
  `scrollary-backend/`. Neither half imports files from the other — the
  contract is the only bridge.
- The backend **never fetches third-party pages** and never stores page
  content. Everything it knows arrives as client-submitted evidence.
- `scrollary-backend/` is published standalone to
  `github.com/neuralith/scrollary-backend` via
  `git subtree split --prefix=scrollary-backend`; its `go.mod` module path is
  `github.com/neuralith/scrollary-backend` and must stay in sync with that
  home. `scrollary-mobile/` corresponds to
  `github.com/neuralith/scrollary-mobile`.
- The guard tests inside `scrollary-mobile/test/` (repository cleanliness,
  entitlement, palette, library check) gate the whole workspace's vocabulary
  and boundaries — they must stay green after any change, in either half.

## What a change costs across the two halves

Synchronisation is an **intent outbox plus a revision cursor**, not a state
dump: a mutation writes one `outbox` row in its own transaction
(`scrollary-mobile/lib/data/outbox_writer.dart`), the drain sends sparse
`fields`, and `GET /changes?cursor=N` returns only rows newer than the cursor.
`cursor=0` is the only full bootstrap. Reading state is its own row precisely
so marking something read does not bump the Entry's revision.

**Every synced field is written out by hand in both halves.**
`scrollary-backend/internal/sync/fields.go` (`unknownKeys`) *rejects* a field
it does not know rather than ignoring it, so:

- A device-local feature (reader, offline copies, save queue, history, hints,
  settings) costs the backend nothing — and `lib/domain/sync_kinds.dart` makes
  an intent about one inexpressible.
- A new **field on a synced entity, or a new synced entity**, must land in all
  of: `contracts/openapi.yaml` (+ the vendored backend copy) → a migration →
  `internal/domain` → `internal/sync/fields.go` → `internal/storage/postgres`
  → `lib/data/schema.dart` **and its client migration step** → the owning
  repository's outbox payload → `lib/sync/pull.dart`. Anything less is a
  rejected mutation, not a silent no-op.

Two standing consequences:

- **No forward compatibility — answered by deploy order, not by negotiation.**
  A new client against an older service gets `rejected`, and
  `lib/data/outbox_repository.dart` parks that row permanently (`rejected:`
  prefix). The rule that follows is **deploy the service before releasing the
  client that sends a new field**; there is deliberately no capability
  handshake, and `GET /version` is where one would go if clients ever face two
  service versions at once. Stated in docs/V2_SYNC.md §8.1a, decided in
  DECISIONS.md V2-D73.
- **The client has a migration path, and every schema change owes it a step.**
  `lib/data/schema.dart` is `schemaVersion = 2` with an `onUpgrade` (V2-D75).
  It was 1 with none while development databases could be reset by hand, and
  the rule outlived that: five additions landed against libraries somebody was
  using, and a Collection read threw on a column that was not there. **A new
  field on a synced entity now also lands in a version bump and a step in
  `_reconcileToDeclaredSchema`, in the same commit** — the step asks the file
  what it has and adds only what is missing, so it is safe against any older
  shape and safe to run twice.

The pair of tests that holds the halves to one vocabulary —
`scrollary-backend/internal/sync/vocabulary_test.go` and
`scrollary-mobile/test/sync/support/contract_vocabulary.dart`, both reading
`contracts/openapi.yaml` — is what makes a forgotten half a failing test rather
than someone's parked outbox row.
