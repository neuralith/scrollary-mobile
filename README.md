# Scrollary

A general-purpose personal reading tool for iOS and Android. Save web pages you
are legally permitted to keep, organise them in a personal library, and read them
offline.

Built with Flutter: an embedded `WKWebView`/`WebView`, a local drift database, and
an offline reader over app-private storage. No account, no server, no analytics.

## Documentation

Start with [docs/TERMINOLOGY.md](docs/TERMINOLOGY.md), then
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Store readiness is covered by
[docs/STORE_POLICY_MAP.md](docs/STORE_POLICY_MAP.md) and
[docs/STORE_PACKAGE.md](docs/STORE_PACKAGE.md). Contributor rules are in
[CLAUDE.md](CLAUDE.md).

## Running

```bash
flutter pub get
dart run build_runner build     # after changing lib/storage/database.dart
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
its route and the override. See [docs/FOREGROUND_MULTITASKING.md](docs/FOREGROUND_MULTITASKING.md) §10.4.

## What it is not

Not a bulk fetcher, an automated harvester, a site archiver, a client for
particular websites, or a tool for getting past paywalls, logins, access
controls, DRM, verification checks or rate limits. It ships no site list and no
site-specific behaviour, and a build-time test enforces that.
