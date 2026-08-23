/// What the last check of each Collection came to.
///
/// **Why this file exists.** `checkLook()` has always built exactly the chips
/// this answers — *Not checked yet · Checking · 3 new · Checked ‹when› · Check
/// failed* — and the V1 surface that rendered them was deleted with the V1
/// library screens. The function survived with no caller, so a Collection has
/// been unable to say whether it had ever been checked, or what came of it.
///
/// **Session memory, not a column.** V1 persisted four columns per collection.
/// V2 keeps this for as long as the app is running and no longer, for the same
/// reason V2-D43 keeps collapsed Folders in memory: the schema is frozen at
/// version 1 with no migration path, and a check is cheap to repeat. *Not
/// checked yet* is the honest state on a fresh launch, and it is exactly what
/// a user who has not checked since launching sees.
///
/// Never gated: what the device did is not a paid feature
/// (docs/V2_CAPABILITY_PARITY.md).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/material.dart';

import '../recognition/check.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// One Collection's last check, as the library shows it.
@immutable
class CollectionCheckState {
  const CollectionCheckState({
    this.checking = false,
    this.failed = false,
    this.checkedAt,
    this.newEntryIds = const {},
  });

  /// A check is reading this Collection's site right now.
  final bool checking;

  /// The last check could not conclude anything.
  final bool failed;

  /// When the last check that *concluded something* finished. Null until one
  /// has — a refusal leaves this alone, because a check that could not read
  /// the site did not check it.
  final DateTime? checkedAt;

  /// The Entries the last check brought in.
  ///
  /// **Library state, not download state.** A new Entry belongs to the
  /// Collection whether or not this device ever holds bytes for it; the ids
  /// are kept so the Collection can mark them, not so they can be queued
  /// (PRODUCT.md §2.3 — known, in the library, downloaded and read are four
  /// independent facts).
  final Set<String> newEntryIds;

  int get newCount => newEntryIds.length;

  /// Whether this Collection is worth opening because of its last check.
  bool get hasNews => newEntryIds.isNotEmpty;
}

/// Every Collection's last check, for this run of the app.
class CheckStateStore extends ChangeNotifier {
  final Map<String, CollectionCheckState> _byCollection = {};

  CollectionCheckState of(String collectionId) =>
      _byCollection[collectionId] ?? const CollectionCheckState();

  /// A check has started. Keeps whatever the previous one concluded, so the
  /// row does not blank while it reads.
  void beginCheck(String collectionId) {
    final previous = of(collectionId);
    _byCollection[collectionId] = CollectionCheckState(
      checking: true,
      checkedAt: previous.checkedAt,
      newEntryIds: previous.newEntryIds,
    );
    notifyListeners();
  }

  /// A check has finished. [outcome] null means it never ran — the Browser was
  /// busy, or there was no site to read — which is not a failure of the
  /// Collection and leaves its state alone.
  void recordCheck(
    String collectionId,
    SourceCheckOutcome? outcome, {
    required DateTime at,
  }) {
    if (outcome == null) {
      final previous = of(collectionId);
      _byCollection[collectionId] = CollectionCheckState(
        checkedAt: previous.checkedAt,
        newEntryIds: previous.newEntryIds,
      );
      notifyListeners();
      return;
    }

    // A reading that vouches for nothing is not a check that succeeded, and
    // must not stamp a time — "Checked 2 minutes ago" over a site that would
    // not load is the same lie the old single sentence told.
    final concluded = outcome.stopReason == null;
    final found = outcome.newEntryIds.toSet();
    _byCollection[collectionId] = CollectionCheckState(
      failed: !concluded && found.isEmpty,
      checkedAt: concluded ? at : of(collectionId).checkedAt,
      newEntryIds: found.isNotEmpty
          ? found
          : (concluded ? const {} : of(collectionId).newEntryIds),
    );
    notifyListeners();
  }

  /// The user has seen what the check found.
  void clearNews(String collectionId) {
    final previous = of(collectionId);
    if (previous.newEntryIds.isEmpty) return;
    _byCollection[collectionId] = CollectionCheckState(
      checking: previous.checking,
      failed: previous.failed,
      checkedAt: previous.checkedAt,
    );
    notifyListeners();
  }
}

/// The one store, for this run of the app.
final checkStateProvider = Provider<CheckStateStore>((ref) {
  final store = CheckStateStore();
  ref.onDispose(store.dispose);
  return store;
});

/// The chip a Collection row wears, or nothing when it has never been checked
/// and nothing is happening to it.
///
/// Absent rather than *Not checked yet* on a quiet library: a badge on every
/// row on every launch is one nobody reads. It appears the moment a check
/// starts and stays for the rest of the session.
class CollectionCheckChip extends ConsumerStatefulWidget {
  const CollectionCheckChip({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<CollectionCheckChip> createState() =>
      _CollectionCheckChipState();
}

class _CollectionCheckChipState extends ConsumerState<CollectionCheckChip> {
  late final CheckStateStore _store;

  @override
  void initState() {
    super.initState();
    _store = ref.read(checkStateProvider);
    _store.addListener(_onChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _store.of(widget.collectionId);
    if (!state.checking && !state.failed && state.checkedAt == null) {
      return const SizedBox.shrink();
    }
    final palette = AppPalette.of(context);
    final look = checkLook(
      palette: palette,
      checking: state.checking,
      failed: state.failed,
      checkedAt: state.checkedAt,
      newCount: state.newCount,
      checkedLabel: state.checkedAt == null
          ? ''
          : checkedAgoLabel(state.checkedAt!),
    );
    return StatusChip(
      key: ValueKey('collectionCheckChip-${widget.collectionId}'),
      icon: look.icon,
      label: look.label,
      bg: look.bg,
      fg: look.fg,
      border: look.border,
    );
  }
}

/// How long ago a check was, in the shortest true words.
///
/// Coarse on purpose: a Collection row is not a clock, and "3 minutes ago"
/// versus "4 minutes ago" is not a difference anyone acts on.
String checkedAgoLabel(DateTime checkedAt, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(checkedAt);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}
