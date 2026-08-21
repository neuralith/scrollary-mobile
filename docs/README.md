# Documentation

## What Scrollary is

**A recognition-driven, cross-platform personal reading library.** You read;
Scrollary recognises which Collection, Entry, Source and Location that is and
keeps your library current; reading state follows the logical Entry across the
sites that publish it and across your own devices. Folders are how you organise
it. Offline content is an optional, per-device capability.

An Entry is in the library because you want to read or track it — **not**
because its content has been downloaded, and **not** because of the URL it
happens to live at. The full statement is [PRODUCT.md](./PRODUCT.md).

## The documents

### Product and decisions

| Document | What it is |
|---|---|
| [PRODUCT.md](./PRODUCT.md) | **The durable product definition** — what Scrollary is, the Folder / Collection / Entry model, the verbs and their blast radii, the product principles, and the two different rules about network work |
| [TERMINOLOGY.md](./TERMINOLOGY.md) | The canonical model, the contextual label rules, the rename inventory |
| [DECISIONS.md](./DECISIONS.md) | **Settled decisions, and the ones still open.** Anything under §Open must not be written elsewhere as though it were decided |
| [../../scrollary-backend/README.md](../../scrollary-backend/README.md) | The V2 service: how to run it, its configuration, and the development library namespace that stands in for authentication |

### As built — current behaviour

| Document | What it is |
|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | **The as-built product and data model.** Save flow, stopping rules, version-1 schema, the §9 invariants, and a built-vs-deferred status table in §10. The authority on what the code actually does today |
| [FOREGROUND_MULTITASKING.md](./FOREGROUND_MULTITASKING.md) | Specification for one user-started operation continuing while the user reads, and **§10.0, the current Free/Pro boundary** |
| [FOREGROUND_MULTITASKING_PLAN.md](./FOREGROUND_MULTITASKING_PLAN.md) | The implementation checklist for that specification, its validation record, and the device and accessibility tests still outstanding |

### V2 — designed; only the backend foundation is built

| Document | What it is |
|---|---|
| [V2_ARCHITECTURE.md](./V2_ARCHITECTURE.md) | **The V2 domain.** Folder / Collection / Source / Entry / Location / Measurement / OfflineCopy, the numbered invariants I1-I17, the state-ownership matrix, identity, and the local architecture |
| [V2_SYNC.md](./V2_SYNC.md) | Automatic synchronisation, merge and conflict rules, removal semantics, the backend responsibility boundary, the shared API contract, and Download to Mobile |
| [V2_ROADMAP.md](./V2_ROADMAP.md) | **The execution plan.** Lanes, gates, per-phase maximum parallelism, worktree ownership, the dependency graph, the port-as-is inventory, V1 cleanup points, and which worktrees can start now |
| [V2_PRODUCTIZATION.md](./V2_PRODUCTIZATION.md) | The separate programme: authentication, monetization, tombstone retention, privacy and store work, production backend, extension publishing, and the V1 release blockers |

### Store and legal

| Document | What it is |
|---|---|
| [STORE_POLICY_MAP.md](./STORE_POLICY_MAP.md) | Official Apple/Google policy areas → risk → mitigation, plus the residual-risk register |
| [STORE_PACKAGE.md](./STORE_PACKAGE.md) | Listing copy (EN/TR), exact in-app wording, reviewer notes, console checklists |
| [PRIVACY.md](./PRIVACY.md) | Per-flow data audit and the claims the listing may make |
| [DEMO_CONTENT.md](./DEMO_CONTENT.md) | The original, developer-owned demo site a reviewer needs |
| [MONETIZATION_STRATEGY.md](./MONETIZATION_STRATEGY.md) | **Historical — dated 2026-08-03, and superseded in part.** Pricing and store-policy research. Its description of the codebase and its proposed free/Pro boundary have both been overtaken; read its own header before using anything in it. Its proposal to sell **update checking** is superseded — checking is Free. The boundary in force is FOREGROUND_MULTITASKING.md §10.0 |

## Which of these is authoritative

When two disagree, resolve in this order:

1. The repository instructions in [CLAUDE.md](../CLAUDE.md).
2. The code and its tests.
3. [DECISIONS.md](./DECISIONS.md), for *why* something is the way it is or is
   going to be.
4. [TERMINOLOGY.md](./TERMINOLOGY.md) and [PRODUCT.md](./PRODUCT.md), for the
   model and the product's intent.
5. [ARCHITECTURE.md](./ARCHITECTURE.md), for what is built.
6. The store and privacy documents.
7. Anything marked historical.

**Two rules that cut across that order.**

*Built beats designed.* The `V2_*` documents describe work that does not exist
yet, apart from the backend foundation in `../scrollary-backend/`. Where one of them and
ARCHITECTURE.md describe the same thing differently, ARCHITECTURE.md is right
about the present and the V2 document is the plan.

*V2 supersedes V1 where they conflict about intent.* ARCHITECTURE.md describes a
library organised around what has been downloaded. That is accurate about the
code and is not the product direction — [PRODUCT.md](./PRODUCT.md) is.

*A document that says "proposed", "deferred", "not built" or "historical" is
describing an intention, not the app.*

## What was removed

The previous planning documents — product brief, MVP plan, technical spec, data
model sketch, decision log, implementation status, open questions — described
the app this one replaced. They were removed rather than annotated: a document
that teaches a future contributor the previous product's model is worse than no
document at all.
