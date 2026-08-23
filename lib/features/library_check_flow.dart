/// Checking every Collection at once.
///
/// **Why this file exists.** V1 called this *"many collections, one visible
/// operation"* and it went out in two commits: the surface with the V1 library
/// screens, the engine 34 minutes later. The precondition each was deleted
/// under said nothing about it — one was *"new library UX passes widget tests
/// and the reader opens through OfflineCopy"*, the other *"source-scoped
/// discovery green on fixtures"*, which is a per-Collection criterion by
/// construction. No lane replaced it and nothing noticed, while five documents
/// went on promising it.
///
/// **It is a repetition, never a second checker.** Every Collection goes
/// through the same [CheckController] a single check uses, with the same
/// limits and the same preferred-Source rule, one at a time. Nothing here
/// reads a page, decides an identity, or knows what a listing looks like.
///
/// Four rules it carries:
///
/// * **Bounded by the library, not by a crawl.** It visits the Collections the
///   user follows and stops. There is no depth, no discovery of new sites, and
///   no site it was not already told about.
/// * **Visible and stoppable, like every other thing that drives the
///   Browser.** It publishes what it is on, and a stop is asked between
///   Collections — never mid-read.
/// * **Ineligible is an answer.** An archived Collection, one with no site, one
///   whose site is on a service this app does not read from, and one with
///   several sites and no preference are each *skipped with a reason*, not
///   silently passed over.
/// * **It downloads nothing.** It is the same metadata reading a single check
///   is, repeated. What it finds becomes new Entries in the library, which the
///   user may then choose to download.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drift/drift.dart' show OrderingTerm;

import '../data/collection_repository.dart';
import '../data/schema.dart';
import '../domain/collection.dart';
import '../recognition/check.dart';
import '../save/capture_policy.dart';
import 'check_controller.dart';
import 'check_state.dart';

/// Why a Collection was not checked.
enum LibraryCheckSkip {
  /// Following has stopped, so there is nothing to keep current (V2-D13).
  archived,

  /// No site is recorded for it.
  noSource,

  /// Published on several sites with none preferred — which one to read is
  /// the user's answer, never this file's.
  noPreferredSource,

  /// Its site is one this app does not read from.
  restricted,
}

/// What one Collection came to in a library-wide check.
@immutable
class LibraryCheckEntry {
  const LibraryCheckEntry({
    required this.collectionId,
    required this.name,
    this.found = 0,
    this.skip,
    this.failed = false,
  });

  final String collectionId;
  final String name;

  /// New Entries this Collection gained.
  final int found;

  /// Set when it was not checked at all.
  final LibraryCheckSkip? skip;

  /// Checked, but concluded nothing.
  final bool failed;

  bool get hasNews => found > 0;
}

/// What the whole pass came to.
@immutable
class LibraryCheckReport {
  const LibraryCheckReport({required this.entries, required this.stopped});

  final List<LibraryCheckEntry> entries;

  /// True when the user stopped it before it reached the end.
  final bool stopped;

  Iterable<LibraryCheckEntry> get checked =>
      entries.where((e) => e.skip == null);
  Iterable<LibraryCheckEntry> get withNews => entries.where((e) => e.hasNews);
  Iterable<LibraryCheckEntry> get skipped =>
      entries.where((e) => e.skip != null);
  Iterable<LibraryCheckEntry> get failed => entries.where((e) => e.failed);

  int get newEntries => withNews.fold(0, (total, entry) => total + entry.found);
  int get upToDate => checked.where((e) => !e.hasNews && !e.failed).length;
}

/// Says what the pass came to, in one sentence.
///
/// The point of checking everything is to make new reading visible, so the
/// count of Collections *worth opening* leads. Nothing here is a per-Collection
/// report: the rows carry their own state (`check_state.dart`), which is where
/// a user looks for which ones.
String libraryCheckSentence(LibraryCheckReport report) {
  final checked = report.checked.length;
  if (checked == 0) {
    final skipped = report.skipped.length;
    if (skipped == 0) return 'There is nothing in your library to check yet.';
    return skipped == 1
        ? 'The one collection in your library could not be checked.'
        : 'None of the $skipped collections in your library could be checked.';
  }

  final lead = report.stopped
      ? 'Stopped after $checked of them.'
      : checked == 1
      ? 'Checked 1 collection.'
      : 'Checked $checked collections.';

  final parts = <String>[];
  if (report.newEntries > 0) {
    final entries = report.newEntries == 1
        ? '1 new entry'
        : '${report.newEntries} new entries';
    final across = report.withNews.length == 1
        ? '1 collection'
        : '${report.withNews.length} collections';
    parts.add('$entries across $across');
  }
  if (report.upToDate > 0) parts.add('${report.upToDate} up to date');
  final trouble = report.failed.length + report.skipped.length;
  if (trouble > 0) {
    parts.add(trouble == 1 ? '1 needs attention' : '$trouble need attention');
  }
  return parts.isEmpty ? lead : '$lead ${parts.join(' · ')}.';
}

/// Runs the same check over every Collection the user follows.
class LibraryCheckController extends ChangeNotifier {
  LibraryCheckController({
    required this._check,
    required this._collections,
    required this._db,
    required this._state,
    Clock? now,
  }) : _now = now ?? DateTime.now;

  final CheckController _check;
  final CollectionRepository _collections;
  final LibraryDatabase _db;
  final CheckStateStore _state;
  final DateTime Function() _now;

  bool _running = false;
  bool _stopRequested = false;
  int _total = 0;
  int _done = 0;
  String _currentName = '';
  LibraryCheckReport? _report;

  bool get isRunning => _running;

  /// How many Collections this pass will visit.
  int get total => _total;

  /// How many it has finished with, skips included.
  int get done => _done;

  /// The Collection being read right now, for whoever is drawing it.
  String get currentName => _currentName;

  /// The last completed pass, or null before the first.
  LibraryCheckReport? get report => _report;

  /// Ask it to stop. Taken between Collections: the one being read finishes.
  void stop() {
    if (!_running) return;
    _stopRequested = true;
    notifyListeners();
  }

  void clearReport() {
    if (_report == null) return;
    _report = null;
    notifyListeners();
  }

  /// Check everything in the library, one Collection at a time.
  Future<LibraryCheckReport?> run({
    SourceCheckLimits limits = const SourceCheckLimits(
      maxPages: 1,
      maxNewEntries: 50,
    ),
  }) async {
    if (_running) return null;
    _running = true;
    _stopRequested = false;
    _done = 0;
    _report = null;

    final all = await _allCollections();
    _total = all.length;
    _currentName = '';
    notifyListeners();

    final entries = <LibraryCheckEntry>[];
    try {
      for (final collection in all) {
        if (_stopRequested) break;
        _currentName = collection.name;
        notifyListeners();

        final skip = await _skipReasonFor(collection);
        if (skip != null) {
          entries.add(
            LibraryCheckEntry(
              collectionId: collection.id,
              name: collection.name,
              skip: skip,
            ),
          );
          _done++;
          notifyListeners();
          continue;
        }

        _state.beginCheck(collection.id);
        final outcome = await _check.run(collection.id, limits: limits);
        _state.recordCheck(collection.id, outcome, at: _now());
        entries.add(
          LibraryCheckEntry(
            collectionId: collection.id,
            name: collection.name,
            found: outcome?.newEntryIds.length ?? 0,
            failed: outcome == null || outcome.stopReason != null,
          ),
        );
        _done++;
        notifyListeners();
      }
    } finally {
      _report = LibraryCheckReport(
        entries: List.unmodifiable(entries),
        stopped: _stopRequested,
      );
      _running = false;
      _currentName = '';
      notifyListeners();
    }
    return _report;
  }

  /// Every Collection in the library, in name order.
  ///
  /// Read straight from the table rather than walked Folder by Folder: which
  /// Folder something sits in is organisation, and a check is about the work.
  Future<List<CollectionRow>> _allCollections() {
    return (_db.select(
      _db.collections,
    )..orderBy([(c) => OrderingTerm.asc(c.name)])).get();
  }

  /// Whether this Collection can be checked at all, and why not.
  Future<LibraryCheckSkip?> _skipReasonFor(CollectionRow collection) async {
    if (collection.lifecycle != CollectionLifecycle.active.name) {
      return LibraryCheckSkip.archived;
    }
    final sources = await _collections.sourcesOf(collection.id);
    if (sources.isEmpty) return LibraryCheckSkip.noSource;

    final preferredId = collection.preferredSourceId;
    if (preferredId == null && sources.length > 1) {
      return LibraryCheckSkip.noPreferredSource;
    }
    final source = preferredId == null
        ? sources.first
        : sources.firstWhere(
            (s) => s.id == preferredId,
            orElse: () => sources.first,
          );
    // Host-first, before anything opens — the same order a single check uses.
    if (isRestrictedCaptureHost(source.host)) {
      return LibraryCheckSkip.restricted;
    }
    return null;
  }
}

/// A time source, so a pass can be tested without a real clock.
typedef Clock = DateTime Function();

/// The library-wide check, where one is attached. Null on surfaces that have
/// no Browser to drive.
final libraryCheckProvider = Provider<LibraryCheckController?>((ref) => null);
