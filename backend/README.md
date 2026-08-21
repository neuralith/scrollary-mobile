# Scrollary backend

The V2 synchronisation service. **Foundation only** — the domain, the
persistence boundary, the schema and the application shell. The synchronisation
endpoints are roadmap Lane B and are built against the frozen contract in
`contracts/`.

What it owns and what it deliberately does not: [docs/V2_SYNC.md](../docs/V2_SYNC.md) §6.
The short version: it arbitrates identity over evidence clients gathered, and it
**never makes an outbound request**. It holds no page content, no browsing
history and no record of what any device has downloaded.

## Running

```bash
cd backend
go run ./cmd/scrollaryd
```

Listens on `:8080` with the in-memory store. Two endpoints:

```bash
curl localhost:8080/healthz
curl localhost:8080/version
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `SCROLLARY_ADDR` | `:8080` | Listen address |
| `SCROLLARY_DATABASE_URL` | *(empty)* | PostgreSQL connection string. Empty selects the in-memory store. Setting it currently **fails fast** — the PostgreSQL store is roadmap task B5, and starting on an in-memory store the operator did not ask for would silently lose every write |
| `SCROLLARY_DEV_MODE` | `false` | Enables the development library namespace |
| `SCROLLARY_DEV_LIBRARY` | `development` | Library name used when a request carries no namespace header |

### The development library namespace

**This is not authentication and does not pretend to be.** Production
authentication is a separate programme
([docs/V2_PRODUCTIZATION.md](../docs/V2_PRODUCTIZATION.md) P1).

With `SCROLLARY_DEV_MODE=true`, a request may carry `X-Scrollary-Library: <name>`
to address a library, which is created on first use. Without the flag the header
is refused outright — the production path is an account, not a header.

It is one middleware, one flag and one header, so removing it is a small,
obvious change. It distorts nothing: `library_id` is a real column on every
synchronised table, and the production account model populates the same column.

## Testing

```bash
gofmt -l .        # must print nothing
go vet ./...
go test ./...
```

No database and no network are required. The schema is validated by parsing the
migration and asserting the tables, constraints and indexes the domain needs —
including a test that the server schema holds **no** device-owned state. A
PostgreSQL integration suite arrives with task B5 and will skip itself without
`SCROLLARY_DATABASE_URL`.

## Layout

```
backend/
  cmd/scrollaryd/       entry point
  internal/
    config/             the one place environment is read
    domain/             entities and invariants (I1-I17), pure Go
    storage/            persistence interfaces
    storage/memory/     in-memory implementation, for tests and local runs
    api/                Fiber v3 application and handlers
  migrations/           fresh V2 PostgreSQL schema
```

`internal/domain` has no dependency on Fiber, on the store, or on anything else.
The invariants are testable without infrastructure, which is the point.

## Migrations

`migrations/0001_init.up.sql` is a **fresh** schema designed from the V2 domain.
It is not derived from the mobile database and there is no migration from V1 —
there are no released users, so nothing is carried forward
([docs/DECISIONS.md](../docs/DECISIONS.md) V2-D1, V2-D26).

Applied by hand for now:

```bash
psql "$SCROLLARY_DATABASE_URL" -f migrations/0001_init.up.sql
```

A migration runner arrives with task B5. **No Docker Compose is included**: the
test suite needs no database, and a compose file that only serves a
not-yet-written repository would be maintenance for nothing. It is added when
B5 needs a repeatable PostgreSQL locally.

## Dependencies

`github.com/gofiber/fiber/v3` and `github.com/google/uuid`. Nothing else, on
purpose — no cache tier, no queue, no broker, no object storage. One stateless
service and PostgreSQL is what V2 functionality needs
([docs/DECISIONS.md](../docs/DECISIONS.md) V2-D23).
