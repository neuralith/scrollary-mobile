# Documentation

| Document | What it is |
|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | The as-built product and data model, save flow, stopping rules, version-1 schema — with a **built vs deferred** status table in §10 |
| [TERMINOLOGY.md](./TERMINOLOGY.md) | The canonical model, the contextual label rules, the rename inventory |
| [STORE_POLICY_MAP.md](./STORE_POLICY_MAP.md) | Official Apple/Google policy areas → risk → mitigation, plus the residual-risk register |
| [STORE_PACKAGE.md](./STORE_PACKAGE.md) | Listing copy (EN/TR), exact in-app wording, reviewer notes, console checklists |
| [PRIVACY.md](./PRIVACY.md) | Per-flow data audit and the claims the listing may make |
| [DEMO_CONTENT.md](./DEMO_CONTENT.md) | The original, developer-owned demo site a reviewer needs |
| [MONETIZATION_STRATEGY.md](./MONETIZATION_STRATEGY.md) | **Historical — dated 2026-08-03, and superseded in part.** Pricing and store-policy research, competitor comparison, and a recommendation. Its description of the codebase and its proposed free/Pro boundary have both been overtaken; read its own header before using anything in it. In particular its proposal to sell **update checking** is superseded — checking is Free. The boundary in force is FOREGROUND_MULTITASKING.md §10.0 |
| [FOREGROUND_MULTITASKING.md](./FOREGROUND_MULTITASKING.md) | Specification for one user-started operation continuing while the user reads — the measured baseline, the architecture decision, the data-safety, WebView, platform and accessibility invariants it rests on, and **§10.0, the current Free/Pro boundary: update checking is Free, foreground multitasking is Pro** |
| [FOREGROUND_MULTITASKING_PLAN.md](./FOREGROUND_MULTITASKING_PLAN.md) | The live, ordered checklist for that specification: phases, dependencies, acceptance criteria, the validation record (including physical-hardware runs), and the device and accessibility tests still outstanding |

**Which of these is authoritative.** When two disagree, resolve in this order:
the repository instructions in [CLAUDE.md](../CLAUDE.md); the code and its tests;
TERMINOLOGY.md and ARCHITECTURE.md; the store and privacy documents; and last,
anything marked historical. A document that says *specified, not built* or
*historical* is describing an intention, not the app.

The previous planning documents (product brief, MVP plan, technical spec, data
model sketch, decision log, implementation status, open questions) described the
app this one replaced. They were removed rather than annotated: a document that
teaches a future contributor the previous product's model is worse than no
document at all.
