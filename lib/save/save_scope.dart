/// How much to download, decided once and answered in rows.
///
/// **Why this file exists.** V1 asked the user how many entries to save and
/// bounded the run by their answer. V2 kept the bound — [SaveScope] and
/// [SaveLimits] in `core/config.dart` are untouched and are still the only way
/// to build a limit — but lost the question: the V2 save sheet offers one
/// button, for one page. This file is the missing half, expressed in the V2
/// domain: a scope plus a starting Entry becomes *a list of (Entry, Location)
/// pairs to queue*, and nothing else.
///
/// Three properties it keeps from V1, because they were the safety story:
///
/// * **There is no open-ended scope.** The plan is built from
///   [SaveLimits.maxEntries], which is always a positive clamped number.
/// * **A plan is what the library already holds.** Planning opens no page,
///   drives no browser and fetches nothing. Finding *more* entries to plan
///   over is a separate, visible, cancellable act — the update check — and the
///   caller runs it first if it wants to.
/// * **A short plan is stated, never padded.** If the user asked for ten and
///   the library knows four, the plan holds four and says so. Nothing invents
///   an address it has not seen.
library;

import '../core/config.dart';

/// One queued download, resolved to the row it will run against.
class PlannedSave {
  const PlannedSave({
    required this.entryId,
    required this.locationId,
    required this.url,
    required this.ordinal,
    required this.title,
  });

  final String entryId;
  final String locationId;
  final String url;

  /// The Entry's position, when it has one. Null for an unplaced Entry, which
  /// can still be downloaded — position is organisation, not permission.
  final double? ordinal;
  final String title;
}

/// What a scope came to, against the library as it stands.
class SaveScopePlan {
  const SaveScopePlan({
    required this.saves,
    required this.requested,
    this.startIsUnplaced = false,
  });

  const SaveScopePlan.empty()
    : saves = const [],
      requested = 0,
      startIsUnplaced = false;

  /// In reading order, starting at the Entry the user was on.
  final List<PlannedSave> saves;

  /// What the user asked for, before the library was consulted.
  final int requested;

  /// True when the starting Entry has no position, so "the ones after it" is
  /// not a question the library can answer. The plan is then that Entry alone.
  final bool startIsUnplaced;

  int get planned => saves.length;

  /// How many of the requested downloads the library cannot name an address
  /// for. Reported to the user; never quietly dropped.
  int get shortfall => requested - planned < 0 ? 0 : requested - planned;

  bool get isEmpty => saves.isEmpty;
}

/// Turns a scope into rows. Reads; never writes, never navigates.
abstract class SaveScopePlanner {
  /// The Entries to download, starting at [startEntryId].
  ///
  /// When the start Entry is placed in a Collection, the plan walks that
  /// Collection's own order upward from it — the same order the library shows
  /// — taking each Entry that has an address to download from, preferring
  /// [preferSourceId] when the Entry has an address on it and falling back to
  /// the Entry's earliest active Location otherwise. It stops at
  /// [limits] `.maxEntries`, at the end of what the library holds, or at an
  /// Entry with no active address, whichever comes first.
  ///
  /// When the start Entry is standalone or unplaced, the plan is that Entry
  /// alone and [SaveScopePlan.startIsUnplaced] says why.
  Future<SaveScopePlan> plan({
    required String startEntryId,
    required SaveLimits limits,
    String? preferSourceId,
  });
}
