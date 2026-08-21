import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';

/// The seam future billing will plug into.
///
/// Three ideas that are easy to collapse into one boolean and must not be:
/// **entitlement** (what the user bought), **capability** (what that makes
/// available), and **preference** (what they asked for). Collapsing them is how
/// a setting ends up lying about what it will do.
void main() {
  group('resolving an entitlement', () {
    test('production passes the real source straight through', () {
      for (final source in Entitlement.values) {
        expect(
          resolveEntitlement(
            production: source,
            override: EntitlementOverride.production,
            internalBuild: true,
          ),
          source,
        );
      }
    });

    test('an internal build can force either side', () {
      expect(
        resolveEntitlement(
          production: Entitlement.free,
          override: EntitlementOverride.forcePro,
          internalBuild: true,
        ),
        Entitlement.pro,
      );
      expect(
        resolveEntitlement(
          production: Entitlement.pro,
          override: EntitlementOverride.forceFree,
          internalBuild: true,
        ),
        Entitlement.free,
      );
    });

    test('a production build ignores the override entirely', () {
      // Belt and braces. The UI that writes the override does not exist in a
      // production build, but a value left in the settings table by an earlier
      // internal build must not be able to grant anything.
      for (final override in EntitlementOverride.values) {
        expect(
          resolveEntitlement(
            production: Entitlement.free,
            override: override,
            internalBuild: false,
          ),
          Entitlement.free,
          reason: '$override must not survive into production',
        );
      }
    });

    test('an unreadable stored override is production, not a grant', () {
      expect(EntitlementOverride.parse(null), EntitlementOverride.production);
      expect(
        EntitlementOverride.parse('forcePro!!'),
        EntitlementOverride.production,
      );
      expect(
        EntitlementOverride.parse('forcePro'),
        EntitlementOverride.forcePro,
      );
    });

    test('todays production source is Free, honestly', () {
      // No billing exists yet. `unknown` would imply something is loading and
      // `pro` would give the product away.
      expect(productionEntitlement(), Entitlement.free);
    });

    test('unknown is never treated as entitled', () {
      expect(proCapabilityAvailable(Entitlement.unknown), isFalse);
      expect(proCapabilityAvailable(Entitlement.free), isFalse);
      expect(proCapabilityAvailable(Entitlement.pro), isTrue);
    });
  });

  group('capability and preference are both required', () {
    test('Pro alone does not switch anything on', () {
      expect(
        foregroundMultitaskingActive(
          effective: Entitlement.pro,
          preferenceEnabled: false,
        ),
        isFalse,
        reason: 'granting Pro must not enable a behaviour nobody asked for',
      );
    });

    test('a preference alone does not grant anything', () {
      for (final e in [Entitlement.free, Entitlement.unknown]) {
        expect(
          foregroundMultitaskingActive(effective: e, preferenceEnabled: true),
          isFalse,
        );
      }
    });

    test('both together is the only true case', () {
      expect(
        foregroundMultitaskingActive(
          effective: Entitlement.pro,
          preferenceEnabled: true,
        ),
        isTrue,
      );
    });
  });

  group('the capability object', () {
    test('defaults to production, Free, and off', () {
      final c = ForegroundMultitasking();
      expect(c.override, EntitlementOverride.production);
      expect(c.effectiveEntitlement, Entitlement.free);
      expect(c.proAvailable, isFalse);
      expect(c.enabled, isFalse);
    });

    test('forcing Pro makes it available but does not enable it', () {
      final c = ForegroundMultitasking()
        ..override = EntitlementOverride.forcePro;
      expect(c.proAvailable, isTrue);
      expect(c.enabled, isFalse, reason: 'the user still has to ask for it');
      c.preference = true;
      expect(c.enabled, isTrue);
    });

    test('losing Pro turns it off but keeps what the user asked for', () {
      final c = ForegroundMultitasking()
        ..override = EntitlementOverride.forcePro
        ..preference = true;
      expect(c.enabled, isTrue);

      c.override = EntitlementOverride.forceFree;
      expect(c.enabled, isFalse, reason: 'effective capability is gone');
      expect(
        c.preference,
        isTrue,
        reason:
            'their choice survives — discarding it would silently reset a '
            'decision they made, and restoring Pro must restore the behaviour',
      );

      c.override = EntitlementOverride.forcePro;
      expect(c.enabled, isTrue, reason: 'and it comes back');
    });

    test('every real change notifies exactly once', () {
      var n = 0;
      final c = ForegroundMultitasking()..addListener(() => n++);
      c.override = EntitlementOverride.forcePro;
      c.override = EntitlementOverride.forcePro;
      c.preference = true;
      c.preference = true;
      expect(n, 2);
    });

    test('the persisted preference round-trips', () {
      final c = ForegroundMultitasking()..preference = true;
      expect(c.storedValue, 'true');
      expect(ForegroundMultitasking.parse(c.storedValue), isTrue);
    });
  });

  group('what entitlement must never reach', () {
    /// Reading, finishing an entry and removing its downloads are things the
    /// app does for everyone. The cheapest way to keep it that way is to keep
    /// the capability layer out of the files that do them: a screen that cannot
    /// see an entitlement cannot condition anything on one, and this fails the
    /// moment an import appears rather than the moment a user notices.
    const readingSurfaces = [
      'lib/features/reader_screen.dart',
      'lib/features/cleanup_dialogs.dart',
      'lib/storage/cleanup.dart',
      'lib/reading/reading_repository.dart',
      'lib/reading/reading_position.dart',
    ];

    for (final path in readingSurfaces) {
      test('$path does not import the capability layer', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('capability/'),
          isFalse,
          reason:
              'reading and finished-entry cleanup are not Pro features, so '
              'this file has no business seeing an entitlement',
        );
      });
    }
  });
}
