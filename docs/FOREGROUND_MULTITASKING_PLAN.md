# Foreground multitasking — implementation plan

The ordered checklist for [FOREGROUND_MULTITASKING.md](./FOREGROUND_MULTITASKING.md).
This file is **maintained as the work happens**: status, evidence and any
assumption that turned out to be wrong are written here rather than remembered.

Status vocabulary: `todo` · `doing` · `done` · `blocked` · `dropped`.

---

## 0. Working strategy

**Historical — this records how the work was carried out, not the current state
of the repository.** The branch has since been merged to `master` and the work
is committed; the row below saying otherwise was true while the branch was live
and is kept so the constraints the work ran under stay legible.

| | |
|---|---|
| Branch | `feature/foreground-multitasking`, cut from `master` at `dcb90cb`. **Since merged** (`f62f08e`) |
| Working tree at start | Clean. `git status --porcelain` empty; nothing unrelated to preserve |
| Worktree | Not used. A dedicated branch on a clean tree is sufficient, and a worktree would have split the iOS/Android build caches the device gate needs |
| Commits | **None while the work was in progress** — nothing was committed, pushed, tagged or published by the work itself. The branch was committed and merged afterwards, by hand |
| Destructive git | None. No reset, rebase, stash, checkout of other branches, or history rewriting |
| Rollback | `ForegroundMultitasking.enabled == false` restores the previous behaviour at runtime. Source-level rollback is no longer "discard the branch" — it is a revert |

---

## Product boundary — built

> **The boundary: update checking is Free; foreground multitasking is Pro.**
> A Free user starts the same Collection check, the same Library-wide check and
> the same save, discovers the same Entries and gets the same report — with the
> Browser on screen while it works. Pro buys only the ability to go and read
> something else while it does. Specified in FOREGROUND_MULTITASKING.md §10.0.
> Nothing about the operation is gated, and the Free flow is not degraded to
> create Pro value.

The boundary is implemented and covered by deterministic tests. What landed, and
where it is specified:

- `lib/capability/foreground_gate.dart` — `resolveStartGate`,
  `resolveLeaveGate`, `TaskCapabilitySnapshot`. Pure; no widget, route or
  WebView. Spec: FOREGROUND_MULTITASKING.md §10.5–§10.6.
- `lib/features/foreground_gate_sheet.dart` — the one reusable surface:
  `showStartOptionsSheet`, `ForegroundStartActions` (embedded by the Library
  check sheet), `showLeaveBrowserSheet`, `showProInfoSheet`, and
  `setKeepWorkingPreference` as the single writer of the preference.
- Wired at: queued saves (`confirmAndStartSaves`), Library check
  (`startLibraryCheck`), every route out of the Browser (`LeaveBrowserGuard` →
  `_ShellState.confirmLeaveBrowser`, which also backs `PopScope`, the bottom
  tabs and every `LeaveBrowserGuard.push`), and the Settings row.
- Tests: `foreground_gate_test.dart` (49 assertions over the decision layer,
  the snapshot, and a structural guard that no screen reads the internal
  override), `foreground_gate_ui_test.dart` (both sheets, the locked-row
  semantics, the Settings row under Force Free and Force Pro).

**Still open:** the **Android** hardware gate (D-2) and both accessibility
passes (D-3, D-4). The iOS hardware gate (D-1) has since **passed** — §6.1.
`ForegroundMultitasking.defaultEnabled` is nonetheless still `false`, so the Pro
path is reachable today only through the internal Force Pro override; see §4a
for the criteria that would justify changing that default, none of which is met
on any platform yet.

**Not built:** billing. `_upgradeSeat` is the seam; nothing fakes a purchase.

## 1. Phase order, and why

1. **Gate** — the covered-rendering premise decides the architecture, so nothing
   depends on it until it is measured on real platforms.
2. **Safety foundations** — the visibility guard, the discovery guard, the
   website-data refusal and the lifecycle hold are correct on their own terms and
   fix a gap that exists today. They ship whatever happens to the rest.
3. **Capability seam** — one boolean, before anything reads it.
4. **Keep-painted mechanism** — the architecture itself, behind that boolean.
5. **Status and intervention UX** — free, and a precondition for the mechanism
   being safe to use rather than merely working.
6. **Vertical slices** — check first (recoverable metadata), then save (bytes),
   then multi-Entry continuation.
7. **Lifecycle and recovery hardening.**
8. **Performance and accessibility.**
9. **Final gating, cleanup and diff review.**

Checks come before saves deliberately: a check writes recoverable metadata, so
if the premise is wrong it fails loudly and cheaply before any capture code
depends on it.

---

## 2. Checklist

### Phase 0 — Architecture gate

| # | Task | Depends on | Risk | Status | Acceptance / evidence |
|---|---|---|---|---|---|
| G1 | Build `integration_test/occlusion_gate_test.dart`: three arms (painted · covered · unpainted) over one real WebView, one real `BrowserController` and the production save run against the fixture Entry | — | low | `done` | File exists; `dart analyze` clean |
| G2 | Run the gate on the iOS Simulator | G1 | low | `done` | §3.1 of the specification |
| G3 | Run the gate on Android | G1 | low | `done` | §3.1 |
| G4 | Run the gate on a physical iPhone | G1 | med | `done` | **PASSED** on a cabled iPhone 17, iOS 26.5.2 — §6.1. It was `blocked` for three attempts first: the only device available was paired wirelessly, and `flutter test` refuses integration tests on one. A cable resolved it, and nothing else about the run changed |
| G4b | Run the gate on a physical Android device | G1 | med | `blocked` | No physical Android device has been available. Emulator only — §4, D-2 |
| G5 | VoiceOver / TalkBack check on a covered WebView | Phase 4 | high | `blocked` | Hardware only — D-3, D-4. **The reason the capability defaults off**, now that G4 has passed |

**Blocking:** G2 and G3 block everything from Phase 3 on. G1–G3 do not block
Phase 1, which is correct independently.

### Phase 1 — Safety foundations (independent of the architecture)

| # | Task | Files | Risk | Status | Acceptance |
|---|---|---|---|---|---|
| F1 | The page bridge reports whether the page considers itself hidden | `lib/browser/bridge_script.dart`, `lib/browser/page_data.dart` | low | `done` | `PageProbe.pageHidden`, documented as a hold signal only (A2) |
| F2 | The save engine's and the checker's render guards ask the app whether it is drawing, and keep both page-side checks (**D1**) | `lib/browser/browser_controller.dart`, `lib/save/save_engine.dart`, `lib/library/update_checker.dart` | med | `done` | `hidden_webview_test.dart` unchanged and green; `foreground_multitasking_test.dart` proves a healthy-looking page is not read while undrawn |
| F3 | An empty link set is never accepted on first sight; the page gets one settle window, and an empty second read is reported rather than read as "up to date" (**D3**) | `lib/library/update_checker.dart` | med | `done` | `update_checker_test.dart` green; the log line is the evidence |
| F4 | Clearing website data is refused while an operation owns the WebView (**W4**) | `lib/features/browser_data_dialogs.dart` | low | `done` | Refusal dialog keyed `clearDataRefused` |
| F5 | An operation holds when the app leaves the foreground, and resumes on return | `lib/app.dart`, `lib/browser/browser_surface_policy.dart` | med | `done` | Expressed as "the app is drawing nothing", so it reuses the same guard; covered by the surface-policy tests |

### Phase 2 — Capability seam

| # | Task | Files | Risk | Status | Acceptance |
|---|---|---|---|---|---|
| C1 | `ForegroundMultitasking` capability object, one boolean, persisted in the existing settings table | `lib/capability/foreground_multitasking.dart`, `lib/providers.dart`, `lib/main.dart` | low | `done` | Defaults **off** until D-1 passes; imports nothing but `foundation`; `library_check_test.dart`'s no-gating scan still green |
| C2 | A settings switch that turns it on and off, with copy that describes the behaviour rather than a payment | `lib/features/settings_screen.dart` | low | `done` | `settingsKeepWorking`; the route listens live, so toggling mid-run takes effect without a restart |

### Phase 3 — Keep-painted mechanism

| # | Task | Files | Risk | Status | Acceptance |
|---|---|---|---|---|---|
| K0 | The decision itself, extracted so it can be read and tested without a platform view | `lib/browser/browser_surface_policy.dart` | low | `done` | Five-input truth table covered in `foreground_multitasking_test.dart` |
| K1 | The shell keeps the Browser child painted underneath the Library tab when an operation owns the WebView — without rebuilding the WebView | `lib/app.dart` | **high** | `done` | `Stack` + `Offstage` with `StackFit.expand`, children never added or removed. Proved end to end by the fixture integration test: a save started on the Browser completes while the Reader is on top, which is only possible if the WebView survived |
| K2 | The Browser child is excluded from pointers and from semantics while it is covered (**W7**) | `lib/app.dart` | med | `done` | `IgnorePointer` + `ExcludeSemantics` for the tab case; `ModalBarrier`'s own pointer absorption and `BlockSemantics` for the pushed-route case. Device confirmation is D-3/D-4 |
| K3 | Screens pushed above the shell become non-opaque routes while the capability is on and an operation owns the WebView | `lib/ui/app_page.dart` (new), `lib/app.dart` | **high** | `done` | `AppPage`; widget test proves opacity follows the flag live and that the screen below stays built and painted |
| K4 | `needsRenderedBrowser` and the leave-Browser confirmation stand down when the surface will keep painting | `lib/app.dart` | med | `done` | `_leavingBrowserIsRisky` returns false while the surface is being kept painted |

### Phase 4 — Status and intervention (free, never gated)

| # | Task | Files | Risk | Status | Acceptance |
|---|---|---|---|---|---|
| S1 | A compact operation indicator, hosted above the router so it is reachable from every screen, showing phase and progress | `lib/features/operation_indicator.dart` (new), `lib/app.dart`, `lib/providers.dart` | med | `done` | Hosted in `MaterialApp.builder`; hidden while `browserOnScreenProvider` is true, so the Browser's own panels are never doubled |
| S2 | Stop, from the indicator, through the existing single-winner cancellation path | same | med | `done` | Calls `SaveRunController.stop` / `UpdateChecker.cancel` — the same methods the Browser's panels use. No new path |
| S3 | "Needs you" — one action that opens the Browser on the exact page | same | med | `done` | `showBrowserSurface`, which is the app's one way of revealing the Browser. It waits on the indicator; it never navigates on its own |

### Phase 5 — Vertical slices

| # | Task | Risk | Status | Acceptance |
|---|---|---|---|---|
| V1 | A Collection check runs through navigation, bridge calls and link resolution while the Reader is on screen | high | `done` | `integration_test/foreground_multitasking_test.dart` — the check navigated, probed and discovered Entry 3 with the Reader on top, and never logged a hold |
| V2 | An Entry save runs through inspect · scroll · lazy discovery · verify · extract · download · commit while the Reader is on screen | high | `done` | Same file: 19 scroll steps, 13 images seen, 6 accepted, 6/6 downloaded and committed, `waitingForBrowser` never entered. The control arm with the capability off held for 21 s at the verify phase and finished only after the Reader was popped |
| V3 | A bounded multi-Entry run continues across next-Entry detection and navigation, from the Library tab | high | `done` | Same file: a three-Entry run passing through `detectingNext` and `navigating` with the Library tab in front — the other half of the mechanism, which the Reader cases do not exercise |

### Phase 6 — Lifecycle and recovery

| # | Task | Risk | Status | Acceptance |
|---|---|---|---|---|
| L1 | Renderer termination is named rather than left to be discovered as a timeout | med | `done` | `onWebContentProcessDidTerminate` / `onRenderProcessGone` wired to `BrowserController.onRendererTerminated`, which records a classified page fault. The engine already ends the Entry on the failing probe that follows, so this adds legibility, not a new outcome. **Not exercised on a device** — inducing a renderer kill needs hardware and memory pressure (D-5) |
| L2 | No operation is duplicated and no ownership lock is stranded across a foreground round trip | med | `partial` | The foreground hold reuses the existing render guard rather than adding state, so there is nothing new to strand — `automationOwner` is untouched by this work. A device round-trip test is **not run**; recorded in §5 |

### Phase 7 — Performance and accessibility

| # | Task | Risk | Status | Acceptance |
|---|---|---|---|---|
| P1 | Measure the specification's §12 criteria, covered vs watched | med | `partial` | Scroll, download and stored-image equality measured on both targets — §6.3. Reader frame timing, memory, renderer terminations, battery and thermals **not measured**: they need a profile build on hardware |
| P2 | VoiceOver and TalkBack over a covered WebView | high | `blocked` | Hardware only. D-3 and D-4 in §5. **This is why the capability ships off** |

### Phase 8 — Gating and cleanup

| # | Task | Status |
|---|---|---|
| Z1 | `dart format lib test integration_test tool` | `done` |
| Z2 | `flutter analyze` clean | `done` |
| Z3 | `flutter test` — full deterministic suite | `done`, one pre-existing time-of-day failure — §6.2 |
| Z4 | Fixture integration suites re-run on at least one platform | `done` — the foreground suite and the gate on the iOS Simulator; the gate ×3 on the Android emulator |
| Z5 | Final diff review for scope drift, generated-file changes and dead code | `done` — 14 files changed, 10 added, no generated files, no dependency change |
| Z6 | Specification updated wherever an assumption failed | `done` — §7 of this file, and D1/D3 in the specification |

---

## 3. Independence and blocking

- **Independent of everything:** F1–F5, C1, S1–S3. They are correct with the
  capability permanently off.
- **Blocked by the gate:** K1–K4, and therefore V1–V3.
- **Blocked by K1–K4:** V1–V3, P1, P2, G5.
- **Blocked by V1/V2:** the honest claim that the feature works.

---

## 4. Device availability

| Target | Available | Used for |
|---|---|---|
| iOS Simulator, iPhone 17, iOS 26.5 | yes | G2, unit/widget/integration |
| Android emulator, Pixel 9 Pro, API 36 | yes | G3, integration |
| Physical iPhone 17, iOS 26.5.2, **cabled** | yes | G4 · D-1 · the §6.1a–§6.1c hardware records |
| Physical Android device | **no** | — · blocks D-2, D-4 |

**The wireless-pairing obstacle, and how it was cleared.** For three attempts the
only physical iPhone available was paired **wirelessly**, and `flutter test`
refuses to start an integration test on a wirelessly tethered iOS device:

```
Cannot start app on wirelessly tethered iOS device.
Try running again with the --publish-port flag
```

`flutter test` has no `--publish-port` option — that flag belongs to
`flutter run`. Attaching the phone with a **cable** resolved it and nothing else
about the runs changed. Kept because the error names a flag that does not exist
on the command it is printed by, which costs an afternoon to discover twice.

**No physical Android device has been available at any point.** Everything in
the Android column is emulator-only, which is why D-2 and D-4 are still open and
why no Android enablement claim can be made.

---

## 4a. Physical-device validation programme

Written **before** the results below it, so no threshold is chosen after seeing
what the device did. Where a threshold later changed, the change and its reason
are recorded in §7.

### Environment of record

| | |
|---|---|
| Device | iPhone 17 (`iPhone18,3`), iOS 26.5.2 (23F84), **wired**, Developer Mode on |
| Identifier | UDID `00008150-…401C` (redacted middle), CoreDevice `8CB6BC0D-…7DED` |
| Storage | 256 GB internal capacity |
| Host | macOS 26.5.2 (25F84), Xcode 26.6 (17F113) |
| Toolchain | Flutter 3.44.8 (stable, 058e0af2c2) · Dart 3.12.2 |
| Android hardware | **none connected.** Emulator only (Pixel 9 Pro, API 36) |

Build modes: correctness runs in **debug** (integration-test harness requires
it); performance and energy runs in **profile**. A debug timing is never
reported as a production figure.

### Test sources

Real, publicly reachable reading pages on the **two third-party sources this
project already used** in its earlier live-browser tests — confirmed present in
this repository's own history, and confirmed absent from
`lib/save/capture_policy.dart`, so capture is not refused for them.

Their hostnames are **deliberately not written into this repository**: the
standing rule is that nothing site-specific ships, and
`test/repository_cleanliness_test.dart` fails the build on one of them by word
alone. They are supplied at run time:

```
BUILD_ID=$(git rev-parse --short HEAD) \
flutter test integration_test/device_matrix_test.dart -d <udid> \
  --dart-define=BUILD_ID=$BUILD_ID \
  --dart-define=LIVE_ENTRY_A=<entry url on source A> \
  --dart-define=LIVE_ENTRY_B=<entry url on source B> \
  --dart-define=SOAK_ROUNDS=6
```

With no `LIVE_ENTRY_*` the live scenarios skip themselves and say so, so the
matrix is still runnable without choosing a source. `SOAK_ROUNDS` defaults to 4.

*This command originally named a `live_site_test.dart`, which no longer exists;
the live scenarios are cases inside the device matrix now. See §6.1a.*

No hostname-specific production logic is added, nothing is bypassed, and
requests stay paced by the engine's existing cooldowns. These are integration
cases, not a compatibility claim.

### Ordered phases

| # | Phase | Build | Acceptance criteria, set in advance |
|---|---|---|---|
| V-1 | Architecture gate on hardware | debug | `covered` matches `painted` on viewport and document height exactly, scroll advances, rAF within 20% of painted, `visible`, save complete with an identical stored image count. `unpainted` must **not** complete |
| V-2 | Foreground suite on hardware | debug | All four existing cases pass, unchanged |
| V-3 | Idle and cleanup probe, 12 states | debug | After every terminal state: rAF ≈ 0 over a 1 s window while covered, no automation owner, no wakelock, no operation indicator, and the app's memory returns to within 25% of its pre-operation value within 5 minutes |
| V-4 | Real-site Collection check | debug | Discovery correct; an inconclusive probe never recorded as "no updates"; exactly one terminal outcome; the Reader is never navigated away from |
| V-5 | Real-site single-Entry save | debug | Stored asset count, order and manifest inspected by hand against the page; no page furniture; opens offline; an existing complete Entry is not replaced |
| V-6 | Real-site bounded multi-Entry save | debug | Every Entry verified independently, not by the run-level flag |
| V-7 | Repetition / soak | debug | ≥ 20 real operations, ≥ 30 min elapsed, no permanent hold, no duplicate completion, no ownership leak, memory trend flat within 25% across repetitions |
| V-8 | Renderer termination | debug + device memory warning | In-flight Entry never committed complete; ownership released; app usable afterwards |
| V-9 | Lifecycle round trip | debug | No Browser-dependent work while not foreground; resumes exactly once; deadline extended by the paused time |
| V-10 | Reader performance | **profile** | With an operation running and covered, no more than 2% of frames over 16 ms above the no-operation baseline |
| V-11 | CPU / memory / energy | **profile** + Instruments | Recorded per state; post-completion CPU for the app and the web-content process must fall back to the idle baseline |
| V-12 | Thermal | profile | No `serious` or `critical` transition during a bounded run; any `fair` recovers to `nominal` after completion |
| V-13 | VoiceOver | debug | No web-page semantics reachable while the Browser is covered. **Release blocker if violated** |

### Failure and retry rules

- A hold that does not release is a **release blocker**, investigated to root
  cause. Increasing a timeout is not an investigation.
- Any intermittent failure is repeated at least three times before it is
  called intermittent, and is recorded either way.
- A performance miss is traced to a dominant cause and fixed where the cause
  is; it is never fixed by weakening a correctness guard, reducing save
  fidelity, or quietly shrinking the requested operation.

### Enablement criteria

The capability may only be enabled by default on a platform where V-1, V-3,
V-5, V-7, V-8, V-9 and V-13 have all passed **on that platform's hardware**.
Anything short of that leaves it behind the existing setting.

---

## 5. Device tests — done and remaining

Recorded here in full so they can be run without this document's author.

| | Test | State |
|---|---|---|
| D-1 | Covered rendering on a physical iPhone | **Done — PASSED**, §6.1 |
| D-2 | Covered rendering on a physical Android device | **Open** — no device |
| D-3 | VoiceOver over a covered WebView | **Open** — release blocker |
| D-4 | TalkBack over a covered WebView | **Open** — release blocker, no device |
| D-5 | Thermal and battery over a bounded covered run | **Open** — needs a profile build |

### D-1 · Covered rendering on a physical iPhone — **done, passed**

Result and numbers: §6.1. The procedure is kept because D-2 is the same one, and
because a re-run is what a plugin or OS upgrade would call for.

1. Attach the iPhone **with a cable** — wireless pairing is refused for
   integration tests (§4). Unlock it and keep it awake.
2. `flutter test integration_test/occlusion_gate_test.dart -d <udid>`.
3. Record the three `[gate]` lines.
4. Then `flutter test integration_test/foreground_multitasking_test.dart -d <udid>`
   and record all four cases.

**Pass:** `covered` matches `painted` on viewport, document height, scroll
advance, `requestAnimationFrame` rate within 10%, `visibility=visible`,
`save=complete`, and an identical stored image count.
**Fail:** any divergence. A fail forces the §4.3 fallback, and the capability
must default off on iOS until it passes.

### D-2 · Covered rendering on a physical Android device — **open**

As D-1, with `-d <serial>`. Not run: no physical Android device has been
available (§4). Until it is, no claim about Android hardware may be made from
the emulator results, which is where **U2** in the specification stands.

### D-3 · VoiceOver over a covered WebView (release blocker)

1. Start a save from the Browser on a fixture Entry, then open a downloaded
   Entry in the Reader.
2. Turn VoiceOver on. Swipe through the Reader from the first element to the
   last.

**Pass:** no element of the web page is announced, focusable or in the swipe
order; the Reader's own order is unchanged; the operation indicator is announced
with its phase; Stop and "Needs you" are announced as actions.
**Fail:** any page content announced. Treated as a release blocker.

### D-4 · TalkBack over a covered WebView (release blocker)

As D-3, with TalkBack.

### D-5 · Thermal and battery over a bounded covered run

Three-Entry save with the Reader on screen, screen on, profile build. Record
battery delta, any thermal notice, and any renderer termination.

---

## 6. Validation record

Filled in as work happens. An unmeasured row says so.

### 6.1 Architecture gate

| Target | OS | Build | Result |
|---|---|---|---|
| iPhone 17 Simulator | iOS 26.5 | debug | **PASSED** — covered identical to painted on every measure; unpainted stops `requestAnimationFrame` and reports `hidden` |
| Pixel 9 Pro emulator | Android 16 (API 36) | debug | **PASSED** — covered identical to painted; unpainted throttles `requestAnimationFrame` to 13/s and still reports `visible` |
| **iPhone 17, cabled** | **iOS 26.5.2** | **debug** | **PASSED** — see the hardware table below |

**iPhone 17 (`iPhone18,3`), iOS 26.5.2, wired, debug**

| Arm | viewport | document | scroll | rAF/s | `visibilityState` | save | images |
|---|---|---|---|---|---|---|---|
| painted | 874 | 6957 | 0 → 900 | 62 | `visible` | complete | 6/6 |
| **covered** | 874 | 6957 | 0 → 900 | 66 | `visible` | **complete** | **6/6** |
| unpainted | 874 | 6957 | 0 → 900 | **0** | `hidden` | **held at `waitingForBrowser`** | **0** |

Two things hardware said that neither simulator nor emulator did:

1. **Covered is indistinguishable from visible on a real device.** Identical
   viewport and document height, scroll advancing, rAF at the display rate, and
   a byte-identical save. U1 is closed for iOS.
2. **The unpainted control held and stored nothing** — where the simulator ran
   it to completion. The new page-visibility half of **D1** is what caught it,
   on the one platform where that signal discriminates. The old viewport-only
   check would have missed it here exactly as it did on the simulator.

Numbers: specification §3.1.

### 6.1a Idle and cleanup, on hardware

Measured against a **real** reading page, iPhone 17, debug build. `raf/s` is
`requestAnimationFrame` ticks in a one-second window — the signal that says
whether the page is still doing work. Memory is the app's own `phys_footprint`;
the web renderer is a separate process and is measured by Instruments
separately.

*The harness these were taken with was `device_validation_test.dart`, which no
longer exists. It measured the right things and waited for them wrongly: three
device runs were lost to it sitting inside a generous timeout after a scenario
had already failed. `integration_test/device_matrix_test.dart` replaced it —
every wait bounded and announced, every scenario capped, and a harness stall
reported as a harness verdict rather than as evidence about the product
(`integration_test/support/device_harness.dart`). The numbers below stand; a
re-run uses the matrix.*

| # | State | raf/s | timer/s | `visibilityState` | painted | owner | app MB |
|---|---|---|---|---|---|---|---|
| 1 | fresh · Browser never opened | **0** | 7 | hidden | no | — | 353 |
| 2 | Browser open · real page loaded | 59 | 19 | visible | yes | — | 458 |
| 3 | left Browser for Library | **0** | 6 | hidden | no | — | 448 |
| 4 | immediately after a save | 174 | 20 | visible | yes | **—** | 468 |
| 5 | Reader open · nothing running | **0** | 7 | hidden | no | — | **1459** |
| 6 | +2 min after completion | **0** | 7 | hidden | no | — | 1436 |
| 7 | after cancellation | **0** | 7 | hidden | no | — | 638 |
| 8 | app inactive | 112 | 19 | visible | **no** | — | 638 |
| 9 | back in the foreground | 192 | 21 | visible | yes | — | 634 |

**The cleanup policy, as measured rather than assumed.** The WebView stays
mounted for the session — that is what makes "come back and the page is still
there, still scrolled, still signed in" true — and in every state where the app
is not painting it, the page does **no** animation work at all: `raf/s` is
exactly 0 in states 1, 3, 5, 6 and 7. Timers throttle from ~20/s to ~6-7/s;
that residue is WebKit's own background throttling, not something the app
sets, and it is recorded rather than asserted on. Every terminal state —
complete, cancelled — released the automation owner. No operation stayed live.

So the answer to "should the WebView be disposed, blanked, suspended or left
alone?" is **left alone**: on this platform an unpainted WebView is already
quiescent, and disposing it would cost the session continuity the product is
built on while buying nothing measurable. That is now a durable invariant.

Caveat stated rather than buried: state 8 was produced by dispatching the
lifecycle event, not by actually backgrounding the app, so the 112 raf/s there
is the harness still on screen. What it does prove is the part that matters —
the app's own `surfaceIsPainted` correctly went false, which is what makes a
run hold.

### 6.1b Real sources, on hardware

Both historical URLs from this project's earlier live tests are **404** today.
Current entry pages on the same two sources were found by ordinary browsing and
passed in at run time. Hostnames are not recorded here — see §4a.

| | Source A | Source B |
|---|---|---|
| Watched save | **76 of 76 assets, complete** | **19 of 19 assets, complete** |
| Classified as | `textAndImages` (article: `<main>` + prose) | — |
| Next-Entry detection | a Turkish labelled control, by generic rules | — |
| Covered save (Reader on top throughout) | ran every phase, **`held=false`** | see below |

The covered save never entered `waitingForBrowser` — it never had to ask for the
Browser back. That is the product claim, on real hardware, against a real page.

### 6.1c Reader memory — investigated, partly fixed, and honestly not solved

**Measured, physical iPhone, debug, same real Entry (76 inline images), before
and after the decode change:**

| State | Before | After |
|---|---|---|
| Fresh, Browser never opened | 353 MB | 350 MB |
| Browser open, real page | 458 MB | 450 MB |
| Immediately after the save | 468 MB | 482 MB |
| **Reader open on the Entry** | **1459 MB** | **1465 MB** |
| +45 s / +2 min later | 1436 MB | 1424 MB |
| After the Reader closed | 638 MB | 634 MB |

**The optimization did not help this Entry.** That is the result, and it is
reported rather than buried.

What was found, in order:

1. The Entry is a **structured document**, not an image sequence — the real
   page classified as `textAndImages`, so it was saved as 81 blocks with 76
   inline images.
2. `document_reader.dart` builds every block eagerly, by design and with a
   documented reason: a lazily-built list does not know the offset of a block
   it has not built, and exact offsets are what make restore land on the
   paragraph the reader left. So **all 76 images are resident at once**.
3. Both readers passed `cacheWidth` = display width unconditionally, which
   *upscales* a stored image narrower than the screen and costs
   `(display/natural)²` for no added detail. That is a genuine defect and it is
   fixed (`lib/reading/decode_budget.dart`, 8 unit tests).
4. **But this content is not narrower than the screen**, so the clamp never
   engaged, and no single panel exceeded the 24 MP budget either. Arithmetic on
   the measured delta: ≈983 MB over 76 images ≈ 13 MB each ≈ 3.2 MP — an
   ordinary panel decoded at display width. Nothing per-image is wrong.

**So the cost is the count, not the size, and the count comes from the eager
document build.** Fixing that means making image blocks lazy while keeping text
offsets exact — a real change to a subsystem this feature does not own, needing
its own device validation for restore drift, flashing and repeated decoding.
Attempting it here would breach "do not introduce flashing or repeated
decoding" without time to prove it did not.

**Decision:** keep the decode fix (correct, tested, helps content that *is*
narrower than the screen, and prevents the pathological single panel), record
the eager-document build as a **separate Reader issue**, and keep the capability
disabled. It is not a foreground-multitasking defect — but concurrent Reader and
WebContent execution is exactly what makes it matter, so it is a named blocker
for enablement rather than someone else's problem.

One flaw in the fix itself was found and corrected during this work: the
document path initially bounded the decode by `EntryAsset.width` without
checking `dimensionsVerified`. That field is the *page's* claim when unverified,
and trusting it could ask for fewer pixels than the file holds — a silent
quality reduction. It now bounds only on dimensions read back from the stored
bytes.

### 6.2 Test runs

**During the feature work:**

| Command | Result |
|---|---|
| `flutter analyze` | **PASSED** — no issues |
| `dart format lib test integration_test tool` | **PASSED** — applied |
| `flutter test` (deterministic suite, 1350+ cases) | **PASSED except one pre-existing failure**: `browser_screens_test.dart › History screen groups by day and lists real visits`. It seeds a visit at `now - 1d3h` and asserts a `YESTERDAY` header, so between local midnight and 03:00 that visit lands two calendar days back. Unrelated to this work, and reported rather than fixed |
| `flutter test test/foreground_multitasking_test.dart` | **PASSED** — 15 cases |
| `flutter test integration_test/occlusion_gate_test.dart -d <iOS Simulator>` | **PASSED** |
| `flutter test integration_test/occlusion_gate_test.dart -d <Android emulator>` | **PASSED** (×3) |
| `flutter test integration_test/foreground_multitasking_test.dart -d <iOS Simulator>` | **PASSED** — 4 cases |

**Later, at `10134dd`, during a documentation audit** — not a re-validation of
the feature, and no integration suite was run:

| Command | Result |
|---|---|
| `flutter test` (deterministic suite) | **PASSED — 1586 cases, no failures.** The time-of-day case above passed, but the run was outside the 00:00–03:00 window that triggers it, so this neither reproduces nor clears it |
| `flutter analyze` | **PASSED** — no issues |
| `dart format --output=none --set-exit-if-changed lib test integration_test tool` | **PASSED** — 223 files, 0 changed |

Integration-case notes:

- All four cases pass: the save while the Reader is open, the capability-off
  control, the bounded multi-Entry run from the Library tab, and the Collection
  check while the Reader is open.
- **One flake, recorded rather than forgotten.** In an earlier three-case run
  the Collection-check case failed once, holding at `browser surface is not
  rendered` for its whole budget. It passed alone immediately afterwards, and
  passed again in the four-case run. Not reproduced since; noted because a
  hold that never releases is the failure mode this design most needs to not
  have, and one sighting is not nothing. Tracked as U6 in the specification.

### 6.3 Performance

Method: the architecture gate's three arms save the same fixture Entry with the
same production engine, and the engine's own `[timing]` line is the measurement.
Debug builds — which is a caveat, not a footnote: absolute numbers are not
release numbers. The comparison between arms is the result; the absolute values
are not.

**Scroll phase — the phase that depends on the page still rendering**

| Target | painted | covered | Δ | Threshold |
|---|---|---|---|---|
| iPhone 17 Simulator, iOS 26.5 (n=1) | 4963 ms | 4958 ms | **−0.1%** | ±15% |
| Pixel 9 Pro emulator, API 36 (n=3) | 2266 / 2989 / 2946 ms (mean 2734) | 2841 / 2815 / 2840 ms (mean 2832) | **+3.6%** | ±15% |

The Android n=1 sample alone would have read as +25%; three runs show the
2266 ms painted figure was the outlier and the covered arm is flat. Recorded
because a single sample was nearly enough to draw the wrong conclusion.

**Download phase** — 2089 → 2086 ms (iOS), 4146 → 4144 ms (Android). Unchanged,
as expected: it is direct HTTP and never touched layout.

**Stored image count, covered vs painted** — 6/6 on both targets, both arms.
An equality, and it held.

**Not measured, and reported as such:** Reader frame timing under an operation,
memory high-water, renderer terminations, battery and thermals. All need a
profile build on physical hardware (D-5), which was not available. No claim is
made about them.

**Startup** — unchanged by inspection: the capability is one settings read
inside the existing critical boot step, and the boot sequence gained no step.
Not separately timed.

---

## 7. Assumptions that failed

Recorded rather than quietly worked around.

| # | Assumption | What actually happened | What changed |
|---|---|---|---|
| A1 | An unpainted WebView reports a zero viewport, so `SaveEngine._waitForRenderedSurface` protects against saving from one | On both platforms the unpainted arm reported a full viewport, accepted programmatic scrolling, and completed a save. The guard never fired | The guard's authority moves to the app (**D1**), which knows whether it is painting. The page-side checks stay as corroboration and are not relaxed |
| A2 | `document.visibilityState` is a portable way to tell painted from unpainted | True on iOS, false on Android — an unpainted Android WebView still reports `visible` | It is used as a *hold* signal only: `hidden` holds, `visible` proves nothing |
| A3 | An `InAppWebView` built without `initialUrlRequest` can simply be navigated with `loadUrl` | With `useShouldOverrideUrlLoading: true` and no `shouldOverrideUrlLoading` callback, every `loadUrl` was silently dropped on iOS and the page stayed on `about:blank` | The gate harness mirrors the production callback set. Worth knowing for any future harness |
| A4 | Integration tests can reach the in-process fixture site on Android as they do on iOS | Android blocks cleartext to the loopback address from API 28; the WebView landed on an error page | A network security config in the **debug** source set permits `127.0.0.1` and `localhost` only. Release and profile builds are untouched |
| A5 | An empty link set can simply be called a failure (**D3** as first written) | It broke a legitimate case: the last Entry in a chain genuinely has no next link, and the deterministic fixture models that with a page carrying no links at all. Turning that into a failure would have made every up-to-date Collection report an error | D3 became "never accepted on first sight": one settle window, a second read, and an explicit *inconclusive* line if it is still empty. The silence is gone; the false failure never arrived |
| A7 | `document.visibilityState` is safe to use as a veto, because it only ever says "hidden" when the surface really is hidden | On a physical iPhone, a Collection check started from the Reader held on it for its entire budget and failed, on a page the app was drawing throughout. WebKit fixes a document's visibility at creation, and the check's own navigation created that document one frame before the drawing landed | Cause fixed (`awaitPaintedSurface` before the first navigation) and symptom bounded (`kPageHiddenGrace`). Specification §7.2; regression tests in `test/foreground_multitasking_test.dart` |
| A6 | One timing sample per arm is enough to judge the performance cost | The first Android sample read as +25% on the scroll phase. Two more runs showed the *painted* baseline had been the outlier and the real difference is +3.6% | Three runs per arm on Android, and the single-sample figure is recorded next to the corrected one rather than deleted |
