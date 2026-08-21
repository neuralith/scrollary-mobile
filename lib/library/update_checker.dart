import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:drift/drift.dart' show Value;

import '../browser/browser_controller.dart';
import '../browser/browser_surface_policy.dart';
import '../browser/history_repository.dart' show NavigationSource;
import '../browser/page_data.dart';
import '../save/capture_policy.dart';
import '../save/next_page.dart';
import '../save/page_hint_repository.dart';
import '../save/selection_request.dart';
import '../save/page_hint.dart';
import '../core/url_utils.dart';
import '../storage/database.dart';
import '../storage/manifest.dart';
import 'collection_identity.dart';
import 'content_shape.dart';
import '../recognition/entry_identity.dart';

export '../recognition/entry_identity.dart'
    show
        EntryIdentityConcern,
        EntryIdentityDoubt,
        EntryIdentityReading,
        kEntryIdentityUnreliableMessage;

const _uuid = Uuid();

/// Where a check is, right now.
enum UpdateCheckState {
  idle,
  checking,
  upToDate,
  updatesAvailable,

  /// Detection was not confident and the user has not yet pointed at the
  /// control. The check is holding; the selection happens in the Browser tab.
  needsUserInput,
  failed,
  cancelled;

  bool get isTerminal =>
      this == upToDate ||
      this == updatesAvailable ||
      this == failed ||
      this == cancelled;
}

/// How many *forward entry transitions* one check may make on its own.
///
/// Depth is counted from the page the check starts on, which is depth **0**:
/// following one "next entry" link reaches depth 1, following a second reaches
/// depth 2, and there is no third. Deliberately shallow — a check answers
/// "has anything appeared since?", and two hops is enough to answer it while
/// keeping the number of someone else's pages this app opens predictable and
/// small. Whatever is beyond it is left for the next check, which resumes from
/// the `next_source_url` this one stored.
///
/// Check-only. Save ranges are bounded by `SaveLimits.forScope` from a number
/// the user typed and share nothing with this.
const int kUpdateCheckForwardDepth = 2;

/// Bounds for one check. Everything here exists to make an unbounded crawl
/// structurally impossible.
class UpdateCheckConfig {
  const UpdateCheckConfig({
    this.maxPagesInspected = 12,
    this.maxNewEntries = 20,
    this.maxForwardDepth = kUpdateCheckForwardDepth,
    this.maxCheckDuration = const Duration(minutes: 3),
    this.navigationTimeout = const Duration(seconds: 25),
    this.cooldownBetweenPages = const Duration(milliseconds: 800),
  });

  final int maxPagesInspected;
  final int maxNewEntries;

  /// Forward entry transitions allowed in one run — see
  /// [kUpdateCheckForwardDepth]. The starting page is depth 0 and is not a
  /// transition.
  final int maxForwardDepth;

  final Duration maxCheckDuration;
  final Duration navigationTimeout;
  final Duration cooldownBetweenPages;
}

const kDefaultUpdateCheckConfig = UpdateCheckConfig();

/// How one check ended.
class UpdateCheckOutcome {
  const UpdateCheckOutcome({
    required this.state,
    this.newEntries = 0,
    this.pagesInspected = 0,
    this.staleRemoved = 0,
    this.error,
    this.detail = '',
    this.concerns = const [],
  });

  final UpdateCheckState state;
  final int newEntries;
  final int pagesInspected;

  /// Discovered-only rows this check removed because the source's own entry
  /// list no longer carries them, inside a window it could vouch for. Never
  /// anything the user holds: see
  /// [AppDatabase.reconcileDiscoveredEntries], which owns the rule.
  final int staleRemoved;

  final String? error;
  final String detail;

  /// Present when the check stopped because it could not justify an entry's
  /// number. [error] is the sentence; this is the evidence behind it, kept
  /// structured so a report can eventually show which entry, what each source
  /// read, and what the addresses around it said — none of which is shown
  /// anywhere yet.
  final List<EntryIdentityConcern> concerns;

  /// The check stopped on an unsupportable entry identity rather than on a
  /// network or navigation failure. Both are [UpdateCheckState.failed]; only
  /// this one has evidence to show.
  bool get stoppedOnEntryIdentity => concerns.isNotEmpty;
}

/// Foreground, user-triggered "has this collection published anything since?".
///
/// Discovers entry *metadata* only: a discovered entry becomes a
/// `knownRemote` row with no local content, never a fake offline entry.
/// Downloading stays a separate, explicit act.
///
/// Discovery is **not** a growing union of everything ever seen. A discovered
/// row is a claim about the source, so a later reading of the source can
/// withdraw it: when one entry-list read can vouch for a window of the
/// collection — see [ObservedEntryWindow] — the discovered-only rows inside
/// that window which the page did not show are removed. The chain walk never
/// does this, and nothing the user holds is reachable by it; the rule itself
/// lives in [AppDatabase.reconcileDiscoveredEntries] rather than here, so it
/// cannot be worked around from this side.
///
/// Reuses the same machinery saves trust: safe-URL validation, the
/// saved-rule → generic next-detection chain, and the user-assisted fallback
/// when confidence is insufficient.
class UpdateChecker extends ChangeNotifier implements SelectionHost {
  UpdateChecker({
    required this.browser,
    required this.db,
    PageHintRepository? rules,
    this.config = kDefaultUpdateCheckConfig,
  }) : rules = rules ?? PageHintRepository(db);

  @override
  final BrowserController browser;
  final AppDatabase db;
  final PageHintRepository rules;
  final UpdateCheckConfig config;

  UpdateCheckState _state = UpdateCheckState.idle;
  UpdateCheckState get state => _state;

  /// The collection being checked, while one is.
  String? _activeItemId;
  String? get activeItemId => _activeItemId;

  /// That collection's title, so the running-operation panel can name what it
  /// is checking without a database read of its own.
  String _activeTitle = '';
  String get activeTitle => _activeTitle;

  /// Live counters for the running check. Both are what the outcome will
  /// report; they exist as fields so the panel can show the same numbers while
  /// the walk is still going rather than only after it ends.
  int _pagesInspected = 0;
  int get pagesInspected => _pagesInspected;

  int _newEntries = 0;
  int get newEntries => _newEntries;

  /// Discovered-only rows this check retracted because the source's list no
  /// longer carries them.
  int _staleRemoved = 0;
  int get staleRemoved => _staleRemoved;

  /// The same number, per collection, for the checks made **this session**.
  ///
  /// Session state on purpose. The rows it describes are gone, so there is
  /// nothing left to derive it from — but it is also not a fact worth a schema
  /// column: it answers "what did the check you just watched do", and after a
  /// restart there is no check the user just watched. A collection absent from
  /// here has had nothing removed as far as anything can still say.
  final Map<String, int> _staleRemovedByCollection = {};
  int staleRemovedFor(String collectionId) =>
      _staleRemovedByCollection[collectionId] ?? 0;

  /// The same record, for a report that reads several collections at once.
  Map<String, int> get staleRemovedByCollection =>
      Map.unmodifiable(_staleRemovedByCollection);

  /// How many forward entry transitions have been made, out of
  /// [UpdateCheckConfig.maxForwardDepth]. The starting page is depth 0.
  int _forwardDepth = 0;
  int get forwardDepth => _forwardDepth;

  String _message = '';
  String get message => _message;

  final List<String> _log = [];
  List<String> get log => List.unmodifiable(_log);

  bool _cancelRequested = false;
  bool get isRunning =>
      _state == UpdateCheckState.checking ||
      _state == UpdateCheckState.needsUserInput;

  SelectionRequest? _pendingSelection;
  @override
  SelectionRequest? get pendingSelection => _pendingSelection;
  Completer<SelectionOutcome>? _selectionCompleter;

  /// URLs walked or already known this check; what stops loops.
  final Set<String> _visited = {};

  /// Entry identities this check could not justify. Populated by the write
  /// gate and by the list reading, and emptied at the start of every check.
  final List<EntryIdentityConcern> _concerns = [];

  /// What the entries already held read like, from both sources — the evidence
  /// the chain walk judges a newly walked page against. Built from rows that
  /// are already in hand, so no extra page is loaded to obtain it.
  final List<EntryIdentityReading> _identityEvidence = [];

  /// The outcome for a check that stopped on an entry it could not identify.
  UpdateCheckOutcome _identityRefusal() => UpdateCheckOutcome(
    state: UpdateCheckState.failed,
    error: kEntryIdentityUnreliableMessage,
    newEntries: _newEntries,
    pagesInspected: _pagesInspected,
    concerns: List.unmodifiable(_concerns),
  );

  void _addLog(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '$stamp  $message');
    if (_log.length > 200) _log.removeLast();
    _message = message;
    notifyListeners();
  }

  void cancel() {
    _cancelRequested = true;
    _addLog('cancel requested');
    // A held selection prompt ends with the check.
    _selectionCompleter?.complete(const SelectionOutcome.cancelled());
    _selectionCompleter = null;
    _pendingSelection = null;
    notifyListeners();
  }

  // --- SelectionHost --------------------------------------------------------

  @override
  Future<void> submitSelection(
    SelectedElement element, {
    HintScope scope = HintScope.collection,
  }) async {
    final request = _pendingSelection;
    if (request == null) return;

    final check = validateNextUrl(
      candidate: element.href,
      currentUrl: request.sourceUrl,
      visited: _visited,
    );
    if (!check.isAccepted) {
      _pendingSelection = request.withError(
        'That link is not usable here (${check.rejection?.name}). '
        'Pick the control that opens the next entry.',
      );
      notifyListeners();
      return;
    }

    // Save the rule exactly like the save flow does, at the narrowest
    // scope the user chose — the whole point is that the next check (and the
    // next save) does not have to ask again.
    final rule = await rules.createNextLinkHint(
      element: element,
      sourceUrl: request.sourceUrl,
      scope: scope,
    );
    _addLog(
      'saved next-link rule for ${rule.host}${rule.hintPath ?? ""} '
      '(scope: ${rule.scope.label})',
    );

    await browser.stopSelection();
    _pendingSelection = null;
    _selectionCompleter?.complete(SelectionOutcome.rule(rule, element));
    _selectionCompleter = null;
    notifyListeners();
  }

  @override
  Future<void> cancelSelection() async {
    await browser.stopSelection();
    _pendingSelection = null;
    _selectionCompleter?.complete(const SelectionOutcome.cancelled());
    _selectionCompleter = null;
    _addLog('selection cancelled by user');
    notifyListeners();
  }

  @override
  Future<void> retryAutomaticDetection() async {
    await browser.stopSelection();
    _pendingSelection = null;
    _selectionCompleter?.complete(const SelectionOutcome.retryAuto());
    _selectionCompleter = null;
    notifyListeners();
  }

  Future<SelectionOutcome> _askUser(SelectionRequest request) async {
    _pendingSelection = request;
    _selectionCompleter = Completer<SelectionOutcome>();
    _state = UpdateCheckState.needsUserInput;
    _addLog(
      'not confident: ${request.reason} — select the control in the '
      'Browser tab',
    );
    await browser.startSelection(mode: 'link');
    return _selectionCompleter!.future;
  }

  // --- the check -------------------------------------------------------------

  /// The first page this check would open, or null when it would open none.
  ///
  /// Asked *before* the check starts, by whoever is bringing the Browser
  /// forward, so the Browser can be showing the page the check is about to
  /// work on rather than whatever it happened to be on (D47). It reads only —
  /// nothing is claimed, navigated or written here, so a caller that then
  /// decides not to start has changed nothing.
  ///
  /// The precedence deliberately mirrors [_run] step for step: the collection
  /// page when there is a usable one, then the stored next link from the latest
  /// known entry, then that entry's own page. Keep the two in step — the value
  /// of this is that the Browser shows the page the walk actually opens first.
  Future<String?> firstPageToInspect(String collectionId) async {
    final item = await db.collectionById(collectionId);
    if (item == null) return null;
    if (isRestrictedCaptureHost(item.host) ||
        isCaptureRestricted(item.sourceUrl) ||
        isCaptureRestricted(item.collectionIndexUrl)) {
      return null;
    }

    final collectionIndexUrl = item.collectionIndexUrl;
    if (collectionIndexUrl != null &&
        collectionIndexUrl.isNotEmpty &&
        item.collectionKey != null) {
      return isCaptureRestricted(collectionIndexUrl)
          ? null
          : collectionIndexUrl;
    }

    final entries = await db.entriesForCollection(collectionId);
    if (entries.isEmpty) return null;
    final ordered = [...entries]
      ..sort(
        (a, b) => compareEntriesForReading(
          (number: a.entryNumber, entryOrder: a.entryOrder, savedAt: a.savedAt),
          (number: b.entryNumber, entryOrder: b.entryOrder, savedAt: b.savedAt),
        ),
      );
    final latest = ordered.last;

    final storedNext = latest.nextSourceUrl;
    if (storedNext != null) {
      final check = validateNextUrl(
        candidate: storedNext,
        currentUrl: latest.sourceUrl,
        visited: {for (final c in entries) c.urlKey},
      );
      if (check.isAccepted && !isCaptureRestricted(check.normalized)) {
        return check.normalized;
      }
    }
    return isCaptureRestricted(latest.sourceUrl) ? null : latest.sourceUrl;
  }

  Future<UpdateCheckOutcome> check(String collectionId) async {
    if (isRunning) {
      return const UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: 'a check is already running',
      );
    }
    if (browser.automationOwner != null) {
      return UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: 'cannot check while ${browser.automationOwner} is running',
      );
    }
    if (!browser.isAttached) {
      return const UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: 'the browser is not ready yet — open the Browser tab once',
      );
    }

    final item = await db.collectionById(collectionId);
    if (item == null) {
      return const UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: 'collection no longer listed',
      );
    }

    // The restricted-site policy. A check is discovery *for* capture: it opens
    // the source's pages and writes rows the user is then invited to save. It
    // is refused before the WebView is claimed, so nothing navigates and the
    // collection's existing entries, files and reading state are untouched.
    if (isRestrictedCaptureHost(item.host) ||
        isCaptureRestricted(item.sourceUrl) ||
        isCaptureRestricted(item.collectionIndexUrl)) {
      return const UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: kCaptureRestrictedMessage,
      );
    }

    final startedAt = DateTime.now();
    _activeItemId = collectionId;
    _activeTitle = item.title;
    _cancelRequested = false;
    _visited.clear();
    _log.clear();
    _concerns.clear();
    _identityEvidence.clear();
    _pagesInspected = 0;
    _newEntries = 0;
    _staleRemoved = 0;
    // A new check for this collection replaces what the last one reported.
    _staleRemovedByCollection.remove(collectionId);
    _forwardDepth = 0;
    _state = UpdateCheckState.checking;
    _addLog('checking "${item.title}" for new entries');

    browser.automationOwner = 'an update check';
    // Let the surface come back before the first page is opened. Claiming the
    // WebView is what makes the app start drawing it again; navigating in the
    // same breath would create the document while it is still uncomposited,
    // and that document keeps the visibility it was born with for its whole
    // life. See `BrowserController.awaitPaintedSurface`.
    await browser.awaitPaintedSurface();
    // Reading an entry list is the app asking the source a question, not a
    // page the user visited — excluded from browsing history (D53).
    browser.navigationSource = NavigationSource.updateCheck;
    browser.navigationLocked = true;
    browser.clearAllowedHostChanges();

    UpdateCheckOutcome outcome;
    try {
      outcome = await _run(item).timeout(
        config.maxCheckDuration,
        onTimeout: () {
          // Stop the underlying walk too — the timeout must end navigation,
          // not just stop waiting for it.
          _cancelRequested = true;
          return const UpdateCheckOutcome(
            state: UpdateCheckState.failed,
            error: 'check duration bound reached',
          );
        },
      );
    } catch (e) {
      outcome = UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: e.toString(),
      );
    } finally {
      browser.navigationLocked = false;
      browser.automationOwner = null;
      browser.navigationSource = NavigationSource.manual;
      _pendingSelection = null;
      _selectionCompleter = null;
    }

    // Persist the outcome — including failures. "It last failed, and why"
    // is collection state the UI must be able to show after a restart.
    final succeeded =
        outcome.state == UpdateCheckState.upToDate ||
        outcome.state == UpdateCheckState.updatesAvailable;
    try {
      await db.writeCollectionCheck(
        collectionId,
        CollectionsCompanion(
          lastCheckAt: Value(startedAt),
          lastCheckSuccessAt: succeeded
              ? Value(DateTime.now())
              : const Value.absent(),
          lastCheckError: Value(outcome.error),
          lastCheckResult: Value(outcome.state.name),
        ),
      );
    } catch (_) {}

    _state = outcome.state;
    _activeItemId = null;
    _activeTitle = '';
    final retracted = outcome.staleRemoved > 0
        ? ' · ${outcome.staleRemoved} no longer listed'
        : '';
    _addLog(switch (outcome.state) {
      UpdateCheckState.upToDate =>
        'up to date — nothing new on the source$retracted',
      UpdateCheckState.updatesAvailable =>
        '${outcome.newEntries} new entry(s) found '
            '(not downloaded — save is a separate step)$retracted',
      UpdateCheckState.cancelled => 'check cancelled',
      _ => 'check failed: ${outcome.error}',
    });
    notifyListeners();
    return outcome;
  }

  Future<UpdateCheckOutcome> _run(Collection item) async {
    final entries = await db.entriesForCollection(item.id);
    if (entries.isEmpty) {
      return const UpdateCheckOutcome(
        state: UpdateCheckState.failed,
        error: 'no known entry to start from',
      );
    }

    for (final c in entries) {
      _visited.add(c.urlKey);
      // Read afresh from the stored title and address rather than trusting the
      // stored number, which may itself have come from either source. The two
      // readings are only evidence while they are still independent.
      _identityEvidence.add(
        EntryIdentityReading.read(url: c.sourceUrl, label: c.title),
      );
    }

    double? latestNumber;
    for (final c in entries) {
      final n = c.entryNumber;
      if (n != null && (latestNumber == null || n > latestNumber)) {
        latestNumber = n;
      }
    }
    var maxEntryOrder = 0;
    for (final c in entries) {
      if (c.entryOrder > maxEntryOrder) maxEntryOrder = c.entryOrder;
    }

    // Counted on the controller rather than in locals so the running panel
    // shows the same numbers the outcome will report, while it is happening.
    // --- strategy 1: the collection page's entry list ------------------------
    final collectionIndexUrl = item.collectionIndexUrl;
    final collectionKey = item.collectionKey;
    if (collectionIndexUrl != null &&
        collectionIndexUrl.isNotEmpty &&
        collectionKey != null) {
      if (_cancelRequested) {
        return const UpdateCheckOutcome(state: UpdateCheckState.cancelled);
      }
      _addLog('inspecting collection page: $collectionIndexUrl');
      final probe = await _navigateAndProbe(collectionIndexUrl);
      _pagesInspected++;
      if (probe != null) {
        final discovery = discoverFromEntryList(
          probe,
          collectionKey: collectionKey,
          latestKnownNumber: latestNumber,
          knownUrlKeys: _visited,
          maxNew: config.maxNewEntries,
        );
        _addLog(
          'entry list: ${discovery.direction.name}, '
          '${discovery.knownSeen} already held, '
          '${discovery.newEntries.length} new'
          '${discovery.orderingConfident ? '' : ' (ordering unclear)'}',
        );
        if (discovery.dropped > 0) {
          _addLog(
            '${discovery.dropped} further new entry(s) left for the next '
            'check (limit ${config.maxNewEntries})',
          );
        }
        // The list contradicted itself about at least one entry's number.
        // Stopping here is the point: not writing the doubted row would still
        // leave us reading the rest of the same page with the same fault, and
        // falling through to the chain walk would re-read those same entries
        // from their own pages and call a second wrong answer a second opinion.
        if (discovery.concerns.isNotEmpty) {
          _concerns.addAll(discovery.concerns);
          for (final concern in discovery.concerns) {
            _addLog(concern.summary);
          }
          _addLog(kEntryIdentityUnreliableMessage);
          return _identityRefusal();
        }
        // Trusting an empty result means declaring the collection up to date
        // without looking any further. That is only safe when the list's own
        // ordering was unambiguous; otherwise "nothing above the checkpoint"
        // may just mean we could not tell what was above it, and the chain
        // walk gets its turn.
        if (discovery.listRecognised &&
            (discovery.newEntries.isNotEmpty || discovery.orderingConfident)) {
          // Reconcile before writing. What the page held has already been read
          // in full at this point, so the removal rests on a complete
          // observation — and doing it first is what lets the checkpoint below
          // be rebuilt from rows that are all still true.
          var reading = discovery;
          final removed = await _reconcile(item, discovery);
          if (removed > 0) {
            // The checkpoint this check started from counted rows that have
            // just gone. Rebuild it from the database rather than adjusting the
            // numbers in place: a stale high number is exactly what stops a
            // collection ever discovering anything again, and a second copy of
            // it kept in a local would be the same bug with a shorter life.
            final remaining = await db.entriesForCollection(item.id);
            double? rebuilt;
            for (final c in remaining) {
              final n = c.entryNumber;
              if (n != null && (rebuilt == null || n > rebuilt)) rebuilt = n;
            }
            latestNumber = rebuilt;
            _identityEvidence
              ..clear()
              ..addAll([
                for (final c in remaining)
                  EntryIdentityReading.read(url: c.sourceUrl, label: c.title),
              ]);
            // Re-read the page already in hand against the corrected
            // checkpoint. Pure, and no request: the same probe, judged by what
            // the library now actually holds.
            reading = discoverFromEntryList(
              probe,
              collectionKey: collectionKey,
              latestKnownNumber: latestNumber,
              knownUrlKeys: _visited,
              maxNew: config.maxNewEntries,
            );
            if (reading.concerns.isNotEmpty) {
              _concerns.addAll(reading.concerns);
              for (final concern in reading.concerns) {
                _addLog(concern.summary);
              }
              _addLog(kEntryIdentityUnreliableMessage);
              return _identityRefusal();
            }
            _addLog(
              'entry list, re-read: ${reading.newEntries.length} new above '
              'the corrected checkpoint',
            );
          }
          // Written this pass, so the re-sighting loop below can tell what it
          // has already dealt with from what the source is repeating.
          final written = <String>{};
          for (final found_ in reading.newEntries) {
            // Asked per row, not once before the loop: a cancel that lands
            // while these are being written stops the discovery here. What was
            // already recorded stays — it is true, and rolling it back would
            // be a deletion nobody asked for.
            if (_cancelRequested) {
              _addLog('cancelled — the rest of the entry list was not read');
              return UpdateCheckOutcome(
                state: UpdateCheckState.cancelled,
                newEntries: _newEntries,
                pagesInspected: _pagesInspected,
                staleRemoved: _staleRemoved,
              );
            }
            maxEntryOrder++;
            final recorded = await _recordDiscovered(
              item: item,
              url: found_.url,
              title: found_.title,
              number: found_.number,
              entryOrder: maxEntryOrder,
              basis: 'entryList',
              confidence: 'high',
              inView: _identityEvidence,
            );
            if (recorded == _DiscoveryWrite.refused) return _identityRefusal();
            if (recorded != _DiscoveryWrite.written) continue;
            _newEntries++;
            _addLog('found: ${found_.title}');
            written.add(normalizeUrl(found_.url));
          }

          // Everything else the page listed is an entry already held. Not a
          // finding and never counted as one — but it is the source's current
          // words about entries this app recorded from an older reading of the
          // same list, and the rows that are still only discoveries take them.
          // Through the same gate the new ones went through, so a page being
          // read wrongly cannot rewrite what is stored either.
          for (final seen in reading.observedEntries) {
            if (_cancelRequested) break;
            if (written.contains(normalizeUrl(seen.url))) continue;
            final recorded = await _recordDiscovered(
              item: item,
              url: seen.url,
              title: seen.title,
              number: seen.number,
              basis: 'entryList',
              confidence: 'high',
              inView: _identityEvidence,
            );
            if (recorded == _DiscoveryWrite.refused) return _identityRefusal();
          }
          return UpdateCheckOutcome(
            state: _newEntries > 0
                ? UpdateCheckState.updatesAvailable
                : UpdateCheckState.upToDate,
            newEntries: _newEntries,
            pagesInspected: _pagesInspected,
            staleRemoved: _staleRemoved,
            detail: 'entry list on the collection page',
          );
        }
        _addLog(
          discovery.listRecognised
              ? 'entry list gave nothing but could not be ordered — '
                    'walking the entry chain'
              : 'no recognisable entry list — walking the entry chain',
        );
      } else {
        _addLog('collection page unreachable — walking the entry chain');
      }
    }

    // --- strategy 2: follow next-entry links from the latest known -------
    final ordered = [...entries]
      ..sort(
        (a, b) => compareEntriesForReading(
          (number: a.entryNumber, entryOrder: a.entryOrder, savedAt: a.savedAt),
          (number: b.entryNumber, entryOrder: b.entryOrder, savedAt: b.savedAt),
        ),
      );
    final latest = ordered.last;
    _addLog('latest known: ${latest.sourceMarker ?? latest.title}');

    String? next;
    final storedNext = latest.nextSourceUrl;
    if (storedNext != null) {
      final check = validateNextUrl(
        candidate: storedNext,
        currentUrl: latest.sourceUrl,
        visited: _visited,
      );
      next = check.isAccepted ? check.normalized : null;
    }
    if (next == null) {
      // Only now open the latest entry's own page to read its next link. This
      // is the check's *starting* page — depth 0 — and reading it is not a
      // forward transition.
      if (_cancelRequested) {
        return UpdateCheckOutcome(
          state: UpdateCheckState.cancelled,
          newEntries: _newEntries,
        );
      }
      final probe = await _navigateAndProbe(latest.sourceUrl);
      _pagesInspected++;
      if (probe == null) {
        return UpdateCheckOutcome(
          state: UpdateCheckState.failed,
          error: 'could not open the latest known entry',
          pagesInspected: _pagesInspected,
        );
      }
      // A page that answered with no links at all did not tell us the chain
      // ends here; it told us nothing. Reading that as "up to date" on first
      // sight is the check's characteristic silent failure — invisible,
      // and it stamps the collection as checked. `readyState` does not help:
      // a page that builds its own list is 'complete' long before the list
      // exists. So give it one settle window and read again, and if it is
      // still empty, say so out loud rather than reporting a clean result
      // that happens to be indistinguishable from one.
      var settled = probe;
      if (settled.links.isEmpty) {
        _addLog('no links on the page yet — waiting once before reading again');
        await Future<void>.delayed(config.cooldownBetweenPages);
        // Re-read, not re-fetch: the page is already open, and asking the
        // site for it a second time is a request this app has no reason to
        // make.
        try {
          settled = await browser.probe(withLinks: true);
        } catch (_) {
          // Mid-navigation or gone; the empty read stands.
        }
        if (settled.links.isEmpty) {
          _addLog(
            'the latest known entry still offers no links — treating this '
            'check as inconclusive rather than up to date',
          );
        }
      }
      final resolved = await _resolveNext(settled, latest.sourceUrl);
      if (resolved.cancelled) {
        return UpdateCheckOutcome(
          state: UpdateCheckState.cancelled,
          pagesInspected: _pagesInspected,
        );
      }
      next = resolved.url;
    }

    // Each turn of this loop *is* one forward entry transition: it opens the
    // page `next` points at. The starting page above is depth 0, so the loop
    // may run at most [UpdateCheckConfig.maxForwardDepth] times, whatever the
    // page and new-entry bounds would otherwise allow.
    while (next != null &&
        _forwardDepth < config.maxForwardDepth &&
        _newEntries < config.maxNewEntries &&
        _pagesInspected < config.maxPagesInspected) {
      if (_cancelRequested) {
        return UpdateCheckOutcome(
          state: UpdateCheckState.cancelled,
          newEntries: _newEntries,
          pagesInspected: _pagesInspected,
        );
      }

      // The chain may not leave the collection: a "next" that jumps to another
      // collection (or a login page — the validator already rejects those paths)
      // ends the check instead of being followed.
      if (collectionFingerprint(next) !=
          collectionFingerprint(latest.sourceUrl)) {
        _addLog('next link leaves the collection — stopping: $next');
        break;
      }

      _forwardDepth++;
      final probe = await _navigateAndProbe(next);
      _pagesInspected++;
      if (probe == null) {
        _addLog('page unreachable, stopping: $next');
        break;
      }

      final landed = browser.currentUrl.isEmpty ? next : browser.currentUrl;
      final landedKey = normalizeUrl(landed);
      if (_visited.contains(landedKey)) {
        _addLog('landed on an already known entry — stopping');
        break;
      }
      if (collectionFingerprint(landed) != collectionFingerprint(next)) {
        _addLog('redirect left the collection — stopping');
        break;
      }
      _visited.add(landedKey);

      final title = probe.title.trim().isEmpty
          ? (browser.title.isEmpty ? landed : browser.title)
          : probe.title;

      // Resolve this page's own next link before recording, so the row can
      // carry it — the next check continues the chain without a page load.
      final resolved = await _resolveNext(probe, landed);

      maxEntryOrder++;
      final recorded = await _recordDiscovered(
        item: item,
        url: landed,
        title: title,
        number: parseEntryNumber(title: title, url: landed),
        entryOrder: maxEntryOrder,
        basis: 'nextChain',
        confidence: resolved.confidence ?? 'high',
        nextSourceUrl: resolved.url,
        inView: _identityEvidence,
      );
      if (recorded == _DiscoveryWrite.refused) return _identityRefusal();
      if (recorded == _DiscoveryWrite.written) {
        _newEntries++;
        _addLog('found: $title');
        // Each page the walk accepts becomes evidence for the next one, so a
        // chain that starts agreeing with itself keeps its own record of that.
        _identityEvidence.add(
          EntryIdentityReading.read(url: landed, label: title),
        );
      }

      if (resolved.cancelled) {
        return UpdateCheckOutcome(
          state: UpdateCheckState.cancelled,
          newEntries: _newEntries,
          pagesInspected: _pagesInspected,
        );
      }
      next = resolved.url;
      if (next == null) _addLog('end of chain');
      await Future<void>.delayed(config.cooldownBetweenPages);
    }

    if (next != null && _forwardDepth >= config.maxForwardDepth) {
      // Not a failure and not "up to date": the walk stopped where it was
      // told to. The row just written carries this page's own next link, so
      // the next check picks the chain up here instead of starting over.
      _addLog(
        'forward depth bound reached (${config.maxForwardDepth} entries '
        'ahead); check again to continue',
      );
    }
    if (next != null && _pagesInspected >= config.maxPagesInspected) {
      _addLog('page bound reached with more entries possibly remaining');
    }
    if (next != null && _newEntries >= config.maxNewEntries) {
      _addLog('new-entry bound reached; check again to continue');
    }

    return UpdateCheckOutcome(
      state: _newEntries > 0
          ? UpdateCheckState.updatesAvailable
          : UpdateCheckState.upToDate,
      newEntries: _newEntries,
      pagesInspected: _pagesInspected,
      detail: 'entry chain from the latest known entry',
    );
  }

  /// Retract the discovered-only entries the source's list no longer carries.
  ///
  /// Reachable from **entry-list discovery only**. The chain walk sees two
  /// entries ahead of the newest one held; nothing about a collection's
  /// membership can be concluded from that, so it never arrives here.
  ///
  /// Returns how many rows went. The decision of *which* is not made here —
  /// this passes on what was observed and `reconcileDiscoveredEntries` decides,
  /// in one transaction, against the rows as they are at that moment.
  Future<int> _reconcile(Collection item, EntryListDiscovery discovery) async {
    final window = discovery.observedWindow;
    // Nothing the page said can be used to prove an absence. The common case,
    // and the one that leaves every discovered row exactly where it is.
    if (window == null) return 0;
    // A check being stopped means its reading is no longer being acted on.
    // Asked immediately before the write: everything after this point is one
    // transaction, so there is no half-reconciled collection to come back to.
    if (_cancelRequested) return 0;

    final removed = await db.reconcileDiscoveredEntries(
      collectionId: item.id,
      observedUrlKeys: window.urlKeys,
      windowFrom: window.from,
      windowTo: window.to,
      windowOpenAbove: window.openAbove,
    );
    if (removed.isEmpty) return 0;

    for (final entry in removed) {
      _visited.remove(entry.urlKey);
      _addLog(
        'no longer listed at the source: ${entry.sourceMarker ?? entry.title}',
      );
    }
    _staleRemoved += removed.length;
    _staleRemovedByCollection[item.id] = _staleRemoved;
    _addLog(
      '${removed.length} entry(s) the source no longer lists were removed '
      '(never downloaded — nothing saved was touched)',
    );
    notifyListeners();
    return removed.length;
  }

  /// Saved rule first, then the generic chain; ask the user only when
  /// detection is not confident, exactly like a save would.
  Future<({String? url, String? confidence, bool cancelled})> _resolveNext(
    PageProbe probe,
    String currentUrl,
  ) async {
    String? hintHref;
    final rule = await rules.findFor(currentUrl, HintKind.nextLink);
    if (rule != null) {
      final match = await browser.applyLocator(rule.locator.toJson());
      if (match != null && match.isMatch) {
        hintHref = match.href;
        await rules.recordUse(rule.id, success: true);
      } else {
        _addLog('saved next-link rule did not match here');
        await rules.recordUse(rule.id, success: false);
      }
    }

    var result = resolveNextPage(
      probe,
      currentUrl: currentUrl,
      visitedNormalized: _visited,
      hintHref: hintHref,
    );

    if (result.needsUserSelection && !_cancelRequested) {
      final outcome = await _askUser(
        SelectionRequest(
          kind: HintKind.nextLink,
          sourceUrl: currentUrl,
          prompt: 'Select the next entry button',
          reason: result.reason,
          candidates: result.considered,
        ),
      );
      _state = UpdateCheckState.checking;
      notifyListeners();

      if (outcome.cancelled) {
        return (url: null, confidence: null, cancelled: true);
      }
      if (outcome.retryAutomatic) {
        result = resolveNextPage(
          probe,
          currentUrl: currentUrl,
          visitedNormalized: _visited,
        );
      } else if (outcome.hasRule) {
        final match = await browser.applyLocator(
          outcome.rule!.locator.toJson(),
        );
        final href = match?.isMatch == true
            ? match!.href
            : (outcome.element?.href ?? '');
        final check = validateNextUrl(
          candidate: href,
          currentUrl: currentUrl,
          visited: _visited,
        );
        return (
          url: check.isAccepted ? check.normalized : null,
          confidence: 'high',
          cancelled: false,
        );
      }
    }

    return (
      url: result.hasNext ? result.chosen!.href : null,
      confidence:
          result.chosen?.confidence?.name ??
          result.chosen?.strategy.baseConfidence.name,
      cancelled: false,
    );
  }

  Future<PageProbe?> _navigateAndProbe(String url) async {
    // A cancelled check does not open one more page. Asked here rather than
    // only at the callers, because this is the single place the walk moves the
    // Browser: whatever route reaches it, a cancel means no navigation.
    if (_cancelRequested) return null;
    // Every address the walk would open is asked about independently — the
    // collection cleared at the start says nothing about where its chain leads.
    // A restricted address is never navigated to and never probed.
    if (isCaptureRestricted(url)) {
      _addLog(kCaptureRestrictedMessage);
      return null;
    }
    try {
      browser.allowNextNavigation(url);
      await browser.loadAndWait(url, timeout: config.navigationTimeout);
      await Future<void>.delayed(config.cooldownBetweenPages);
      var probe = await browser.probe(withLinks: true);
      // Same protection as save, and the same three checks — see
      // `SaveEngine._waitForRenderedSurface`. A check reads links rather than
      // geometry, but "read nothing off a surface the app is not drawing" is
      // one rule, not two: a page whose entry list is built after layout has
      // exactly the save's problem, and its failure is worse, because an empty
      // link set reads as "no new entries".
      var warned = false;
      final waitStart = DateTime.now();
      while (!_cancelRequested) {
        final hold = surfaceHoldReason(
          surfaceIsPainted: browser.surfaceIsPainted,
          pageHidden: probe.pageHidden,
          viewportHeight: probe.viewportHeight,
          heldFor: DateTime.now().difference(waitStart),
        );
        if (hold == null) break;
        if (!warned) {
          warned = true;
          _addLog('browser surface: ${surfaceHoldMessage(hold)}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        probe = await browser.probe(withLinks: true);
      }
      if (_cancelRequested) return null;
      return probe;
    } catch (e) {
      _addLog('navigation failed: $e');
      return null;
    }
  }

  /// Write a discovered entry.
  ///
  /// The single place a discovery of any kind becomes a row, and therefore the
  /// place the identity is cross-checked one last time. Both strategies reach
  /// it, so neither can grow a way past it.
  ///
  /// [inView] is the evidence the caller had — the other entries on the list it
  /// read, or the entries already held plus the pages walked so far.
  Future<_DiscoveryWrite> _recordDiscovered({
    required Collection item,
    required String url,
    required String title,
    required double? number,
    required String basis,
    required String confidence,
    required List<EntryIdentityReading> inView,
    int? entryOrder,
    String? nextSourceUrl,
  }) async {
    // A discovered entry is a row the user is invited to save. One on a
    // restricted service is not written at all, so it can never become queued
    // work through the "save new entries" path.
    if (isCaptureRestricted(url)) {
      _addLog(kCaptureRestrictedMessage);
      return _DiscoveryWrite.skipped;
    }

    // Nothing is written on a number the evidence contradicts. This is the
    // boundary that matters: a row that never exists cannot be read back as a
    // checkpoint, cannot order anything, and cannot be repaired later by
    // guessing what the source meant.
    final reading = EntryIdentityReading.read(url: url, label: title);
    final concerns = reviewEntryIdentities(
      candidates: [reading],
      inView: [...inView, reading],
    );
    if (concerns.isNotEmpty) {
      _concerns.addAll(concerns);
      for (final concern in concerns) {
        _addLog(concern.summary);
      }
      return _DiscoveryWrite.refused;
    }

    final key = normalizeUrl(url);
    _visited.add(key);
    final existing = await db.findEntryByUrlKey(item.id, key);
    if (existing != null) {
      // Already known — never a duplicate row. Still worth a second look: the
      // source may have corrected a label since, or printed a number where it
      // had none, or this may be the check that found on a collection page
      // what a chain walk had only inferred. Nothing here decides what may be
      // written; `refreshDiscoveredEntry` holds the field rules and refuses
      // outright for a row that has become the user's.
      final stored = existing.entryNumber;
      if (stored != null && number != null && stored != number) {
        // Reported, not resolved. Replacing a stored number on the strength of
        // a second reading is how a good checkpoint becomes a guess.
        _addLog(
          'kept the stored number for ${existing.sourceMarker ?? existing.title} '
          '— the source now reads ${_plainNumber(number)}',
        );
      }
      final refreshed = await db.refreshDiscoveredEntry(
        id: existing.id,
        title: title,
        number: number,
        sourceMarker: sourceMarkerFrom(
          title: title,
          url: url,
          number: number ?? stored,
        ),
        basis: basis,
        confidence: confidence,
        nextSourceUrl: nextSourceUrl,
      );
      if (refreshed.isEmpty) return _DiscoveryWrite.skipped;
      _addLog('updated ${refreshed.join(", ")} for: $title');
      return _DiscoveryWrite.refreshed;
    }

    // No position to give it, so it is not created here. Reached only by a
    // re-sighting pass, whose whole subject is entries that already exist —
    // one that turns out not to is left for the next check to find as new,
    // rather than being appended at a place nobody chose.
    if (entryOrder == null) return _DiscoveryWrite.skipped;

    await db.upsertEntry(
      Entry(
        id: _uuid.v4(),
        collectionId: item.id,
        title: title,
        sourceUrl: url,
        urlKey: key,
        host: Uri.tryParse(url)?.host.toLowerCase() ?? '',
        // Discovery reads a list of links, not the pages themselves, so it has
        // no evidence about what any of them contains. `unknownWebContent` at
        // `low` is the honest answer, and the collection's own shape is what the
        // UI labels these with until one is actually opened and saved.
        contentKind: ContentKind.unknownWebContent.name,
        contentKindConfidence: ShapeConfidence.low.name,
        contentKindIsUserSet: false,
        // Nothing is stored, so there is no artifact yet. The column carries
        // its default rather than a claim: a discovered entry has no package,
        // and `save_status`/`content_path` are what say so.
        artifactFormat: ArtifactFormat.imageSequence.name,
        // Known to exist at the source; holds nothing locally. Everything that
        // means "readable offline" keys off contentPath + status, so this can
        // never masquerade as an offline entry.
        saveStatus: 'knownRemote',
        contentPath: null,
        savedAt: null,
        detectedAssetCount: 0,
        storedAssetCount: 0,
        nextSourceUrl: nextSourceUrl,
        entryOrder: entryOrder,
        saveError: null,
        byteSize: 0,
        entryNumber: number,
        sourceMarker: sourceMarkerFrom(title: title, url: url, number: number),
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
        discoveredAt: DateTime.now(),
        discoveryBasis: basis,
        discoveryConfidence: confidence,
      ),
    );
    return _DiscoveryWrite.written;
  }
}

/// A number as the source would print it, for a log line.
String _plainNumber(double n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

/// What one attempt to write a discovered entry did.
enum _DiscoveryWrite {
  /// A new discovered entry row exists.
  written,

  /// The entry was already known and its source-side metadata was brought up
  /// to date. **Not** a discovery: nothing new was found, so nothing counts it.
  refreshed,

  /// Nothing was written and nothing is wrong — the entry is already known and
  /// unchanged, or its address is on a restricted service. The caller carries
  /// on.
  skipped,

  /// Nothing was written because the entry's number is not supported by the
  /// evidence. The caller stops; carrying on would mean reading the rest of a
  /// source we have just shown we are reading incorrectly.
  refused,
}

/// One entry link found on a collection page.
class DiscoveredEntry {
  const DiscoveredEntry({required this.url, required this.title, this.number});

  final String url;
  final String title;
  final double? number;
}

/// Which way an entry list runs down the page.
///
/// Most sites list newest first; some list oldest first; a few are not
/// ordered coherently at all. Getting this wrong is what makes an update
/// check save entry 1 when the user wanted 386.
enum EntryListDirection { newestFirst, oldestFirst, unknown }

/// The part of a source's entry list one reading can actually vouch for.
///
/// This exists so absence can mean something. A check reads **one page**, and a
/// page is a window: paginated, latest-N, or built as the user scrolls. An
/// entry missing from a page that never covered it has not been shown to be
/// missing from the source, so the only honest statement a reading can make is
/// "between these two numbers, this is the complete list" — which is exactly
/// what this carries.
///
/// Built only by [discoverFromEntryList], and only when the reading was
/// recognisable, unambiguously ordered, free of identity concerns, not
/// truncated by a discovery bound, and able to place every entry it saw on the
/// number line. Any of those missing and there is no window at all.
class ObservedEntryWindow {
  const ObservedEntryWindow({
    required this.urlKeys,
    required this.from,
    required this.to,
    required this.openAbove,
  });

  /// Every same-collection entry link the page showed, normalised — the
  /// **complete** observation, before novelty filtering and before the
  /// `maxNew` bound. A key missing from here was missing from the page.
  final Set<String> urlKeys;

  /// The lowest position the reading covered. A hard floor, never widened:
  /// below it is where the previous page of a paginated list lives.
  final double from;

  /// The highest position the reading covered.
  final double to;

  /// Whether anything *above* [to] can be ruled out.
  ///
  /// True only for a list the page itself ran newest-first: such a list puts
  /// the newest entry at its top, so an entry newer than [to] would have had
  /// to appear above the ones that did. The one thing this assumes is that the
  /// page read is the front of that list rather than a later page of it — the
  /// same assumption the checker's novelty test already makes by treating this
  /// page as where new entries appear. `reconcileDiscoveredEntries` withdraws
  /// it whenever the library itself contradicts it.
  final bool openAbove;

  /// Would an entry numbered [number] have had to appear in this reading?
  bool covers(double number) => number >= from && (openAbove || number <= to);
}

class EntryListDiscovery {
  const EntryListDiscovery({
    required this.listRecognised,
    required this.newEntries,
    this.observedEntries = const [],
    this.knownSeen = 0,
    this.direction = EntryListDirection.unknown,
    this.orderingConfident = false,
    this.dropped = 0,
    this.concerns = const [],
    this.observedWindow,
  });

  /// Whether the page plausibly showed this collection's entry list at all.
  /// False means "fall back to the chain walk", not "up to date".
  final bool listRecognised;

  /// New entries in **save order: oldest first**, so a partial run leaves
  /// a contiguous block rather than holes.
  final List<DiscoveredEntry> newEntries;

  /// Every entry the page listed, new or already held, in the page's own
  /// order — what the source says right now, before any question of novelty.
  ///
  /// [newEntries] answers "what should be recorded"; this answers "what did
  /// the page say", and they are different questions. An entry already held is
  /// absent from the first and present here, which is what lets a check notice
  /// that the source has corrected a label since.
  final List<DiscoveredEntry> observedEntries;

  final int knownSeen;

  /// Which way the list ran, as read off the page itself.
  final EntryListDirection direction;

  /// True only when the list's own ordering was unambiguous. An empty result
  /// from a list we could not order is *not* evidence of being up to date —
  /// see the caller, which keeps walking the chain in that case.
  final bool orderingConfident;

  /// New entries found but cut by `maxNew`. Reported rather than silently
  /// dropped: the next check picks them up, and the log should say so.
  final int dropped;

  /// Entries whose number the list's own evidence contradicts. Never empty and
  /// ignorable: they are already absent from [newEntries], and a caller that
  /// finds any of these must stop rather than treat the rest as a clean
  /// reading of the page.
  final List<EntryIdentityConcern> concerns;

  /// What this reading can vouch for being *complete*, or null when it can
  /// vouch for nothing. Null is the safe answer and the common one; only a
  /// non-null window may be used to conclude that an entry is gone.
  final ObservedEntryWindow? observedWindow;
}

/// One same-collection link, with the two things ordering can be read from: the
/// number in its label and its position in the list.
class _EntryLink {
  _EntryLink({
    required this.index,
    required this.url,
    required this.key,
    required this.title,
    required this.reading,
    required this.depth,
  }) : number = reading.labelNumber ?? reading.urlNumber,
       position = reading.labelNumber ?? reading.urlNumber;

  final int index;
  final String url;
  final String key;
  final String title;

  /// Both readings of this entry's number, kept apart so they can be compared.
  /// [number] is the one discovery acts on and is exactly what
  /// `parseEntryNumber(title:, url:)` would have returned — the label's number
  /// when it has one, the address's otherwise.
  final EntryIdentityReading reading;

  final double? number;
  final int depth;

  /// Where this entry sits on the number line: its own number, or — for an
  /// unnumbered one — a value interpolated from its numbered neighbours.
  /// Null only when the list offers nothing to interpolate from.
  double? position;
}

/// Whether a link is an entry *of this collection*.
///
/// [collectionFingerprint] answers this for ordinary entries by dropping a
/// trailing entry-looking segment. It cannot for an entry whose slug is
/// just a word — `/guide/foo/extra`, `/guide/foo/side-story` — which keeps
/// its own segment and so fingerprints as a different collection. Those are
/// admitted on structure instead: exactly one segment below the collection path.
/// (What stops that from admitting `/guide/foo/comments` is the caller, which
/// only keeps an unnumbered link that sits *inside* the numbered run.)
bool _belongsToCollection(String url, String collectionKey) {
  if (collectionFingerprint(url) == collectionKey) return true;
  final path = Uri.tryParse(url)?.path;
  if (path == null) return false;
  final trailing = RegExp(r'/+$');
  final prefix = '${collectionKey.replaceAll(trailing, '')}/';
  final trimmed = path.replaceAll(trailing, '');
  if (!trimmed.startsWith(prefix)) return false;
  return !trimmed.substring(prefix.length).contains('/');
}

int _pathDepth(String url) =>
    Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).length ?? 0;

/// Read a collection page's entry list. Pure — unit tested against literal
/// probes.
///
/// Three things this has to get right, in order of how often they bite:
///
/// 1. **Newest-to-oldest lists.** The links arrive in DOM order, which is the
///    site's own ordering. That ordering is measured (not assumed) and used
///    to emit new entries oldest-first, whichever way the page runs.
/// 2. **Decimals.** `385 < 385.5 < 386`; comparisons are on the parsed
///    numbers, never on text.
/// 3. **Unnumbered entries.** `"Extra"`, `"Prologue"`, `"Side Story"` have no
///    number to compare, so they are placed by position relative to the
///    entries already held — not discarded, which is what used to happen.
///
/// "Starting from the middle" falls out of the same rule: the checkpoint is
/// the highest number already held plus the set of known URLs, so a library
/// holding 100–105 of 400 finds 106 onwards and saves upward from there.
EntryListDiscovery discoverFromEntryList(
  PageProbe probe, {
  required String collectionKey,
  required double? latestKnownNumber,
  required Set<String> knownUrlKeys,
  int maxNew = 20,
}) {
  final base = probe.url;
  final baseKey = normalizeUrl(base);
  final seen = <String>{};
  final candidates = <_EntryLink>[];

  for (final link in probe.links) {
    final resolved = resolveUrl(base, link.href);
    if (resolved == null) continue;
    if (hostOf(resolved).toLowerCase() != hostOf(base).toLowerCase()) continue;
    if (!_belongsToCollection(resolved, collectionKey)) continue;

    final key = normalizeUrl(resolved);
    // The collection page links to itself from its own header; that is not a
    // entry.
    if (key == baseKey) continue;
    if (!seen.add(key)) continue;

    candidates.add(
      _EntryLink(
        index: candidates.length,
        url: resolved,
        key: key,
        title: link.text.trim().isEmpty ? resolved : link.text.trim(),
        reading: EntryIdentityReading.read(url: resolved, label: link.text),
        depth: _pathDepth(resolved),
      ),
    );
  }

  final numbered = candidates.where((c) => c.number != null).toList();

  // An unnumbered link only counts as an entry when it sits inside the
  // numbered run and at the same URL depth. Without that, a collection page's
  // "comments" or "bookmark" link would be saved as an entry — which is
  // why these used to be dropped outright.
  final modalDepth = _modalDepth(numbered);
  final firstNumbered = numbered.isEmpty ? -1 : numbered.first.index;
  final lastNumbered = numbered.isEmpty ? -1 : numbered.last.index;
  final links = candidates.where((c) {
    if (c.number != null) return true;
    if (knownUrlKeys.contains(c.key)) return true;
    return c.depth == modalDepth &&
        c.index > firstNumbered &&
        c.index < lastNumbered;
  }).toList();

  // Give every unnumbered entry a place on the number line by interpolating
  // between its numbered neighbours in list order: a "Side Story" between
  // 386 and 385 belongs at 385.5. That is what lets the *same* comparison
  // decide novelty and ordering for numbered and unnumbered entries alike —
  // and it is immune to the shortcut links ("First Entry", "Latest") that
  // real collection pages put above their list.
  _interpolateUnnumbered(links);

  // --- which way does the list run? ---------------------------------------
  //
  // Reported, and used only to gate early stopping. Deliberately tolerant:
  // those same shortcut links break strict monotonicity on both sites this
  // project verifies against, so a majority with a clear margin is what a
  // real entry list looks like.
  var ascendingPairs = 0;
  var descendingPairs = 0;
  for (var i = 1; i < numbered.length; i++) {
    final delta = numbered[i].number!.compareTo(numbered[i - 1].number!);
    if (delta > 0) {
      ascendingPairs++;
    } else if (delta < 0) {
      descendingPairs++;
    }
  }
  final orderedPairs = ascendingPairs + descendingPairs;
  final majority = descendingPairs >= ascendingPairs
      ? descendingPairs
      : ascendingPairs;
  final decided = orderedPairs > 0 && majority >= orderedPairs * 0.8;
  final direction = !decided
      ? EntryListDirection.unknown
      : descendingPairs > ascendingPairs
      ? EntryListDirection.newestFirst
      : EntryListDirection.oldestFirst;
  // Enough entries for the majority to mean something. Two links that happen
  // to descend are a coincidence; three or more are an ordering.
  final confident =
      direction != EntryListDirection.unknown && numbered.length >= 3;

  var knownSeen = 0;
  for (final c in links) {
    if (knownUrlKeys.contains(c.key)) knownSeen++;
  }

  // --- which of them are new ----------------------------------------------
  final fresh = <_EntryLink>[];
  for (final c in links) {
    if (knownUrlKeys.contains(c.key)) continue;
    final position = c.position;
    final bool isNew;
    if (latestKnownNumber == null) {
      // Nothing to measure against: the first check reports the whole list.
      isNew = true;
    } else if (position != null) {
      // Decimal-safe by construction: 385.5 > 385, and 386 > 385.5.
      isNew = position > latestKnownNumber;
    } else {
      // Neither a number nor a numbered neighbour. "New" cannot be
      // established from a list alone, so it is not claimed.
      isNew = false;
    }
    if (isNew) fresh.add(c);
  }

  // --- oldest first, so save runs forward -------------------------------
  fresh.sort((a, b) {
    final ap = a.position;
    final bp = b.position;
    if (ap != null && bp != null) {
      final byNumber = ap.compareTo(bp);
      if (byNumber != 0) return byNumber;
    } else if (ap != null) {
      return -1;
    } else if (bp != null) {
      return 1;
    }
    return a.index.compareTo(b.index);
  });

  // Recognised = the page demonstrably lists this collection's entries: either
  // it shows entries we already hold, or several numbered same-collection
  // links. A page with neither tells us nothing and must not produce
  // "up to date".
  final recognised = knownSeen > 0 || numbered.length >= 2;

  // --- does the list contradict itself? -----------------------------------
  //
  // Asked of every entry that would be written, not only the first `maxNew` of
  // them: a contradiction beyond the bound is a fault now, and deferring it to
  // the next check would just discover it later with less context.
  //
  // A doubted candidate is *removed* as well as reported. The caller stops the
  // whole check on `concerns`, so the removal is belt and braces — but this
  // function is public and pure, and a future caller that reads `newEntries`
  // without reading `concerns` must still be unable to persist one.
  final concerns = reviewEntryIdentities(
    candidates: fresh.map((c) => c.reading).toList(),
    inView: candidates.map((c) => c.reading).toList(),
  );
  final doubted = concerns.map((c) => c.url).toSet();
  final trusted = doubted.isEmpty
      ? fresh
      : fresh.where((c) => !doubted.contains(c.url)).toList();
  final dropped = trusted.length > maxNew ? trusted.length - maxNew : 0;

  return EntryListDiscovery(
    listRecognised: recognised,
    newEntries: trusted
        .take(maxNew)
        .map(
          (c) => DiscoveredEntry(url: c.url, title: c.title, number: c.number),
        )
        .toList(),
    observedEntries: [
      for (final c in links)
        if (!doubted.contains(c.url))
          DiscoveredEntry(url: c.url, title: c.title, number: c.number),
    ],
    knownSeen: knownSeen,
    direction: direction,
    orderingConfident: confident,
    dropped: dropped,
    concerns: concerns,
    observedWindow: _observedWindow(
      links: links,
      recognised: recognised,
      confident: confident,
      direction: direction,
      dropped: dropped,
      concerns: concerns,
    ),
  );
}

/// The window this reading may be used to prove absence within, or null.
///
/// Every condition here is a way the reading could be incomplete, and each one
/// alone is enough to refuse: an unrecognised page is not this collection's
/// list, an ambiguous order means "above" and "below" have no meaning, a
/// contradicted number means the list is being read wrongly, a `maxNew`
/// truncation means the reading stopped short of what the page held, and an
/// entry that could not be placed on the number line is one the interval does
/// not describe. Returning null costs a check's worth of delay; returning a
/// window that is not true costs the user rows they were still waiting to save.
ObservedEntryWindow? _observedWindow({
  required List<_EntryLink> links,
  required bool recognised,
  required bool confident,
  required EntryListDirection direction,
  required int dropped,
  required List<EntryIdentityConcern> concerns,
}) {
  if (!recognised || !confident || dropped > 0 || concerns.isNotEmpty) {
    return null;
  }
  if (links.isEmpty) return null;

  var lowest = double.infinity;
  var highest = double.negativeInfinity;
  for (final link in links) {
    final position = link.position;
    // One unplaceable entry and the interval no longer describes the page.
    if (position == null) return null;
    if (position < lowest) lowest = position;
    if (position > highest) highest = position;
  }

  return ObservedEntryWindow(
    urlKeys: {for (final link in links) link.key},
    from: lowest,
    to: highest,
    openAbove: direction == EntryListDirection.newestFirst,
  );
}

/// Place each unnumbered entry between its numbered neighbours in list
/// order. With neighbours on both sides it lands midway between them; with
/// only one side it borrows that neighbour's number, which keeps it adjacent
/// to where the site put it. With no numbered neighbour at all it stays
/// null — and an entry with no position is never claimed as new.
void _interpolateUnnumbered(List<_EntryLink> links) {
  for (var i = 0; i < links.length; i++) {
    if (links[i].number != null) continue;
    double? before;
    for (var j = i - 1; j >= 0; j--) {
      if (links[j].number != null) {
        before = links[j].number;
        break;
      }
    }
    double? after;
    for (var j = i + 1; j < links.length; j++) {
      if (links[j].number != null) {
        after = links[j].number;
        break;
      }
    }
    links[i].position = before != null && after != null
        ? (before + after) / 2
        : (before ?? after);
  }
}

/// The URL depth most of the numbered entry links share.
int _modalDepth(List<_EntryLink> numbered) {
  if (numbered.isEmpty) return -1;
  final counts = <int, int>{};
  for (final c in numbered) {
    counts[c.depth] = (counts[c.depth] ?? 0) + 1;
  }
  var best = numbered.first.depth;
  for (final entry in counts.entries) {
    if (entry.value > (counts[best] ?? 0)) best = entry.key;
  }
  return best;
}
