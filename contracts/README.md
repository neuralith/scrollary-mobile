# The Scrollary V2 contract

> **This directory is the shared API contract** (DECISIONS.md V2-D27): the one
> schema Dart, Go and later JavaScript all validate against, so the payloads
> most prone to drift — evidence submission and mutation shape — cannot fork
> silently. It is not a runtime dependency of anything.

| File | Owns |
|---|---|
| `openapi.yaml` | Every endpoint, entity resource schema, mutation envelope, change feed, download-request lifecycle |
| `errors.yaml` | The complete enumerated error and refusal vocabulary |
| `evidence.yaml` | Evidence payloads, provisional identity, arbitration request and response |

`openapi.yaml` `$ref`s into the other two, so a single lint validates the whole
graph:

```bash
npx -y @redocly/cli lint contracts/openapi.yaml
```

## Ownership and freeze

**Lane A owns `contracts/**` exclusively.** No other lane edits these files —
not to add a field, not to fix a typo, not "temporarily".

The contract **freezes at Gate B**. From that point it is the authority that
Lane B implements, Lane G drains against, and the extension will consume.
Downstream code conforms to the contract; the contract is never bent to match
code that diverged from it.

## Change protocol

A leaf task that discovers a genuine contract flaw does not patch around it and
does not invent an ad-hoc payload. The protocol is:

1. **Stop** the work that depends on the flawed part. Building against a shape
   about to change is waste.
2. **Report centrally** — to the orchestrating/integration agent — with the
   concrete failure: which payload, which field, what breaks.
3. **Lane A fixes it once**, in this directory, keeping the vocabulary rules
   below.
4. **Propagate intentionally**: every consumer of the changed shape is
   identified and updated in the same integration wave. A contract change with
   an unidentified consumer is not done.

Divergent payloads — a client sending a field this document does not define, a
server accepting one — are defects even when they "work".

## Vocabulary rules

- Wire field names are `snake_case` and match the column names of
  `backend/migrations/0001_init.up.sql`, which is the single spelling
  authority. Enum spellings (`ordering_basis`, `lifecycle`, `placement`,
  reading `status`, download-request `state`, tombstone `kind`) are exactly the
  migration's CHECK-constraint spellings.
- The one exception is `GET /version`, which mirrors the handler that already
  ships (`devMode`).
- Machine-readable failures are codes from `errors.yaml`, never free text. The
  same vocabulary names arbitration refusals inside 200 responses.
- Entity ids are client-mintable UUIDs, provisional until arbitration maps
  them. The server never asks a client to rewrite a local id.
- Examples use reserved example domains only. No third-party hostname enters
  this directory.

## Validation

Redocly's recommended ruleset must pass with zero errors. Examples are part of
the contract — they are validated against the schemas, and a change that breaks
an example is a change that breaks a client.
