# Scrollary

A personal reading library for web-based reading content, on iOS and Android.
Track what you are reading and where it came from, organise it into Collections
and Entries, and — where you are legally permitted to keep a copy — download
Entries to read offline.

**An Entry is in the library because you want to read or track it, not because
its content has been downloaded.** Downloading is a per-device capability of an
Entry, and removing a download never removes the Entry.

Built with Flutter: an embedded `WKWebView`/`WebView`, a local drift database,
and an offline reader over app-private storage. Local-first: every action
completes on the device in front of you, and the app is fully usable offline.
No analytics, no advertising, and nothing about what you read is sent to the
developer.

The app is **V2**: a recognition-driven library where reading updates your
library automatically, Collections have several Sources, Folders organise
everything, and library metadata can synchronise across your devices as a Pro
capability. It needs no account and is fully usable offline.

## Documentation

**The documentation set lives in the workspace above this repository**, at
[`../docs/`](../docs/README.md), because most of it describes the app and the
sync service together. Start with [../docs/README.md](../docs/README.md), which
lists every document and the order to trust them in. The short version:
[PRODUCT.md](../docs/PRODUCT.md) for what the product is,
[TERMINOLOGY.md](../docs/TERMINOLOGY.md) for the nouns,
[V2_ARCHITECTURE.md](../docs/V2_ARCHITECTURE.md) for the domain,
[CURRENT_STATE.md](../docs/CURRENT_STATE.md) for what is built and what is left,
and [DECISIONS.md](../docs/DECISIONS.md) for why. Contributor rules are in
[CLAUDE.md](CLAUDE.md).

## Repository layout

| Path | What it is |
|---|---|
| `lib/`, `test/`, `integration_test/` | The Flutter app as built today |
| `contracts/` | The shared API contract — the canonical copy, frozen |
| `../scrollary-backend/` | The V2 synchronisation service — Go, Fiber v3, PostgreSQL. See [its README](../scrollary-backend/README.md) |
| `../docs/` | Product, domain, sync, store and privacy — for both halves |

## Running

```bash
flutter pub get
dart run build_runner build     # after changing lib/data/schema.dart
flutter run
```

## Verifying

```bash
dart format lib test integration_test tool
flutter analyze
flutter test
```

## Internal builds

Developer tooling — the destructive local reset and the entitlement override
that unlocks the Pro path — is gated by `kInternalBuild`, which is
`kDebugMode || bool.fromEnvironment('SCROLLARY_INTERNAL_BUILD')`. Debug builds
already have it. To get it in a profile or release build, which is where device
performance, energy and accessibility work has to happen:

```bash
flutter run --profile --dart-define=SCROLLARY_INTERNAL_BUILD=true -d <udid>
flutter run --release --dart-define=SCROLLARY_INTERNAL_BUILD=true -d <udid>
```

**A build for the stores passes neither flag.** The constant is compile-time, so
without the define it folds to `false` and the tree-shaker removes the screen,
its route and the override. See [../docs/FOREGROUND_MULTITASKING.md](../docs/FOREGROUND_MULTITASKING.md) §10.

## What it is not

Not a bulk fetcher, an automated harvester, a site archiver, a client for
particular websites, or a tool for getting past paywalls, logins, access
controls, DRM, verification checks or rate limits. It ships no site list and no
site-specific behaviour, and a build-time test enforces that.
