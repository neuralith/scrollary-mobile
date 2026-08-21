/// DownloadRequest — "download this Entry on mobile", expressed as an intent.
library;

import 'invariants.dart';

/// The lifecycle of an intent, never of content.
enum DownloadRequestState {
  pending,
  claimed,
  completed,
  failed,
  cancelled;

  /// Whether no further transition is expected.
  bool get terminal => this == completed || this == failed || this == cancelled;
}

/// The extension does not capture and the backend never fetches content. This
/// record says only what the user asked for; a device with a capture engine
/// claims it, converts it into an ordinary local save task, and applies its
/// own capture policy and validation unchanged.
///
/// It is NOT OfflineCopy state and must never be read as one: the server still
/// does not know what any device holds. A failure never changes library
/// membership (I17).
class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.entryId,
    required this.state,
    this.locationId,
    this.idempotencyKey = '',
    this.createdBy = '',
    this.createdAt,
    this.claimedByDevice = '',
    this.claimedAt,
    this.resolvedAt,
    this.failureReason = '',
  });

  final String id;
  final String entryId;
  final String? locationId;
  final DownloadRequestState state;
  final String idempotencyKey;
  final String createdBy;
  final DateTime? createdAt;
  final String claimedByDevice;
  final DateTime? claimedAt;
  final DateTime? resolvedAt;
  final String failureReason;

  /// The single-winner claim: only a pending request may be claimed, so
  /// exactly one device wins and the loser is told — the same conditional
  /// transition V1's queue uses. Returns the violation instead of the claimed
  /// request when this one already lost.
  (DownloadRequest?, InvariantViolation?) claim({
    required String device,
    required DateTime at,
  }) {
    if (state != DownloadRequestState.pending) {
      return (null, requestAlreadyClaimed);
    }
    return (
      _copy(
        state: DownloadRequestState.claimed,
        claimedByDevice: device,
        claimedAt: at,
      ),
      null,
    );
  }

  /// Records the terminal state a device reported. Refuses a non-terminal
  /// target: "still working on it" is not a resolution.
  (DownloadRequest?, InvariantViolation?) resolve({
    required DownloadRequestState to,
    required DateTime at,
    String reason = '',
  }) {
    if (!to.terminal) return (null, requestNotTerminal);
    return (_copy(state: to, resolvedAt: at, failureReason: reason), null);
  }

  DownloadRequest _copy({
    DownloadRequestState? state,
    String? claimedByDevice,
    DateTime? claimedAt,
    DateTime? resolvedAt,
    String? failureReason,
  }) {
    return DownloadRequest(
      id: id,
      entryId: entryId,
      locationId: locationId,
      state: state ?? this.state,
      idempotencyKey: idempotencyKey,
      createdBy: createdBy,
      createdAt: createdAt,
      claimedByDevice: claimedByDevice ?? this.claimedByDevice,
      claimedAt: claimedAt ?? this.claimedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
