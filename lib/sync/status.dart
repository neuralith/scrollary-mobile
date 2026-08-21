/// What `Settings → Sync` is allowed to know (roadmap G7).
///
/// Routine success is silent (V2_SYNC.md §3). This file exists so that the one
/// screen permitted to show sync state has something to show, and so that the
/// derivation — snapshot plus scheduler state in, one calm sentence out — can
/// be asserted without a widget.
///
/// Three properties this file is responsible for:
///
/// - **Invisible when healthy.** [SyncStatusView.isHealthy] is the whole
///   condition, and nothing here produces an event, a badge or a message. A
///   healthy sync has no user-facing consequence anywhere in the app.
/// - **A failure the user cannot act on is not an alert.** An unreachable
///   service is a sentence in Settings that says when the app will try again,
///   and nothing else.
/// - **A rejection is different from a failure.** The server refusing an
///   intent is deterministic and permanent, so it is parked and counted — that
///   is the only thing here that asks for attention.
library;

import 'session.dart';

/// The one word for what sync is doing. Ordered by precedence: a run in
/// flight outranks a pending retry, which outranks a parked rejection, which
/// outranks quiet.
enum SyncPhase {
  /// No transport is configured on this device. Not an error and not a
  /// failure — there is nothing to reach, so nothing is attempted.
  neverConfigured,

  /// Nothing to say. The state the app is in almost all of the time.
  idle,

  /// An opportunity is in flight.
  syncing,

  /// The last attempt could not reach the service; another is scheduled.
  retrying,

  /// The service refused one or more intents. They are parked, counted and
  /// visible; everything else keeps syncing.
  attention,
}

/// A snapshot of sync as Settings sees it. Immutable and comparable, so a
/// notifier can drop a republish that changes nothing.
class SyncStatusView {
  const SyncStatusView({
    required this.phase,
    this.lastSuccessAt,
    this.pendingCount = 0,
    this.problemCount = 0,
    this.nextRetryAt,
  });

  /// Before the first snapshot has been read. [configured] is what the
  /// transport resolver answered, so an unconfigured device says so from the
  /// first frame rather than claiming to be up to date.
  factory SyncStatusView.initial({required bool configured}) => SyncStatusView(
    phase: configured ? SyncPhase.idle : SyncPhase.neverConfigured,
  );

  final SyncPhase phase;

  /// The last opportunity that completed without a transport failure.
  final DateTime? lastSuccessAt;

  /// Local changes journalled and not yet acknowledged, excluding parked
  /// rejections.
  final int pendingCount;

  /// Parked rejections — the only thing on this surface that asks for
  /// attention.
  final int problemCount;

  /// When the scheduled retry will run, when one is scheduled.
  final DateTime? nextRetryAt;

  /// Whether this state is allowed to be completely invisible.
  bool get isHealthy => phase == SyncPhase.idle && problemCount == 0;

  bool get isRunning => phase == SyncPhase.syncing;

  @override
  bool operator ==(Object other) =>
      other is SyncStatusView &&
      other.phase == phase &&
      other.lastSuccessAt == lastSuccessAt &&
      other.pendingCount == pendingCount &&
      other.problemCount == problemCount &&
      other.nextRetryAt == nextRetryAt;

  @override
  int get hashCode => Object.hash(
    phase,
    lastSuccessAt,
    pendingCount,
    problemCount,
    nextRetryAt,
  );

  @override
  String toString() =>
      'SyncStatusView(${phase.name}, pending: $pendingCount, '
      'problems: $problemCount)';
}

/// Folds the engine's snapshot and the scheduler's own state into one view.
///
/// [snapshot] is null before the first read. [configured] answers whether a
/// transport exists at all — asked here rather than inferred from a missing
/// success, because a device that has never synced and a device that cannot
/// are different states and only one of them is worth a sentence.
SyncStatusView deriveSyncStatus({
  required SyncStatus? snapshot,
  required bool configured,
  required bool running,
  DateTime? nextRetryAt,
}) {
  final pending = snapshot?.pendingCount ?? 0;
  final problems = snapshot?.rejectedCount ?? 0;
  final phase = !configured
      ? SyncPhase.neverConfigured
      : running
      ? SyncPhase.syncing
      : nextRetryAt != null
      ? SyncPhase.retrying
      : problems > 0
      ? SyncPhase.attention
      : SyncPhase.idle;
  return SyncStatusView(
    phase: phase,
    lastSuccessAt: snapshot?.lastSuccessAt,
    pendingCount: pending < 0 ? 0 : pending,
    problemCount: problems,
    nextRetryAt: configured ? nextRetryAt : null,
  );
}

/// What the sync section reads, and the two things it may ask for.
///
/// Deliberately smaller than the scheduler: a screen has no business starting
/// a periodic timer or hearing about a lifecycle change, and a surface this
/// narrow is one a test can stand in for without a clock or a transport.
abstract class SyncStatusSource {
  /// The current view. Always available, never null.
  SyncStatusView get status;

  /// Every subsequent view. Broadcast; a late listener starts from [status].
  Stream<SyncStatusView> get statusChanges;

  /// Re-reads the snapshot and republishes. Cheap, and safe to call from a
  /// screen that has just been opened.
  Future<void> refreshStatus();

  /// The user asked. Completes when the opportunity it asked for has finished.
  Future<void> syncNow();
}

// ─── words ──────────────────────────────────────────────────────────────────

/// The current state, in one sentence.
///
/// It says what the app is doing, never what the user should do about it.
String syncStatusSentence(SyncStatusView view, DateTime now) =>
    switch (view.phase) {
      SyncPhase.neverConfigured => 'Sync is not set up on this device.',
      SyncPhase.syncing => 'Syncing now.',
      SyncPhase.retrying =>
        'The sync service could not be reached. '
            'Trying again ${syncDelayPhrase(view.nextRetryAt, now)}.',
      // A parked rejection is stated by its own row; the state itself is quiet.
      SyncPhase.attention || SyncPhase.idle =>
        view.pendingCount == 0 ? 'Up to date.' : 'Changes are waiting to sync.',
    };

/// Last success and how much is waiting, on one quiet line.
String syncDetailLine(SyncStatusView view, DateTime now) {
  final synced = view.lastSuccessAt == null
      ? 'Not synced yet'
      : 'Last synced ${syncAgoPhrase(view.lastSuccessAt!, now)}';
  if (view.pendingCount == 0) return synced;
  return '$synced · ${_changes(view.pendingCount)} waiting';
}

/// The attention row's headline, when there is one.
String syncProblemHeadline(int problemCount) =>
    '${_changes(problemCount)} ${problemCount == 1 ? 'was' : 'were'} '
    'not accepted';

/// Why the attention row is not an emergency.
const String kSyncProblemNote =
    'They stay on this device and nothing was lost. Everything else keeps '
    'syncing.';

String _changes(int count) => '$count change${count == 1 ? '' : 's'}';

/// How long ago something happened, in the app's existing register.
String syncAgoPhrase(DateTime at, DateTime now) {
  final delta = now.difference(at);
  if (delta.isNegative || delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

/// How long until something will happen.
String syncDelayPhrase(DateTime? at, DateTime now) {
  if (at == null) return 'shortly';
  final delta = at.difference(now);
  if (delta.inSeconds <= 0) return 'in a moment';
  if (delta.inSeconds < 60) return 'in ${delta.inSeconds}s';
  if (delta.inMinutes < 60) return 'in ${delta.inMinutes}m';
  return 'in ${delta.inHours}h';
}
