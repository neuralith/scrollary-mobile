# Scrollary workspace

One local workspace, two products, one shared contract:

| Path | What it is | Published to |
|---|---|---|
| `scrollary-mobile/` | The Flutter app (iOS/Android) — V2 is the running app; V1 is retired | `github.com/neuralith/scrollary-mobile` |
| `scrollary-backend/` | The V2 synchronisation service — Go, Fiber v3, PostgreSQL | `github.com/neuralith/scrollary-backend` |
| `scrollary-mobile/contracts/` | The shared API contract, frozen at Gate B — canonical copy. `scrollary-backend/contracts/` is a vendored snapshot kept in sync | — |
| `docs/` | The documentation set for **both** halves. It sits at the workspace root rather than inside either repository, because most of it — the domain, sync, the contract boundary, store and privacy work — describes the two together | — |

Start with [docs/README.md](docs/README.md) for the documentation index, and
[scrollary-mobile/CLAUDE.md](scrollary-mobile/CLAUDE.md) for the standing
product and engineering rules.

## Working in each half

```bash
# Mobile
cd scrollary-mobile
flutter pub get && flutter analyze && flutter test

# Backend
cd scrollary-backend
go build ./... && go vet ./... && go test ./...   # Postgres suite uses testcontainers (Docker)
```
