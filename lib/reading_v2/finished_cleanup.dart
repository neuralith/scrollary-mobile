/// What happens to a finished Entry's downloaded copy when you read on.
///
/// **Why this file exists.** Reading a serialized work through to the end fills
/// a device with Entries nobody will open again. V1 answered that with a rule
/// the user set **once per Collection** — remove the copy after continuing, or
/// keep it — and the rule went with the reader's V1 route when that route was
/// removed (`b1be16d`); nothing replaced it, and the only way left to free
/// those bytes is to remember to go to Storage and sweep. This is the rule,
/// back, over V2's own model.
///
/// **A rule about bytes, not about the library.** Applying it removes the
/// **OfflineCopy** and nothing else: the Entry stays in the library on every
/// device, with its Collection, its Locations, its reading history and its
/// read mark, and it can be opened at its Source or downloaded again. Those
/// are four independent facts (PRODUCT.md §2.3) and this touches exactly one
/// of them.
///
/// **Device-local, in the settings table.** V1 stored it as a column on the
/// Collection, which made a decision about *these* bytes into synced library
/// state — a phone that chose to remove would have been deciding for a tablet
/// that had room. What is being configured is this device's storage, so the
/// preference lives where this device's other per-Collection answers live:
/// `LocalSettingsStore`, keyed by Collection id. The schema is frozen at
/// version 1 with no migration path (CLAUDE.md, "The database has no
/// history"), and this needs no column.
///
/// Modelled on `CapturePreferenceStore` deliberately, down to the tri-state:
/// **null is a question, not a default.** There is no app-wide answer, no
/// answer inherited from another Collection, and no silent fallback — an
/// unset Collection is asked, once, the first time the question has a
/// consequence.
library;

import '../data/local_settings.dart';

/// What a Collection does with a finished Entry's downloaded copy.
///
/// Two values and no third: *not answered yet* is the absence of one, which is
/// what makes "ask again next time" expressible.
enum FinishedCleanupRule {
  /// Free the bytes once the reader has moved on to the next Entry.
  remove,

  /// Leave them on this device until the user removes them.
  keep,
}

FinishedCleanupRule? finishedCleanupRuleFromName(String? name) {
  for (final rule in FinishedCleanupRule.values) {
    if (rule.name == name) return rule;
  }
  // An unreadable stored value means "ask", never "remove": a preference this
  // build cannot interpret must not be resolved into the destructive answer.
  return null;
}

/// The settings key a Collection's rule lives under.
///
/// Namespaced by the Collection's own id, so there is one row per Collection
/// and forgetting one cannot touch another. Exposed for the test that pins the
/// spelling: a key that changes silently is a preference that silently
/// vanishes, and this one silently vanishing means files quietly stop being
/// freed.
String finishedCleanupKeyFor(String collectionId) =>
    'finished_cleanup.$collectionId';

/// Reads and writes what a Collection does with a finished Entry's copy.
class FinishedCleanupPreferenceStore {
  const FinishedCleanupPreferenceStore(this._settings);

  final LocalSettingsStore _settings;

  /// This Collection's rule, or null when the user has never said.
  Future<FinishedCleanupRule?> of(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return null;
    return finishedCleanupRuleFromName(
      await _settings.get(finishedCleanupKeyFor(collectionId)),
    );
  }

  /// Remember [rule] for this Collection.
  ///
  /// Only ever called for an answer the **user** gave. Nothing infers one from
  /// how full the device is, from what another Collection was told, or from
  /// what the user did last time.
  Future<void> remember(String? collectionId, FinishedCleanupRule rule) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _settings.set(finishedCleanupKeyFor(collectionId), rule.name);
  }

  /// Go back to asking. Removes nothing and restores nothing — it is a rule
  /// about what happens next, and clearing it changes only that.
  Future<void> forget(String collectionId) =>
      _settings.remove(finishedCleanupKeyFor(collectionId));
}
