/// One sync opportunity, end to end (roadmap G1–G3; V2_SYNC.md §4.4).
///
/// `syncOnce` = pull → push → pull again if the push landed anything —
/// pulling first applies local mutations on top of the server's current view
/// instead of racing it, and the trailing pull collects the revisions the
/// push produced. Every step is kill-safe on its own (cursor moves only with
/// its committed batch; outbox rows go only on acknowledgement), so the
/// session needs no state of its own and a re-run from anywhere converges.
///
/// Failure is an outcome, not an exception: callers schedule opportunities,
/// they do not handle sync internals. Routine success is silent (§3) — the
/// status snapshot exists for `Settings → Sync` and nothing else.
library;

import '../data/data_ids.dart';
import '../data/schema.dart';
import 'identity.dart';
import 'pull.dart';
import 'push.dart';
import 'repositories.dart';
import 'transport.dart';

/// What `Settings → Sync` shows. Derived on demand; never cached.
class SyncStatus {
  const SyncStatus({
    required this.pendingCount,
    required this.rejectedCount,
    required this.cursor,
    required this.lastSuccessAt,
    required this.lastAttemptAt,
    required this.lastError,
  });

  final int pendingCount;
  final int rejectedCount;
  final int cursor;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
}

class SyncOutcome {
  const SyncOutcome({required this.pulled, required this.pushed, this.error});

  final PullResult? pulled;
  final PushResult? pushed;

  /// A transport-level failure that ended the opportunity early. The next
  /// opportunity resumes; nothing was lost (§1).
  final String? error;

  bool get succeeded => error == null;
}

class SyncEngine {
  SyncEngine(LibraryDatabase db, {Clock? now})
    : _repos = SyncRepositories(db),
      _now = now ?? utcNow {
    _identity = SyncIdentity(_repos);
    _puller = SyncPuller(_repos, _identity);
    _pusher = SyncPusher(_repos);
  }

  final SyncRepositories _repos;
  final Clock _now;
  late final SyncIdentity _identity;
  late final SyncPuller _puller;
  late final SyncPusher _pusher;

  SyncRepositories get repositories => _repos;
  SyncIdentity get identity => _identity;

  Future<SyncOutcome> syncOnce(
    SyncTransport transport, {
    int pullLimit = 200,
  }) async {
    await _repos.syncState.recordAttempt(_now());
    PullResult? pulled;
    PushResult? pushed;
    try {
      pulled = await _puller.pullAll(transport, limit: pullLimit);
      pushed = await _pusher.drainAll(transport);
      if (pushed.stoppedBy != null) {
        await _repos.syncState.recordError(pushed.stoppedBy!, _now());
        return SyncOutcome(
          pulled: pulled,
          pushed: pushed,
          error: pushed.stoppedBy,
        );
      }
      if (pushed.pushedAnything) {
        pulled = await _puller.pullAll(transport, limit: pullLimit);
      }
      await _repos.syncState.recordSuccess(_now());
      return SyncOutcome(pulled: pulled, pushed: pushed);
    } on SyncTransportException catch (e) {
      await _repos.syncState.recordError(e.message, _now());
      return SyncOutcome(pulled: pulled, pushed: pushed, error: e.message);
    }
  }

  Future<SyncStatus> status() async {
    final state = await _repos.syncState.current();
    final rejected = await _repos.outbox.rejected();
    final pending = await _repos.outbox.pendingCount();
    return SyncStatus(
      pendingCount: pending - rejected.length,
      rejectedCount: rejected.length,
      cursor: state.cursor,
      lastSuccessAt: state.lastSuccessAt?.toUtc(),
      lastAttemptAt: state.lastAttemptAt?.toUtc(),
      lastError: state.lastError,
    );
  }
}
