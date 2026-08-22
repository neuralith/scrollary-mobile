import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The build guard behind the Free/Pro boundary.
///
/// The V1 library-check logic this file also covered retired with
/// `lib/library/library_check.dart` (roadmap §10, after F3 + F4); the V2
/// check's behaviour is pinned in `test/recognition/check_test.dart` and
/// `test/recognition/discovery_test.dart`. The guard below is not V1: it
/// scans `lib/` and fails the build if gating, counter or purchase state
/// appears outside the capability seam. It stays here, unchanged.
void main() {
  test('no entitlement, usage-counter or purchase state exists in lib/', () {
    // Note: `paywall` is deliberately absent. In this app it names a *site's*
    // paywall — a stopping condition — which is the opposite of a paywall the
    // app puts in front of its own features.
    //
    // **`lib/capability/` is exempt, and only it.** This guard was written when
    // nothing in the product was paid, and its real subject is stated in its
    // own failure message: *checking is unrestricted*. That is still true —
    // Library checks, saves, recovery, retry and every byte already on disk are
    // ungated and cannot be gated, because the capability seam reaches exactly
    // one behaviour: whether an operation may continue while another screen is
    // in front. What the guard forbids everywhere else is unchanged, so a
    // counter, a purchase record or a second gate cannot appear in a screen, an
    // engine or a repository. See docs/FOREGROUND_MULTITASKING.md §10.
    // Keyed by path, each with the reason it is not gating state.
    const exempt = <String, String>{
      // The seam itself: three pure functions and one value object.
      'lib/capability/': 'the capability seam — no counter, no purchase record',
      // These two only *name* it: an import and a type. Neither decides
      // anything; both defer to the seam above.
      'lib/features/settings_screen.dart': 'imports the developer control',
      'lib/main.dart': 'reads the persisted override at startup',
      'lib/features/developer_screen.dart':
          'hosts the internal-build-only control; compiled out of release',
    };
    const forbidden = <String>[
      'library_check_runs_used',
      'complimentary_checks_remaining',
      'is_pro',
      'ispro',
      'pro_required',
      'prorequired',
      'trial_expired',
      'trialexpired',
      'purchase_required',
      'entitlement',
      'upgrade_to_pro',
      'upgradetopro',
      'in_app_purchase',
      'storekit',
      'billingclient',
    ];
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (exempt.keys.any(file.path.contains)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final lower = lines[i].toLowerCase();
        for (final word in forbidden) {
          if (lower.contains(word)) {
            offenders.add('${file.path}:${i + 1} $word');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'checking is unrestricted; no gating, counter or purchase state may '
          'sit dormant in the app waiting to be switched on',
    );
  });
}
