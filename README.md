# Scrollary workspace

One local workspace, two products, one shared contract:

| Path | What it is | Published to |
|---|---|---|
| `scrollary-mobile/` | The Flutter app (iOS/Android): V1 as shipped today plus the V2 rewrite in progress. Docs live in `scrollary-mobile/docs/` | `github.com/neuralith/scrollary-mobile` |
| `scrollary-backend/` | The V2 synchronisation service — Go, Fiber v3, PostgreSQL | `github.com/neuralith/scrollary-backend` |
| `contracts/` | The shared API contract (OpenAPI + evidence + error vocabulary). Frozen at Gate B; both sides conform to it | — (source of truth lives here) |

Start with [scrollary-mobile/docs/README.md](scrollary-mobile/docs/README.md) for
the documentation index, and [scrollary-mobile/CLAUDE.md](scrollary-mobile/CLAUDE.md)
for the standing product and engineering rules.

## Working in each half

```bash
# Mobile
cd scrollary-mobile
flutter pub get && flutter analyze && flutter test

# Backend
cd scrollary-backend
go build ./... && go vet ./... && go test ./...   # Postgres suite uses testcontainers (Docker)
```
