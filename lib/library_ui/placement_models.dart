/// Placing an unplaced Entry: the request, the answer, and the words for both
/// (roadmap D6).
///
/// An unplaced Entry is a **real, visible state**, not an error and not a
/// number waiting to be guessed (V2-D16). Everything in this file follows from
/// that:
///
/// * The position comes from the user. Nothing derives one, and nothing
///   *adjusts* one — a taken position is refused and named, never quietly
///   shifted to the next free number. An automatic +1 would put an Entry
///   somewhere no source ever said it was, which is the exact failure the
///   unplaced state exists to avoid.
/// * A refusal is visible. Both refusals — the one this device already knows
///   about, and the one that comes back from elsewhere — print the Entry that
///   holds the position.
///
/// [PlacementSubmit] is the seam. Where a placement travels, and what else it
/// touches on the way, belongs to the lane that owns the transport; this lane
/// consumes the interface and applies what comes back.
library;

/// One request: put [entryId] at [ordinal] in [collectionId].
class PlacementRequest {
  const PlacementRequest({
    required this.entryId,
    required this.collectionId,
    required this.ordinal,
  });

  final String entryId;
  final String collectionId;

  /// A position in a sequence. Real, because sources number half-positions and
  /// a placement that could not express one would push the user into
  /// renumbering somebody else's sequence.
  final double ordinal;
}

enum PlacementStatus {
  /// The placement stands. [PlacementOutcome.ordinal] is what was applied —
  /// read it rather than the requested value, so this device records what
  /// actually happened.
  applied,

  /// The position is held by another Entry. Never auto-adjusted.
  conflict,

  /// Refused for a stated reason.
  refused,
}

/// What came back. Three answers, and "it worked but somewhere else" is not
/// one of them.
class PlacementOutcome {
  const PlacementOutcome._({
    required this.status,
    this.ordinal,
    this.occupyingEntryId,
    this.occupyingTitle,
    this.reason,
  });

  /// Applied, at [ordinal] — which the caller writes locally, rather than
  /// assuming the number it asked for.
  const PlacementOutcome.applied(double ordinal)
    : this._(status: PlacementStatus.applied, ordinal: ordinal);

  /// Taken. [occupyingEntryId] names the Entry holding it where that is known,
  /// and [occupyingTitle] is what the far side calls it — used only when this
  /// device cannot name the Entry itself.
  const PlacementOutcome.conflict({
    required double ordinal,
    String? occupyingEntryId,
    String? occupyingTitle,
  }) : this._(
         status: PlacementStatus.conflict,
         ordinal: ordinal,
         occupyingEntryId: occupyingEntryId,
         occupyingTitle: occupyingTitle,
       );

  const PlacementOutcome.refused(String reason)
    : this._(status: PlacementStatus.refused, reason: reason);

  final PlacementStatus status;
  final double? ordinal;
  final String? occupyingEntryId;
  final String? occupyingTitle;
  final String? reason;

  bool get isApplied => status == PlacementStatus.applied;
  bool get isConflict => status == PlacementStatus.conflict;
}

/// How a placement leaves this device.
///
/// Injected, and deliberately unimplemented until something is attached: this
/// lane draws the dialog and applies the answer, and inventing a local-only
/// success while the transport is absent would be a placement the rest of the
/// library never hears about.
typedef PlacementSubmit =
    Future<PlacementOutcome> Function(PlacementRequest request);

/// `3`, `3.5`, `12` — never `3.0`.
///
/// A trailing `.0` reads as precision the sequence does not have, and the same
/// number must print identically in the field, the refusal and the confirmation.
String formatOrdinal(double ordinal) {
  if (ordinal == ordinal.roundToDouble() && ordinal.abs() < 1e15) {
    return ordinal.toStringAsFixed(0);
  }
  return ordinal.toString();
}

/// What the user typed, or null when it is not a number yet.
///
/// Null is an ordinary state — a half-typed field — and never an error
/// message: the action is simply not available until there is a number.
double? parseOrdinal(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || !value.isFinite) return null;
  return value;
}

/// The one sentence a taken position gets, wherever the refusal came from.
///
/// It names the position and the Entry holding it, and it proposes nothing:
/// choosing a different number is the user's decision, and the app has no
/// standing to make it for them.
String placementConflictSentence({
  required double ordinal,
  String? occupantLabel,
}) {
  final where = 'Position ${formatOrdinal(ordinal)} in this collection';
  return occupantLabel == null || occupantLabel.trim().isEmpty
      ? '$where is already taken. Nothing was changed.'
      : '$where is already taken by “${occupantLabel.trim()}”. Nothing was '
            'changed.';
}
