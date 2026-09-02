/// The version the app shows is the version the build carries.
///
/// Two files hold it — `pubspec.yaml`, which the build system reads, and
/// `lib/core/version.dart`, which the app prints — and there is no mechanism
/// keeping them equal except this test and the script that writes both
/// (`tool/release.sh`). A build that tells the user 1.0.3 while the store row
/// says 1.0.7 is a bug report nobody can act on, so the pairing is pinned here
/// rather than trusted.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/version.dart';

void main() {
  test('pubspec.yaml and lib/core/version.dart agree', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere(
      (l) => l.startsWith('version: '),
      orElse: () => fail('pubspec.yaml has no version line'),
    );

    expect(
      line,
      'version: $kAppVersion+$kAppBuild',
      reason:
          'move both with `bash tool/release.sh`, which is the only thing '
          'that writes either of them',
    );
  });

  test('the version is a three-part number and the build is positive', () {
    expect(
      RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kAppVersion),
      isTrue,
      reason: 'both stores read the marketing version as major.minor.patch',
    );
    // A build number that goes down, or starts again at 1 for a new version,
    // is an upload both stores refuse.
    expect(kAppBuild, greaterThan(0));
  });

  test('the label is what a bug report would quote', () {
    expect(appVersionLabel, '$kAppVersion ($kAppBuild)');
  });
}
