/// Measurement — progress scoped to the rendering it was taken against.
library;

import 'invariants.dart';

/// Keyed by `(entry, source)`. A fraction measured against one Source's
/// rendering is not an approximation of another's — it is a fact about a
/// different thing. Scope replaces any notion of progress "confidence", and
/// the app never invents a number for a Source it has not measured (V2-D18).
///
/// The reading ANCHOR is deliberately absent: an index and offset inside a
/// specific artifact is meaningless without the bytes it indexes, so it lives
/// on the device's OfflineCopy and never leaves it.
class Measurement {
  const Measurement({
    required this.entryId,
    required this.sourceId,
    required this.fraction,
    required this.observedAt,
  });

  final String entryId;
  final String sourceId;
  final double fraction;
  final DateTime observedAt;

  /// I12: a Measurement must name the Source it was measured against, and a
  /// fraction is a fraction.
  InvariantViolation? validate() {
    if (sourceId.isEmpty) return measurementNeedsScope;
    if (fraction < 0 || fraction > 1) return measurementNeedsScope;
    return null;
  }
}
