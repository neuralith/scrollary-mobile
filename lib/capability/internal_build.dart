import 'package:flutter/foundation.dart';

/// Whether this build may show internal developer tooling.
///
/// `kDebugMode` alone is not enough: profile and release builds are exactly
/// where device performance, energy and accessibility work happens, and that
/// work needs the entitlement override and the reset tools. So an internal
/// build is *either* a debug build *or* one launched with the define:
///
/// ```
/// flutter run --profile --dart-define=SCROLLARY_INTERNAL_BUILD=true
/// ```
///
/// A normal Store build passes neither, and `const bool.fromEnvironment`
/// resolves to a compile-time `false` — so the tree-shaker removes the screens,
/// the routes and the override entirely. There is no runtime string to typo
/// into production and no setting that could be flipped on a real device.
const bool kInternalBuild =
    kDebugMode || bool.fromEnvironment('SCROLLARY_INTERNAL_BUILD');
