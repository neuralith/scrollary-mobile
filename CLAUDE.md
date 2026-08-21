# Scrollary workspace — structure and cross-cutting rules

This repository is a workspace holding two products and their shared contract:

- `scrollary-mobile/` — the Flutter app. **All product and engineering rules
  live in [scrollary-mobile/CLAUDE.md](scrollary-mobile/CLAUDE.md); read it
  before touching anything under that directory.** Its documentation set is
  `scrollary-mobile/docs/`.
- `scrollary-backend/` — the V2 synchronisation service (Go + Fiber v3 +
  PostgreSQL). See `scrollary-backend/README.md`.
- `contracts/` — the shared API contract, frozen at Gate B. It is the single
  authority for wire payloads; changes go through the protocol in
  `contracts/README.md`, never through a lane edit.

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
