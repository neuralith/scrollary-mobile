# V2 Productization backlog

> **A separate programme from V2 Functionality.** Nothing here is implemented
> during the functionality build, and nothing here may block it.
>
> The split exists so that production concerns — authentication, monetization,
> deployment, legal — do not leak into the domain rewrite and stall it. The
> architecture must *support* each item below; none of them is *built* yet.
>
> Functionality plan: [V2_ROADMAP.md](./V2_ROADMAP.md) · Decisions:
> [DECISIONS.md](./DECISIONS.md).

## How to read this

Each item names what the functionality build must already support so the item
can be added later without another foundational change. If an item requires
something the foundation does not have, that is a defect in the foundation and
belongs in the roadmap instead.

---

## P1 · Authentication and accounts

**Deferred deliberately.** The functionality build uses a development library
namespace ([DECISIONS.md](./DECISIONS.md) V2-D28) — an `X-Scrollary-Library`
header behind a `SCROLLARY_DEV_MODE` flag, which authenticates nothing and says
so.

| Item | Note |
|---|---|
| Production authentication | Provider comparison is explicitly **not** this phase's work |
| Account lifecycle: create, sign in, sign out, recovery | Sign-out keeps everything local (V2-D11) |
| Anonymous → account transition on mobile | Mobile is fully usable without an account, permanently (V2-D3) |
| Multi-device ownership and device naming | Enables targeted Download to Mobile |
| Session and token storage | Platform secure storage, never the settings table |

**Foundation must already support:** a real `library_id` column on every
synchronised table, so the production account model populates it without a domain
change.

## P2 · Monetization

**Sync is Pro, decided through the existing seam — billing itself is still
not.** The boundary this section used to leave open is now implemented: `lib/capability/entitlement.dart`
(`cloudSyncAvailableFor`) is the single question, asked only at the network
drain (`SyncComposition.resolve`, `lib/features/v2_composition.dart`) —
exactly the seam this document already required
([DECISIONS.md](./DECISIONS.md) V2-D7, V2-D37). What remains genuinely
undecided is everything about *paying*: there is no purchase flow, no
provider, and `productionEntitlement()` (`lib/capability/entitlement.dart`)
returns `Entitlement.free` unconditionally, honestly, because there is
nothing behind it yet.

| Item | Note |
|---|---|
| ~~Whether sync is Pro~~ | **Decided and implemented** — V2-D37. What is still open below is how a user *becomes* Pro |
| Whether foreground multitasking remains separately gated | The existing V1 boundary, `FOREGROUND_MULTITASKING.md §10.0` |
| How server-cost capabilities map to entitlement | Sync answers this; a future capability repeats the pattern |
| Purchase and restore behaviour | `_upgradeSeat` is the existing seam; nothing fakes a purchase |
| Entitlement across clients | Mobile and extension must agree |

**The accepted cost of gating only at the drain.** A device that never
upgrades keeps journaling to its outbox forever — every local mutation, on a
permanently-Free device, is a row nothing ever drains. Nothing prunes it and
nothing caps it. This is not an oversight: it is the direct, accepted
consequence of V2-D7's rule that local writes and the outbox are never
gated. A retention or compaction policy for an outbox that will never drain is
production work, not foundation work, and is not designed here.

**Foundation must already support, and this is binding:** local writes and the
outbox are **never** gated; `lib/capability/` stays the only entitlement reader;
any future gate may sit only on the network drain, never on recording, reading or
opening. `test/entitlement_test.dart` already fails the build if a reading or
cleanup surface imports the capability seam, and that guard extends to the library
and sync-write paths.

## P3 · Tombstone lifecycle

Architecture supports tombstones now; policy is deferred.

| Item | Note |
|---|---|
| Retention period | Must outlive a plausible offline period; no figure chosen |
| Compaction | Revisions and tombstones grow without bound otherwise |
| Long-offline-device guarantees | What happens to a device past the retention window — full re-bootstrap is the likely answer |

## P4 · Deferred product questions

| # | Question | Why deferred |
|---|---|---|
| Q1 | What a second client does with a followed Collection whose only Source is restricted or unreadable there | A reconciliation edge, not a foundation concern |
| Q2 | Whether a measurement taken on Source A may ever be shown as an approximation on Source B | The architecture deliberately does **not** assume this (V2-D18). Adding it later is presentation, not schema |
| Q3 | Whether the extension ever gains capture | Currently no (V2-D19). Would require re-implementing the safety-critical capture rules in JavaScript |
| Q4 | Device-targeted Download to Mobile | Needs P1 device management. Any-device claiming is sufficient for functionality |

## P5 · Privacy, legal and stores

The server holds a list of what the user reads. That is a real responsibility and
it changes several claims that are currently true.

| Item | What changes |
|---|---|
| `PRIVACY.md` rewrite | §2 *"no account, no server"* and §3's permitted claims become false **for a signed-in user** and must be re-scoped, not deleted — anonymous mobile use stays fully supported |
| App Store Connect App Privacy | Redone: library metadata and reading state are collected and linked to the user |
| Play Data safety | Same |
| `STORE_POLICY_MAP.md` | Its position that *"there is no login and no back end, so no demo account is needed"* becomes false. App Review will require credentials and a working backend |
| Privacy policy URL, terms, content-rights page, support URL | `STORE_PACKAGE.md §8.5`, still outstanding |
| Account deletion | Real erasure, reachable in-app |
| Data export | Library metadata and reading state in a readable format |
| Store copy pass | Copy that equates "saved" with "downloaded" now understates the product |

**Foundation must already support:** account deletion and export as first-class
server operations, so they are not retrofitted onto a schema that cannot express
them.

## P6 · Production backend

| Item | Note |
|---|---|
| Authentication middleware | P1 |
| Rate limiting and abuse protection | |
| Backups and restore drills | Managed Postgres provides the mechanism, not the drill |
| Observability: structured logs, metrics, traces | **No source URLs or titles in logs** beyond serving the request |
| Alerting | |
| Deployment and secrets management | |
| Migration operations | Ordinary SQL; the mechanism exists from the foundation |
| Scaling and recovery | Not a concern at the scale this product realistically needs |

## P7 · Extension productization

| Item | Note |
|---|---|
| Store distribution and review | |
| Production authentication | P1 |
| Permissions model and host permissions | |
| Browser support matrix | Chrome first; the contract is browser-agnostic |
| Privacy declarations | The extension sees every page the user visits — a stronger disclosure than the app's |

## P8 · Release readiness carried from V1

These were V1 release blockers. `V2-D1` moved the release, so they become the V2
launch gate. None is code work.

| Item | Source | Note |
|---|---|---|
| VoiceOver over a covered WebView (D-3) | `FOREGROUND_MULTITASKING_PLAN.md §5` | Release blocker |
| TalkBack over a covered WebView (D-4) | Same | Release blocker; needs hardware |
| Physical Android hardware gate (D-2 / G4b) | `PLAN §4` | Still blocked — no device |
| Thermal, battery, profile-build performance (D-5, P1) | `PLAN §5, §7` | Not release-blocking |
| First-use content-rights disclosure UI | `ARCHITECTURE.md §10` | Copy fixed in `STORE_PACKAGE.md §6.1` |
| Save-scope review step UI | `ARCHITECTURE.md §10` | Domain layer complete; copy fixed in §6.4 |
| Hosted demo site | `DEMO_CONTENT.md` | Needed for screenshots and review |
| Name, trademark, domain clearance | `STORE_PACKAGE.md §1.2` | |
| Console tasks | `STORE_PACKAGE.md §8.6` | |
| **Database migration system** | `V2-D1` | Required before the **first store build**, not before V2 code |
| Reader memory: lazy image blocks | `ARCHITECTURE.md §12` | ~13 MB per inline image measured on hardware |
| Dedicated `StopReason` tests | `ARCHITECTURE.md §10` | Existing gap |

## What is explicitly **not** here

Because it is Functionality, not Productization, and lives in
[V2_ROADMAP.md](./V2_ROADMAP.md):

the domain model · the fresh local and server schemas · Folder · multi-source ·
standalone Entries · reading state · Measurement · OfflineCopy · recognition ·
library-first UI · local-first behaviour · automatic sync · the backend service ·
Download to Mobile · the client contract.
