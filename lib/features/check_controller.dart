import 'package:flutter/foundation.dart';

import '../browser/browser_controller.dart';
import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/recognition_index.dart';
import '../recognition/check.dart';
import '../recognition/discovery.dart';
import '../save/capture_policy.dart';

/// Runs one explicit, user-started Source check through the real Browser.
///
/// The app-level owner of a check: it takes the Browser's automation
/// ownership for the run's duration (so a save and a check can never fight
/// over the WebView), waits for the surface to be painted, and relays the
/// cooperative cancel. The judgements all live in `recognition/check.dart`;
/// this class only drives it and publishes "a check is running" for the shell
/// to keep the Browser painted — the same contract V1's checker had.
class CheckController extends ChangeNotifier {
  CheckController({
    required this._browser,
    required this._collections,
    required this._entries,
    required this._index,
    required this._observations,
  });

  final BrowserController _browser;
  final CollectionRepository _collections;
  final EntryRepository _entries;
  final RecognitionIndex _index;
  final SourceObservationSource _observations;

  bool _running = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  String? _collectionId;
  SourceCheckOutcome? _lastOutcome;

  bool get isRunning => _running;
  bool get needsRenderedBrowser => _running;

  /// Test hook, mirroring the V1 checker's.
  @visibleForTesting
  void debugSetRunning(bool value) {
    _running = value;
    notifyListeners();
  }

  String? get runningCollectionId => _collectionId;
  SourceCheckOutcome? get lastOutcome => _lastOutcome;

  /// Ask the running check to stop at the next safe point.
  void cancel() => _cancelRequested = true;

  /// Check [collectionId]'s preferred Source. [checkSourceId] names another
  /// Source explicitly — a separate act the user performs, never an
  /// iteration.
  ///
  /// [limits] are the user's own visible numbers, passed by the surface that
  /// collected them.
  Future<SourceCheckOutcome?> run(
    String collectionId, {
    String? checkSourceId,
    required SourceCheckLimits limits,
  }) async {
    if (_running || _disposed) return null;
    if (_browser.isAutomating) return null;

    // The policy is asked before anything opens, host-first, exactly as the
    // V1 checker did: a restricted host never even navigates.
    final sourceId =
        checkSourceId ??
        (await _collections.byId(collectionId))?.preferredSourceId;
    if (sourceId != null) {
      final source = await _collections.sourceById(sourceId);
      if (source != null && isRestrictedCaptureHost(source.host)) {
        return null;
      }
    }

    _running = true;
    _cancelRequested = false;
    _collectionId = collectionId;
    _browser.automationOwner = 'a source check';
    notifyListeners();
    try {
      // The page must be drawn, not merely shown — the covered-WebView rule
      // the whole foreground design rests on.
      await _browser.awaitPaintedSurface();
      final check = SourceCheck(
        collections: _collections,
        entries: _entries,
        index: _index,
        discovery: SourceDiscovery(
          entries: _entries,
          collections: _collections,
          index: _index,
        ),
        observations: _observations,
      );
      final outcome = checkSourceId == null
          ? await check.checkPreferredSource(
              collectionId,
              limits: limits,
              shouldContinue: () => !_cancelRequested && !_disposed,
            )
          : await check.checkSource(
              checkSourceId,
              limits: limits,
              shouldContinue: () => !_cancelRequested && !_disposed,
            );
      _lastOutcome = outcome;
      return outcome;
    } finally {
      _browser.automationOwner = null;
      _running = false;
      _collectionId = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
