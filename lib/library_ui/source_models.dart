/// View models and wording for a Collection's Sources (roadmap D4).
///
/// A Source is this Collection **on one site**, and it carries its whole life
/// in one row: `active · dormant · dead · resolvedInto` (V2-D14). Two product
/// rules are carried here rather than in a widget:
///
/// 1. **A dead Source is stated dead, never hidden.** A Collection outlives the
///    site that published it, and the row that says where it used to be is part
///    of the honest answer. Nothing in this file can filter a lifecycle out.
/// 2. **Nothing here promises to check or fetch anything.** Source traversal
///    and update checking are content-affecting automation that stays explicit
///    and user-started, and that flow arrives in its own lane. Wording that
///    implied Scrollary was already watching a site would be a sentence the app
///    cannot honour today.
///
/// Preference is a single pointer on the Collection (V2-D14), so *preferred* is
/// a property of the Collection read against a Source, never a flag on the
/// Source itself.
library;

import '../data/data_violations.dart';
import '../data/schema.dart';
import '../domain/invariants.dart';
import '../domain/source.dart';

/// What the Sources section says about itself.
const kSourcesSectionNote =
    'Where this collection is published. A site that has gone is still '
    'listed — the collection outlives it.';

/// One Source as a row: which site, in which language, and what state that
/// site is in.
class SourceView {
  const SourceView({
    required this.row,
    required this.preferred,
    this.resolvedInto,
  });

  final SourceRow row;

  /// This is the Collection's preferred Source. Read from the Collection's
  /// pointer, which is the one place the answer lives.
  final bool preferred;

  /// The Source this one moved to, when the library still lists it. Null is a
  /// real answer for a `resolvedInto` row — the pointer can outlive its target
  /// — and is said as such rather than drawn as though the move never happened.
  final SourceRow? resolvedInto;

  String get id => row.id;
  String get host => row.host;

  /// The language tag exactly as it was recorded. Never expanded into a
  /// language name: a tag is evidence, and a table of names is data this app
  /// has no reason to carry.
  String get languageTag => row.language.trim();

  SourceLifecycle get lifecycle => SourceLifecycle.values.byName(row.lifecycle);

  /// Whether this Source may currently be read from. Only these are offered
  /// the preference switch — a control that does not apply is absent, not
  /// disabled.
  bool get readable =>
      lifecycle == SourceLifecycle.active ||
      lifecycle == SourceLifecycle.dormant;

  String get lifecycleLabel => switch (lifecycle) {
    SourceLifecycle.active => 'Active',
    SourceLifecycle.dormant => 'Dormant',
    SourceLifecycle.dead => 'Dead',
    SourceLifecycle.resolvedInto => 'Moved',
  };

  /// One sentence about this site's state. Every one of them describes what is
  /// known, and none of them describes what Scrollary is going to do next.
  String get lifecycleSentence => switch (lifecycle) {
    SourceLifecycle.active => 'This site carries this collection.',
    SourceLifecycle.dormant =>
      'Still readable. Nothing new has been seen here for a while.',
    SourceLifecycle.dead =>
      'This site no longer carries this collection. It stays listed so the '
          'collection can say where it used to be.',
    SourceLifecycle.resolvedInto =>
      resolvedInto == null
          ? 'This site moved. Where it moved to is not listed here.'
          : 'This site moved to ${resolvedInto!.host}.',
  };
}

/// A refused preference, in a sentence.
///
/// Both cases are the same event from the user's side — the Source stopped
/// being this Collection's while the sheet was open — and neither is silently
/// swallowed: a preference the app did not write must not be drawn as one it
/// did.
String sourcePreferenceMessage(InvariantViolation violation) {
  if (violation == preferredSourceForeign) {
    return 'That site is no longer one of this collection’s sources.';
  }
  if (violation == unknownRow) {
    return 'That collection is no longer in your library.';
  }
  return violation.message;
}
