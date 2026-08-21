# Foreground multitasking

**Status: specification.** The implementation plan and its live checklist are in
[FOREGROUND_MULTITASKING_PLAN.md](./FOREGROUND_MULTITASKING_PLAN.md). Read
[TERMINOLOGY.md](./TERMINOLOGY.md) and [ARCHITECTURE.md](./ARCHITECTURE.md)
first; everything here is an addition to the model those two describe, not a
replacement for any part of it.

---

## 1. The outcome

A user starts a Collection check or an Entry save and can keep using
Scrollary — above all, keep reading an Entry they already have — while that
same operation continues.

The application stays open and in the foreground throughout. The work is the
work the user started, it is bounded by the scope they chose, and it is
visible while it runs.

Today the same run holds. Every Browser-dependent phase — inspecting,
scrolling, waiting for assets, verifying, extracting, detecting the next
Entry, navigating to it — requires the Browser tab to be the thing on screen.
Leaving is either refused by a confirmation or turns into a pause
(`kPauseBrowserHidden`, `SaveState.waitingForBrowser`). Only the direct-HTTP
download and the commit already survive leaving, because
`SaveRunController.needsRenderedBrowser` deliberately excludes them.

Finishing that download tail while the Reader is open is *not* the outcome.
The outcome is the whole run continuing.

### 1.1 Not in scope, in one sentence

Nothing here continues after the app is minimised, after the screen locks, or
through an OS background service, a scheduler, `WorkManager`, a foreground
service, `BGTaskScheduler`, or a persisted authorisation to resume work later —
those remain out of scope and unbuilt, and the app's standing rule that nothing
saves in the background is unchanged.

---

## 2. Scope and non-goals

**In scope**

- One user-started operation continuing through its Browser-dependent phases
  while the user is somewhere else *in the app*.
- Reading an already-downloaded Entry while that happens.
- Library, Collection, Activity, Settings and every other screen staying usable.
- A clear, accessible way to see what is running, stop it, and go to it when it
  needs a person.

**Non-goals, explicitly**

| Not this | Why |
|---|---|
| OS background execution, screen-lock continuation | §1.1; the app has no background modes and gains none |
| A scheduler, or work that starts without the user | Queued work still waits for an explicit Start, and that authorisation is still never persisted |
| Parallel captures | One operation owns the WebView. Concurrency is not required by this outcome and would remove a structural guarantee |
| A site catalogue, presets or per-host capability records | Nothing site-specific ships; the one exception stays `lib/save/capture_policy.dart` |
| Getting past a login, a CAPTCHA, a consent dialog, a paywall or any access control | The app stops; it never works around |
| A broad terminology migration | `Collection` and `Entry` stay the model; legacy internal names are left alone |
| A navigation rewrite | The router, the shell and the two tabs stay as they are |
| Replacing or losing downloaded content | A run that cannot see its page must not write |
| A claim of universal site compatibility | The honest bound is "the same pages that work today, while you look elsewhere" |

---

## 3. Measured baseline

Everything below was measured before any production code changed, by
`integration_test/occlusion_gate_test.dart`. It drives one real
`InAppWebView`, one real `BrowserController` and the production
`SaveRunController` over the existing fixture Entry (`tool/fixture/`), whose
four lazy panels arrive through an `IntersectionObserver` with a 400 ms delay.
A run that stores 6/6 images therefore exercises viewport, scrolling, timers,
JavaScript, `IntersectionObserver` and lazy loading together.

Three arms, one native view, re-composited without being rebuilt:

- **painted** — nothing above it. Today's Browser tab.
- **covered** — painted, with an opaque full-screen layer drawn over all of it.
  What a Reader route would do above a Browser that keeps painting.
- **unpainted** — laid out but not painted, through `IndexedStack`. Today's
  shell when the Library tab is selected.

### 3.1 Results

**iOS Simulator — iPhone 17, iOS 26.5, debug build**

| Arm | viewport | document | scroll | rAF/s | `visibilityState` | save | images |
|---|---|---|---|---|---|---|---|
| painted | 874 | 6957 | 0 → 900 | 61 | `visible` | complete | 6/6 |
| covered | 874 | 6957 | 0 → 900 | 61 | `visible` | complete | 6/6 |
| unpainted | 874 | 6957 | 0 → 900 | **0** | `hidden` | complete | 6/6 |

**Android emulator — Pixel 9 Pro, API 36, debug build**

| Arm | viewport | document | scroll | rAF/s | `visibilityState` | save | images |
|---|---|---|---|---|---|---|---|
| painted | 2162 | 5921 | 0 → 900 | 61 | `visible` | complete | 6/6 |
| covered | 2162 | 5921 | 0 → 900 | 65 | `visible` | complete | 6/6 |
| unpainted | 2162 | 5921 | 0 → 900 | **13** | `visible` | complete | 6/6 |

**Physical iPhone 17 (`iPhone18,3`), iOS 26.5.2, cabled, debug build.** Run
later than the two above, after the **D1** guard existed — which is why its
`unpainted` arm behaves differently from the simulator's, and the difference is
the point rather than an inconsistency.

| Arm | viewport | document | scroll | rAF/s | `visibilityState` | save | images |
|---|---|---|---|---|---|---|---|
| painted | 874 | 6957 | 0 → 900 | 62 | `visible` | complete | 6/6 |
| covered | 874 | 6957 | 0 → 900 | 66 | `visible` | **complete** | **6/6** |
| unpainted | 874 | 6957 | 0 → 900 | **0** | `hidden` | **held at `waitingForBrowser`** | **0** |

Hardware said two things neither the simulator nor the emulator did. **Covered
is indistinguishable from visible on a real device** — identical viewport and
document height, scroll advancing, rAF at the display rate, and a
byte-identical save. And **the unpainted control held and stored nothing**,
where the simulator had run it to completion: the new page-visibility half of
**D1** caught it, on the one platform where that signal discriminates. The old
viewport-only check would have missed it there exactly as it did on the
simulator.

Conclusions that follow from the numbers rather than from expectation:

1. **Covering is not hiding, on both platforms.** A painted-but-fully-covered
   platform view keeps its viewport, keeps scrolling, keeps running
   `requestAnimationFrame` at the display rate, and completes a real save
   byte-identically to the visible baseline. This is the premise the whole
   feature rests on, and it is measured on two targets rather than assumed.
2. **The existing zero-viewport guard does not fire at all.** In the unpainted
   arm, on *both* platforms, the page reported a full viewport and accepted
   programmatic scrolling — so `SaveEngine._waitForRenderedSurface` never
   triggered, and the save ran to completion on a surface nobody was
   compositing. What actually degrades when unpainted is
   `requestAnimationFrame`: stopped dead on iOS, throttled to roughly a fifth of
   the display rate on Android. That is exactly the "throttles rAF and
   lazy-loading" hazard `lib/app.dart` already warns about, and it is why the
   2026-07-27 audit saw a complete-looking entry made of the wrong images. The
   fixture survives it only because its lazy loading is `setTimeout`-driven; a
   `requestAnimationFrame`-driven page would have stalled or under-collected.
3. **No page-side signal is a portable discriminator.**
   `document.visibilityState` separates the arms correctly on iOS and **not at
   all on Android**, where an unpainted view still reports `visible`. Viewport,
   document height and scroll are useless on both. The rAF rate is a difference
   of degree, not of kind, and sampling it costs a second per check.

Point 2 is a pre-existing correctness gap, found by this work. Point 3 changes
where the fix has to live: the authority on whether the app is painting its own
WebView is **the app**, not the page. That is invariant **D1** in §7, and it is
strictly stronger than what ships today, because today's check can be satisfied
by a surface that is not being composited at all.

---

## 4. Architecture decision

### 4.1 Options considered

| | **A — offstage** | **B — keep the one WebView painted** | **C — a second, sized automation WebView** | **D — move the native view between hosts** |
|---|---|---|---|---|
| Mechanism | Let the existing WebView go unpainted and remove the guards | Keep the single WebView painted whenever an operation owns it; other screens cover it | A second `InAppWebView` (or `HeadlessInAppWebView`) drives automation while the Browser stays interactive | Park the live Browser view into a hidden host when the user leaves, promote it back on return |
| Correctness | Fails. This is the 2026-07-27 audit's failure mode, and §3.1 shows the guard that was supposed to catch it does not always fire | One viewport, one surface, one session. A covered run and a watched run select the same `srcset` candidate and store the same bytes **by construction** | Two rects can disagree. Matching them deliberately is fragile across rotation, dynamic type and split view, and the divergence is invisible and permanent once committed | n/a |
| Silent-failure risk | Highest | Lowest — and the new visibility invariant makes the remaining failure a *hold*, not a wrong write | Real: a run at a different effective viewport storing a different but plausible image set | n/a |
| Supported by the pinned plugin | n/a | Needs no plugin feature at all | Yes | **No.** `HeadlessInAppWebViewManager.run` on both platforms unconditionally constructs a new native web view and unconditionally performs the initial load. There is no adoption branch for an existing widget-hosted view. Headless → widget promotion *is* supported; widget → headless is not |
| Engine reuse | n/a | ~100%. `SaveEngine`, `SaveRunController`, `UpdateChecker` and `AssetFetcher` never learn anything happened | ~95%. They already take a `BrowserController`, so they would drive a second one unchanged; the wiring and ownership around them change | n/a |
| Single-task invariant | n/a | Survives untouched. One `automationOwner` on one controller keeps "one at a time" structurally impossible to violate | Converts a structural impossibility into a rule somebody has to keep, in the subsystem where this repository has been most deliberate about structural guarantees | n/a |
| Memory | n/a | One web content process | Two, competing during the most memory-hungry operation the app performs; on iOS the backgrounded one is reclaimed first, and it is the hidden one | n/a |
| Global operations | n/a | Unchanged owner | Cookie deletion, cache clearing and Android's timer pause are process-global; clearing website data would destroy a running operation's session | n/a |
| Return to the Browser | n/a | Same surface, same page, same scroll, same session. Nothing to reconcile | Promotion works, but is one-way: the next operation needs a fresh hidden surface, which reloads | n/a |
| Accessibility | n/a | Handled by Flutter's own route machinery for pushed screens (§6.4) | A permanently mounted parallel view needs its own exclusion, and the iOS behaviour of that is unverified | n/a |
| Rollback | n/a | One boolean. Off ⇒ today's structure and today's behaviour, exactly | Removing a second WebView after the ownership model has been rewritten around it | n/a |

### 4.2 Decision

**Primary: B — one WebView, kept painted.**

Not because it is the smaller change. Because it is the only option in which a
run the user is *not* watching produces the same bytes as one they are, and
because it keeps the property this codebase has already paid for once: exactly
one WebView, exactly one automation owner, no second surface that can quietly
disagree.

Concretely, and deliberately minimally:

1. **The `InAppWebView` does not move.** It stays where `browser_screen.dart`
   constructs it today, at the same rect, inside the same shell. Its viewport is
   constant because nothing about its layout changes. No second WebView, no
   headless view, no root re-hosting, no keep-alive migration.
2. **When an operation owns the WebView and the capability is enabled, the app
   keeps that WebView painted**:
   - the shell keeps the Browser child onstage underneath the Library tab
     instead of switching it off;
   - screens pushed above the shell become non-opaque routes, so Flutter keeps
     painting the shell beneath them.
3. **Occlusion, input blocking and semantics blocking are Flutter's**, not
   hand-rolled. A `ModalRoute`'s barrier already absorbs pointers and wraps the
   content in `BlockSemantics`, so a screen pushed above the shell hides the
   Browser from touch and from assistive technology while it keeps painting. The
   tab case gets the same two properties explicitly (§6.4).
4. **A stronger liveness invariant** replaces the viewport-only check. The app
   publishes whether it is painting its own WebView, and a Browser-dependent
   phase requires that, in addition to the page-side checks that already exist
   (§7, **D1**). This is what makes the design fail-safe: if the surface stops
   being painted for any reason — the capability is off, a future screen is
   opaque, the app leaves the foreground — the operation *holds* and asks for the
   user, exactly as it does today for a hidden tab. It also closes a gap that
   exists right now, where an unpainted surface passes the viewport check on both
   platforms.

### 4.3 Fallback, and what would force it

**Fallback: C**, a second sized automation WebView, with the differential
validation C needs to be safe (a first run per operation compared against a
watched run, and a refusal to commit on divergence).

Evidence that would force reconsideration:

- A physical device on either platform failing the `covered` arm of
  `occlusion_gate_test.dart` — a zero or changed viewport, a frozen scroll,
  `requestAnimationFrame` stopping, or the save storing fewer images than the
  painted arm.
- `document.visibilityState` reporting `visible` for an unpainted surface on a
  physical device, which would make **D1** unable to tell the two apart.
- Semantics leaking from a covered WebView to VoiceOver or TalkBack that
  `BlockSemantics` / `ExcludeSemantics` cannot suppress. This is a release
  blocker, not a polish item.

**Rollback** is one flag. `ForegroundMultitasking.enabled == false` restores
exactly today's behaviour: the shell switches the Browser child off, routes are
opaque, `needsRenderedBrowser` triggers the leave-Browser confirmation, and a
run that loses the surface holds at `waitingForBrowser`. No data shape, no
column, no manifest field and no engine changes with the flag, so turning it off
cannot strand anything.

### 4.4 The smallest experiment that resolves the remaining unknown

`integration_test/occlusion_gate_test.dart`, run on a physical iPhone and a
physical or emulated Android device. It is the same three arms that produced
§3.1 and it takes about a minute per platform.

---

## 5. Behavioural state model

Six states, and no new persisted state machine. Every one of them maps onto
machinery that already exists, because a seventh concept is a seventh thing to
keep consistent.

| State | Meaning | Backed by |
|---|---|---|
| **Working** | A Browser-dependent or download phase is progressing | `SaveProgress.state` (`inspecting` … `saving`), `UpdateChecker.isRunning` |
| **Waiting** | Held, and expected to continue on its own | `SaveState.waitingForBrowser`, `SaveState.paused`, `pauseReason` |
| **Needs you** | Held, and it will not continue until a person acts | `SaveState.awaitingSelection`, and the access-control stops in `stop_conditions.dart` |
| **Completed** | Finished | `SaveState.complete` / `partial`, queue `completed` |
| **Failed** | Stopped by a condition, terminally | `SaveState.failed`, queue `failed`, a named `StopReason` |
| **Cancelled** | Stopped because the user said so | `SaveState.cancelled`, queue `cancelled` |

### 5.1 Transitions

```
            ┌──────────────────────────── user cancels ─────────────────┐
            │                                                           v
Working ───────► Waiting ────── surface returns ──────► Working    Cancelled
   │  ▲            │                                       │  ▲
   │  └────────────┘                                       │  │
   │   app leaves the foreground / surface lost            │  └── user acts
   │                                                       │
   ├──────────────► Needs you ─────────────────────────────┘
   │
   ├──────────────► Completed
   └──────────────► Failed
```

- **Persisted:** the terminal three, on the queue row and on the entry; and the
  pause reason on the `save_runs` row, which already happens.
  Nothing about *presentation* is persisted — not "this run is allowed to move
  the user", not "the Browser is being kept painted", not an authorisation to
  start.
- **Resumes automatically:** Waiting → Working, when the surface reports itself
  visible again, or when the app returns to the foreground. This is the existing
  `resumeAfterBrowserVisible` / `_waitForRenderedSurface` path.
- **Requires explicit user action:** Needs you → Working. Never automatic, and
  never a retry with different headers, a different URL, or a wait-out.
- **Terminal:** Completed, Failed, Cancelled. A terminal row is never revived.

### 5.2 Ownership

- **Navigation of the WebView** is owned by whoever holds
  `BrowserController.automationOwner`. Unchanged. While it is held, the Browser
  is not interactive and says so.
- **Navigation of the app** is owned by the user. A running operation never
  moves them. The one existing exception stays: the operation that *brought the
  Browser forward* is the one that may put it back, and only while it still
  owns the foreground (`LibraryCheckFlow.ownsForeground`, which releases the
  moment the user pushes a surface of their own).
- **Cancellation** has exactly one winner, through the existing conditional
  `updateQueueTaskIfState` SQL `UPDATE`. Unchanged, and this feature adds no
  second cancellation path.

### 5.3 Races and hostile cases

| Case | Behaviour |
|---|---|
| User taps Cancel while the pump is claiming the row | The conditional `UPDATE` decides; the loser is told and the pump skips the row |
| User navigates the Browser while an operation owns it | Impossible — the operation holds `automationOwner` and the Browser surface is not interactive |
| Operation completes while the user is deep in the Reader | The report is recorded; nothing navigates. The user finds it in Activity and on the Collection |
| Surface stops reporting visible mid-phase | The phase holds (Waiting) and resumes when it returns. Committed work is untouched |
| Renderer terminates | Treated as a page failure for the current Entry: never a completion, never a partial write, never an automatic retry loop |
| App leaves the foreground | The operation holds (Waiting), and resumes on return. It does not continue while the app is not in front |
| Website data cleared while an operation runs | Refused, the way deletion is already refused while an entry is open |

---

## 6. WebView and automation invariants

| # | Invariant |
|---|---|
| **W1** | **There is exactly one `InAppWebView` in the app.** `lib/features/browser_screen.dart` is the only place one is constructed, and `lib/browser/browser_controller.dart` is the only file in `lib/` that imports the plugin. This feature adds neither a second WebView nor a headless one. |
| **W2** | **At most one WebView-dependent operation runs at a time**, enforced by `automationOwner` on the single controller. The queue respects it rather than duplicating it. |
| **W3** | **The WebView's rect never changes with what is on screen.** It is laid out by the Browser tab and only by the Browser tab. Covering it does not relayout it. This is what makes a covered run and a watched run select the same responsive candidate. |
| **W4** | **Cookies, cache, local storage and website-data clearing stay owned by the single controller**, and clearing is refused while an operation is live. |
| **W5** | **The Browser is not interactive while an operation owns it**, and the operation's presence is stated on the surface rather than implied by an inert page. |
| **W6** | **Handing the WebView back to the user is a navigation, not a transplant.** "Needs you" takes the user to the Browser, on the exact page, through `ensureBrowserVisible(url:)`. The native view is never moved between hosts. |
| **W7** | **A covered WebView is invisible to touch and to assistive technology.** For a pushed screen this is the route barrier's `BlockSemantics` and pointer absorption; for the Library tab it is an explicit `IgnorePointer` + semantics exclusion. |
| **W8** | **Renderer termination is detected and surfaced**, never silently read as an empty page. |
| **W9** | **Every screen above the shell is an `AppPage`.** A `GoRoute` written with `builder:` gets go_router's default opaque page, which stops Flutter painting the shell, which stops the WebView, which makes a running operation hold — with nothing failing to compile. `test/route_paint_invariant_test.dart` reads `lib/app.dart` and fails the build on a route that bypasses the single `_page()` helper; it carries a deliberately broken sample so the guard is known to be able to fail. |
| **W10** | **The retained page is left mounted and quiescent.** Measured on hardware: with the app not painting it, `requestAnimationFrame` is exactly 0 and timers throttle to roughly a third of their normal rate. Disposing it, blanking it or navigating it away would cost the session — cookies, scroll position, sign-in — and buy nothing measurable. What the page's own timers do with that residue is the site's business and is bounded by the platform; see §7.3. |

---

## 7. Data-safety invariants

These are the rules that make it safe for an operation to write while nobody is
watching. Each is enforceable and each has a test.

| # | Invariant |
|---|---|
| **D1** | **A Browser-dependent phase requires the app to be painting the WebView.** The authority is `BrowserController.surfaceIsPainted`, published by the one widget that hosts the WebView and by the shell that decides whether it is onstage — because §3.1 showed that no page-side signal answers this portably. The page-side checks corroborate it, and the whole decision lives in one place, `surfaceHoldReason`. A zero viewport holds **without limit**; so does the app not drawing. A page that calls itself hidden *while the app is drawing it* is a contradiction and holds only for `kPageHiddenGrace`, after which the app's own knowledge wins and the log says so — see §7.2. |
| **D2** | **A covered operation writes exactly what a watched one would.** No phase, threshold, timeout, scroll strategy, candidate rule or capture mode differs by whether the user is looking. There is no "hidden mode" code path. |
| **D3** | **An empty link set is never accepted on first sight.** A page that answers a check with no links at all has not said the chain ends; it has said nothing, and reading that as "no new Entries" is the check's characteristic silent failure. The page gets one settle window and is read again — `readyState` cannot help, because a page that builds its own list is `complete` long before the list exists — and a second empty read is reported as inconclusive rather than passed off as a clean result. The entry-list strategy already declines to trust an unrecognised list and falls through to the chain walk; that is unchanged. |
| **D4** | **An existing complete Entry is never replaced by an operation the user is not watching.** The duplicate policy still decides; what changes is that "overwrite" is not available to an unattended path. |
| **D5** | **Reading progress is untouched.** Reading columns remain writable only from `lib/reading/`, through `writeEntryReading`, and no part of this feature reaches them. |
| **D6** | **Partial work stays recoverable.** Staging, `.previous` restoration and startup recovery are unchanged, and recovery still never promotes an entry to complete. |
| **D7** | **A refusal is terminal and visible.** A run stopped by a stop condition writes a `failed` row with its `StopReason`; it is not deleted, not retried automatically, and does not leave a partial entry claiming to be whole. |
| **D8** | **Offline files, manifests and Collection metadata are only ever written by the same code paths as today.** This feature adds no new writer. |

### 7.2 A document born hidden

Found on a physical iPhone against a real site, and the reason **D1** is worded
the way it is.

WebKit fixes `document.visibilityState` when a document is **created**. A
document created in a view that is not being composited starts life `hidden`
and *stays* hidden after the view is composited — the flag describes the moment
of birth, not the present.

An operation that starts while the user is already on another screen creates
exactly that document: claiming the WebView is what makes the app start drawing
it again, and navigating in the same breath opens the page before the drawing
has landed. A Collection check started from the Reader did this, then held on
its own page-visibility check for the full three-minute budget and failed — on
a page the app was drawing the entire time. An unbounded page-side veto is a
permanent stall, which is the worst failure this feature can have.

Two changes, cause and symptom:

- **Cause.** `BrowserController.awaitPaintedSurface` is awaited after the
  automation owner is claimed and before the first navigation, by both the save
  run and the update checker. The document is then never born in an
  uncomposited view. Its timeout is not a correctness boundary: returning false
  simply means the ordinary guard takes over, which is what should happen when
  the user really is elsewhere.
- **Symptom.** `surfaceHoldReason` bounds the page-side veto with
  `kPageHiddenGrace`. The two app-side reasons — not drawing, no measurable
  layout — are still unbounded, because waiting is genuinely the only correct
  response to those.

The gate's `unpainted` arm still holds and still stores nothing, because there
the app-side signal is the one that fires.

### 7.3 The cleanup invariant, and what it deliberately does not cover

**Scrollary's own work stops completely at a terminal state.** Measured on a
physical iPhone across fresh / left-Browser / Reader-open / +45 s /
post-cancellation: `requestAnimationFrame` exactly 0 in every one,
`automationOwner` null in every one, no operation live, no indicator. The
wakelock and the owner are released in `finally` blocks that no path can skip.

**The retained third-party page is a separate question and is not fully
answered.** Its JavaScript context stays alive; its timers continue at a
throttled rate (~6–7/s against ~19–21/s painted). A page with a polling
interval, an ad refresh or an analytics beacon can therefore still make requests
while mounted and unpainted. No network capture was taken, so the volume is
**unmeasured**.

Four policies were considered against the evidence:

| Policy | Session | Memory | Page timers | Browser return | Verdict |
|---|---|---|---|---|---|
| **Leave it mounted** | kept | ~95 MB retained | throttled, not stopped | instant | **chosen** |
| Navigate to a blank page | kept (cookies) but scroll and in-page state lost | frees the page | stopped | needs a reload | rejected — breaks the property `browser_screen.dart` exists to provide |
| Suspend the WebView | kept | little freed | stopped | risk of a stale surface | rejected — no supported API in the pinned plugin |
| Dispose and recreate | **lost** | frees everything | stopped | full reload | rejected — costs the session for ~95 MB |

The retained cost is small and measured; the alternatives cost the session,
which is the thing the single-WebView design exists to protect. **If a network
capture later shows a retained page making meaningful requests while unpainted,
the blank-page policy becomes the right answer** and this table is where that
decision should be revisited.

### 7.1 Every write that can happen while the Browser is not visible

This is the exhaustive list the invariants above have to cover.

| Write | Path | Guarded by |
|---|---|---|
| Entry package (assets, `manifest.json`) | `SaveEngine` → `FileStore` | D1, D2, D4, D6 |
| Entry row (status, `content_path`, `byte_size`, `source_url`) | `SaveEngine` → `AppDatabase` | D1, D2, D4 |
| Collection creation and `next_source_url` | `SaveEngine`, `UpdateChecker` | D1, D3 |
| Discovered-Entry rows and last-check fields | `UpdateChecker._recordDiscovered` | D1, D3 |
| `save_runs` rows and pause reason | `SaveRunController._persistRun` | — (session bookkeeping; already exists) |
| Queue row state | `TaskQueueController`, one conditional `UPDATE` | 5.2 |
| Browsing history | `HistoryRepository`, manual navigation only | unchanged |

---

## 8. Platform behaviour

Separated on purpose. "Confirmed" means measured by
`integration_test/occlusion_gate_test.dart` on the stated target; "assumed"
means reasoned from plugin or framework source and not yet measured; "device
only" means it cannot be answered anywhere but on hardware.

The iOS column's simulator figures have since been **reproduced on a cabled
iPhone 17** (§3.1). The Android column is still emulator-only: no physical
Android device has been available, and every Android row below should be read
with that caveat.

| Behaviour | iOS | Android |
|---|---|---|
| Viewport while covered | **Confirmed** unchanged (874, simulator) | **Confirmed** unchanged (2162, emulator) |
| Viewport while unpainted | **Confirmed** unchanged — it does *not* go to zero | **Confirmed** unchanged |
| Scrolling while covered | **Confirmed** advances | **Confirmed** advances |
| Scrolling while unpainted | **Confirmed** still advances | **Confirmed** still advances |
| JavaScript while covered | **Confirmed** — bridge calls and page scripts run | **Confirmed** |
| `requestAnimationFrame` while covered | **Confirmed** at display rate (61/s) | **Confirmed** at display rate (61–65/s) |
| `requestAnimationFrame` while unpainted | **Confirmed stopped** (0/s) | **Confirmed throttled** (13/s) |
| `document.visibilityState` while covered | **Confirmed** `visible` | **Confirmed** `visible` |
| `document.visibilityState` while unpainted | **Confirmed** `hidden` | **Confirmed** `visible` — no discrimination |
| `IntersectionObserver` + lazy loading while covered | **Confirmed** — 6/6 lazy panels stored | **Confirmed** — 6/6 |
| Navigation while covered | **Confirmed** — a full run's next-Entry hop completed | **Confirmed** |
| Platform-view composition under an opaque Flutter layer | **Confirmed on hardware** — iPhone 17, iOS 26.5.2 (§3.1) | **Confirmed** on the emulator; **device only** on hardware |
| Route-barrier semantics blocking of a covered platform view | **Assumed** from `ModalBarrier`'s `BlockSemantics`; **device only** with VoiceOver — still unrun, and the reason the capability ships off | **Assumed**; **device only** with TalkBack — still unrun |
| Memory pressure and renderer termination during a long covered save | **Device only** — a soak scenario exists in `device_matrix_test.dart`; no renderer termination has been induced or observed | **Device only** |
| Orientation change while covered | **Device only** — the WebView is laid out by the Browser tab, so its rect follows the window either way | **Device only** |
| Cookies and storage | Shared process-wide; one controller owns them (**W4**) | Shared process-wide; `CookieManager` is global |
| Plugin specifics | `flutter_inappwebview` is pinned at `6.2.0-beta.3` deliberately. `useShouldOverrideUrlLoading: true` with **no** `shouldOverrideUrlLoading` callback silently prevents every `loadUrl` on iOS — found while building the gate harness, and the reason the harness mirrors the production callback set | Cleartext to the loopback fixture is blocked from API 28; a **debug-source-set** network security config re-permits it for `127.0.0.1` only |

---

## 9. Intervention model

The rule is unchanged and absolute: **the app stops; it never works around.**
Foreground multitasking changes only *how the stop reaches the user*, because
the user may not be looking at the Browser when it happens.

| Situation | Outcome |
|---|---|
| Sign-in required | Needs you |
| CAPTCHA | Needs you |
| Consent dialog | Needs you |
| Access restriction or paywall (structural signal) | Failed, with the existing `StopReason` |
| A gesture the page requires | Needs you |
| Next-Entry control is ambiguous or low-confidence | Needs you — never an automatic pick |
| Cross-host redirect with nobody to consent | Refused; the current site keeps running |
| Restricted host (capture policy) | Terminal `failed` with `StopReason.captureRestrictedForSite`, exactly as today |
| Scroll does not advance | Distinguish "not rendering" (Waiting) from "page finished" (the existing stability check) |
| Renderer terminated | Waiting → re-inspect the current Entry; never a completion |
| App left the foreground | Waiting; resumes on return |
| Website data cleared | Refused while an operation is live |

**"Needs you" is one action**: it opens the Browser on the exact page, through
the existing `ensureBrowserVisible(url:)` contract. It waits on the operation
indicator; it never yanks the user out of what they are doing.

---

## 10. Product boundary

### 10.0 The decision, in one line

> **Update checking is Free. Foreground multitasking — letting a supported
> operation keep working while the user goes somewhere else in the app — is
> Pro.**

This is the current product decision and it supersedes the earlier proposal in
MONETIZATION_STRATEGY.md §8.3, which named update checking as the headline Pro
feature. That proposal is **no longer an active requirement** and must not be
read as one.

**Separate the operation from the way it executes.** Everything below turns on
that split, and collapsing it is how a convenience becomes a hostage:

| | Free | Pro |
|---|---|---|
| **The operation itself** — start a Collection check, start a Library-wide check, discover new Entries and see them, save or capture an Entry, read offline, organise the library | ✅ **all of it**, on the ordinary supported flows | ✅ identical |
| **The way it executes** — the operation continuing through its Browser-dependent phases while the user reads another Entry or uses the Library | **holds** while the user is elsewhere, and resumes when they return | **continues** |

So a Free user can check a Collection, check the whole Library where that is
offered, see every newly discovered Entry, and save it. Nothing about *what* the
app will do for them is smaller. What Pro buys is **not having to watch it**.

**The Free path is not made worse to create Pro value.** A Free operation is not
cancelled, not truncated, not slowed, not limited in how many Entries it may
discover, and not denied any result. Leaving the Browser mid-phase offers
*Pause and leave*, which holds at the next safe point, keeps everything saved so
far and resumes on return (§10.6) — that is the behaviour that shipped before
this capability existed, and it stays. Any future rule that degrades the Free
flow in order to make Pro look better is a violation of this section, not an
implementation of it.

**This is foreground multitasking, not background execution.** Nothing continues
once Scrollary is not in front. §1.1 is unchanged: no OS background mode, no
scheduler, no persisted authorisation to resume later. Pro moves work from
"needs this screen" to "needs this app", and no further.

### 10.1 Always free, and never behind a payment

Safety and legibility are not features to sell:

- The operation indicator, its phase and its progress.
- Cancellation, from anywhere.
- Pause and failure states, in words that say what happened.
- The completion report.
- Recovery, retry and resume.
- Every access to already-downloaded content.
- Protection of reading progress and downloaded data.
- The whole visible-Browser path for saving and checking — which stays the
  correct path, not a degraded one.
- **Update checking itself**, at both granularities: a single Collection check
  and the Library-wide check that repeats it. Starting one, its discovery, its
  results and its report are core library function, not a power tool (§10.0).
- **Saving and capture** on the ordinary supported flows, single and bounded
  multi-entry, in every capture mode.

The behaviour that already ships — direct downloads and the commit continuing
while the user is elsewhere — stays free. It exists today; putting a price on it
later would be taking something away.

### 10.3 Free versus Pro — the behaviour matrix

The capability changes **one** thing: whether a Browser-dependent phase may
continue while another screen is in front. Everything else is identical, and
everything in the "both" column is unconditional.

Read this table as the detail of §10.0: every row about *what the app does* is
the same in both columns, and the single row that differs is about *where the
user has to be while it does it*.

| Behaviour | Free | With the capability |
|---|---|---|
| Start a check or a save | ✅ same | ✅ same |
| Check one Collection · check the whole Library · see discovered Entries | ✅ same | ✅ same |
| Which Entries a check may discover, and how many | ✅ same | ✅ same |
| Browser-dependent phases with the Browser on screen | ✅ | ✅ |
| Browser-dependent phases with the Reader/Library on screen | **holds** at `waitingForBrowser` | **continues** |
| Leaving the Browser mid-phase | confirmation first, then a hold | no confirmation — nothing is at risk |
| Download and commit phases while elsewhere | ✅ already true, and **stays free** | ✅ |
| Operation indicator, phase, progress | ✅ | ✅ |
| Stop, from anywhere | ✅ | ✅ |
| Completion report | ✅ | ✅ |
| Failure state, `StopReason`, retry, recovery | ✅ | ✅ |
| `Needs you` → opens the exact page | ✅ | ✅ |
| Access to everything already downloaded | ✅ | ✅ |
| Reading progress protection | ✅ | ✅ |
| Content correctness, guards, overwrite protection | ✅ identical | ✅ identical |

**Rules this matrix encodes.**

- The free path is the *correct* path, not a degraded one. Nothing about it was
  made slower, noisier or less capable to make the capability look better. The
  confirmation dialog it shows is the same one that shipped before this work.
- Behaviour that already worked — direct downloads and commit continuing while
  the user is elsewhere — **stays free**. Pricing it later would be taking
  something away.
- Losing the capability removes a future convenience. It never removes a saved
  Entry, a Collection, a reading position, or the ability to read any of them.
- The capability may be flipped at any moment. What it does **not** do is
  change the operation already running — see §10.5.

### 10.5 The task capability snapshot

**An operation keeps the surface it started with.** `TaskCapabilitySnapshot`
(`lib/capability/foreground_gate.dart`) latches the capability on the edge where
an operation acquires the Browser, and drops it the moment nothing owns it. The
shell's surface recompute reads the latched value, never the live one.

Why it exists: without it, turning the preference off — or an entitlement source
answering differently — while a save is mid-page stops the app compositing the
WebView underneath it, and the run stalls on a page it was in the middle of
reading. The user changed a setting; they did not ask to interrupt anything.

The latch holds in **both** directions, and that is deliberate:

| Change, mid-task | This task | The next task |
|---|---|---|
| Preference off | keeps multitasking | visible Browser |
| Preference on | keeps needing the Browser | multitasking |
| Force Pro → Force Free | keeps its surface; nothing is deleted or corrupted | Free |
| Force Free → Force Pro | unchanged | Pro |

So the honest sentence, and the one the leave sheet uses, is *"turning this on
now applies to the next check or save"*. `ForegroundMultitasking.enabled`
answers for the next task; `enabledForActiveTask` answers for the one running.

### 10.6 The gate, and the one surface that presents it

Every screen that starts Browser-dependent work, or lets the user walk away from
it, asks `lib/capability/foreground_gate.dart` — two pure functions over
entitlement, preference and phase, so the whole boundary is testable without a
WebView, a route or a widget. No screen reads the internal override;
`foreground_gate_test.dart` fails the build if one starts to.

**Queue start matrix** (`showStartOptionsSheet`, one sheet, three shapes):

| | Primary | Also offered |
|---|---|---|
| Free | **Start in Browser** — fully functional | **Start and keep using Scrollary · PRO**, locked and tappable |
| Pro, preference on | **Start and keep using Scrollary** | Start in Browser |
| Pro, preference off | **Start in Browser** | **Turn on Keep working while I read and start** |

Dismissing the sheet chooses nothing: every queued row stays exactly where it
was. The two paths share one save engine and one queue — only the navigation
differs. `StartChoice.inBrowser` calls `showBrowserSurface`; the multitasking
paths do not, and the shell keeps the WebView drawn under whatever the user is
looking at instead.

**Browser-leave matrix** (`showLeaveBrowserSheet`), decided by the *phase*
first:

| Phase | Free | Pro, task started with it | Pro, task started without it |
|---|---|---|---|
| Download, commit, paused, idle | leave, no question | leave, no question | leave, no question |
| Browser-dependent | Stay · Pause and leave · **What Pro does here** | leave, no question | Stay · Pause and leave · **Turn on for next time** |

There is deliberately no outcome that refuses navigation. *Pause and leave* is
always on the table, for everyone: it holds the run at its next safe point, keeps
everything saved so far, releases nothing destructively, and resumes when the
user returns to the Browser. Dismissing the sheet means **stay** — walking away
from a question about work in flight is never permission to strand it.

**Locked-action UX.** A locked control is *visible, tappable, and explains
itself*. A disabled widget cannot: a screen reader announces it as unavailable
and stops there. Every locked row carries a `PRO` badge, a semantics label that
begins with the action and contains *"Requires Pro"*, and a tap action that
opens the Pro sheet. `foreground_gate_ui_test.dart` holds all three.

**The Pro information sheet** says what the user was trying to do, that the
capability is Pro, that Scrollary must stay open in front, that this is not OS
background downloading, and that the Free visible-Browser flow is unchanged.
There is **no Buy button**: there is no billing in this build, and a button that
cannot charge anybody would be the one genuinely dishonest thing on the screen.
A line of text stands where the purchase entry point will go (`_upgradeSeat` in
`lib/features/foreground_gate_sheet.dart`) — that is the whole billing seam.

### 10.4 Entitlement, capability, preference — and the internal build

Three ideas that a single boolean would collapse, and must not:

```text
production source  +  internal override  ->  effective entitlement
                                                    |
                                          Pro capability available
                                                    |
                                   available AND "Keep working while I read"
                                                    |
                                      foreground multitasking active
```

| Concept | Where | Today |
|---|---|---|
| **Entitlement** | `productionEntitlement()` | Returns `free` — there is no billing, and `unknown` would imply loading while `pro` would give the product away |
| **Override** | `EntitlementOverride` | `production` · `forceFree` · `forcePro`. Internal builds only |
| **Capability** | `proCapabilityAvailable()` | Pure function of the effective entitlement |
| **Preference** | `ForegroundMultitasking.preference` | What the user asked for, persisted, and **kept across entitlement loss** |
| **Active** | `ForegroundMultitasking.enabled` | Capability **and** preference. The only thing the shell and engines read |

**Rules the tests enforce** (`test/entitlement_test.dart`):

- Forcing Pro makes the capability available but does **not** enable the
  behaviour — the user still has to ask for it.
- Losing Pro turns it off but **keeps the preference**, so restoring Pro
  restores the behaviour. Discarding it would silently reset a decision the
  user made.
- A production build ignores the override entirely, whatever is persisted —
  belt and braces, since the UI that writes it does not exist there.
- `unknown` is never treated as entitled.

**Internal builds.** `kInternalBuild` is `kDebugMode || bool.fromEnvironment('SCROLLARY_INTERNAL_BUILD')`
— a compile-time constant, so a Store build folds it to `false` and the
tree-shaker removes the screen, the route and the override. `kDebugMode` alone
was too narrow: profile and release builds are exactly where device
performance, energy and accessibility work happens, and that work needs these
tools.

```
flutter run --profile --dart-define=SCROLLARY_INTERNAL_BUILD=true -d <udid>
```

**Changing the override during live work.** The rule is *the next task picks it
up*. A run already in flight keeps the capability it started with, because
pulling the painted surface out from under a scrolling save is precisely the
corruption this feature exists to avoid. Nothing is cancelled, no ownership is
dropped, no commit is interrupted, and no downloaded content or reading
position is touched.

**When billing lands**, it replaces the body of `productionEntitlement()`. No
screen, engine or capability check changes — that is the entire reason the seam
is a function rather than a boolean somewhere convenient.

**One standing guard was narrowed, deliberately — and it is now the executable
form of §10.0.** `test/library_check_test.dart` scans every `.dart` file under
`lib/` for gating vocabulary — `is_pro`, `pro_required`, `trial_expired`,
`purchase_required`, `entitlement`, `upgrade_to_pro`, `in_app_purchase`,
`storekit`, `billingclient`, and two usage-counter names
(`library_check_runs_used`, `complimentary_checks_remaining`) — and fails the
build on a hit. Its failure message states the subject:

> *checking is unrestricted; no gating, counter or purchase state may sit
> dormant in the app waiting to be switched on*

`paywall` is deliberately **absent** from that list: in this app it names a
*site's* paywall, a stopping condition, which is the opposite of a paywall the
app puts in front of its own features.

The exemption is by path with a recorded reason for each — `lib/capability/`
itself, plus `settings_screen.dart`, `main.dart` and `developer_screen.dart`,
which only name the seam without deciding anything. Everywhere else the ban
holds, so a counter, a purchase record or a second gate cannot appear in a
screen, an engine or a repository.

**That guard is what makes "update checking is Free" enforceable rather than a
promise.** Gating checking would mean editing it on purpose, which is the point:
the decision in §10.0 is not something a later change can drift past quietly.
Do not weaken or exempt around it without recording why here first.

### 10.2 The capability seam

Foreground multitasking is expressed as one capability object,
`lib/capability/foreground_multitasking.dart`, with a single boolean and one
place that decides it. Nothing else in the app asks *why* it is on.

- Today it is an explicit, user-visible setting.
  `ForegroundMultitasking.defaultEnabled` is **`false`**, and stays false until
  the enablement criteria in the plan's §4a are met on a platform's own
  hardware — the compositing gate alone is not enough, and passing it on iOS
  (§3.1) did not change the default. Whether it should ever default on is a
  product decision, not a consequence of the gate.
- If it is ever sold, an entitlement supplies that boolean and nothing else
  moves. That is the whole seam.
- **The capability may only ever remove a convenience.** With it off, every
  operation still runs, still completes and still reports — the user just has to
  be looking at the Browser, which is the behaviour that ships today.
- No billing, no account, no backend, no network call is introduced by this
  work.

---

## 11. Validation strategy

| Layer | What it proves | Where |
|---|---|---|
| Unit | State transitions, the visibility guard's decision function, the empty/shrunken discovery rule, capability defaults | `test/` |
| Widget | The shell keeps the Browser onstage when it should and offstage when it should; pointer and semantics exclusion; route opacity follows the capability | `test/` |
| Fixture integration | A complete check and a complete save running through their Browser-dependent phases while another screen is on top, against the in-process fixture site | `integration_test/` |
| Architecture gate | Covered rendering, on real platforms | `integration_test/occlusion_gate_test.dart` |
| Device | Everything in §8 marked device-only, plus VoiceOver and TalkBack | manual, recorded in the plan |
| Performance | §12 | `integration_test/` + the plan's record |

Fixtures are developer-owned and live in `tool/fixture/`. No third-party site is
named, hard-coded, or treated as a target; live verification remains bounded and
against the developer-owned demo site only, per
[DEMO_CONTENT.md](./DEMO_CONTENT.md).

---

## 12. Performance acceptance criteria

Defined before the implementation, measured after, and recorded in the plan with
device, OS version, build mode, scenario, baseline, result and variance.

| Measure | Threshold |
|---|---|
| Reader frame build/raster time while an operation runs | No more than one frame in fifty over 16 ms, in profile mode, on the stated device |
| Save wall-clock for one fixture Entry, covered vs watched | Within 15% of the watched baseline |
| Check wall-clock for one fixture hop, covered vs watched | Within 15% of the watched baseline |
| Stored image count, covered vs watched | Identical. Not a threshold — an equality |
| Memory high-water during a three-Entry run | No more than 10% above the watched baseline |
| App startup | Unchanged: this feature adds nothing to the boot sequence |
| Renderer terminations during a bounded run | Zero on the stated devices; any occurrence is recorded, not averaged away |

Subjective observation is not evidence. An unmeasured criterion is reported as
unmeasured.

---

## 13. Accessibility requirements

Treated as release blockers.

- A covered WebView must not be reachable by VoiceOver or TalkBack: not
  focusable, not read, not in the swipe order.
- The Reader's semantics must be unchanged with an operation running.
- The Browser's semantics must return intact when it becomes interactive again.
- The operation indicator must be readable: how much work is outstanding, and
  whether it is moving, held or needs a person. It is a compact pill and says
  no more than that; the phase, the progress and the log are one tap away on
  the surface it opens.
- **Where it opens is the state's own answer.** A held operation opens the
  Browser, because that is where a "Needs you" is answered (§9) and the only
  live control a list could offer for one is a button that opens the Browser.
  Everything else opens Activity. The label names the destination either way,
  so the button never has to be pressed to find out.
- Cancel must be reachable and labelled — from the indicator, that means
  reachable *through* it: on Activity for a queued task and for a direct run
  alike, and on the Browser's own save and check panels for a held one. The
  pill is a status, not a control surface; one tap to the place that owns the
  controls is the trade, and it is the same trade the Library's activity strip
  has always made.
- The indicator must not mark a run with somebody else's failure. A `failed`
  row is kept as history, so the marker is scoped to failures that finished
  after the oldest still-outstanding row was queued — the batch you are
  watching, not the one you already saw.
- "Needs you" must be announced as an action, with what it will do.
- Focus must not jump when operation state changes.
- No composition workaround may disable accessibility to achieve occlusion.

---

## 14. Open questions

| # | Question | State | Resolved by |
|---|---|---|---|
| U1 | Covered rendering on physical iOS hardware | **Closed.** Passed on a cabled iPhone 17, iOS 26.5.2 — covered identical to painted, and the unpainted control correctly held and stored nothing | §3.1; plan D-1, §6.1 |
| U2 | Covered rendering on Android | **Closed on the emulator**, ×3, identical to the painted arm. **Open on hardware:** no physical Android device has been available | A physical Android device (D-2) |
| U3 | Whether semantics exclusion suppresses a platform view's native accessibility elements on iOS | **Open** | VoiceOver, on hardware (D-3) |
| U4 | Renderer-termination rate under a long covered image save | **Open.** A soak scenario exists in `device_matrix_test.dart`; no termination has been induced or observed, so the rate is unmeasured rather than known to be zero | A soak and an induced kill on hardware (D-5) |
| U5 | Thermal and battery cost of a full bounded covered run with the screen on | **Open.** Needs a profile build; only debug runs have been done | A bounded device run (D-5) |
| U6 | Whether the Collection-check case is genuinely process-isolation-sensitive or hiding a fault | **Open.** It passes alone and failed once when run third in the same test process; not reproduced since | Re-running the integration file; if it recurs, instrument `surfaceIsPainted` across the whole run |
| U7 | Whether the Reader's eager document build makes a covered save unsafe on a memory-constrained device | **Open.** A real 76-image document entry held ≈1.4 GB with its Reader open (plan §6.1c). Not a fault of this feature, but concurrent Reader and WebContent execution is exactly what makes it matter | A lazy-image document reader, then a device re-measure |

The capability ships **off**, and the reasons have narrowed rather than gone
away. U1 is closed, so the compositing premise is no longer the blocker. What
remains: **U3** — accessibility is a release blocker by §13 and has not been
tested on any device; **U2 on hardware** — no physical Android device has run
any of this; and **U7**, which is a Reader problem this feature does not own but
would be the first to expose. With the capability off the app behaves exactly as
it did before this work, so none of those is on the path any save takes today.
