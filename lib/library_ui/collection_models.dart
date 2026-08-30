/// View models for one Collection and for one Entry row (roadmap D3).
///
/// Two product rules are carried here rather than in a widget, because a
/// widget is the wrong place to be tempted:
///
/// 1. **Availability is a row state, never a filter.** An Entry is listed
///    because it is in the library; whether this device holds bytes for it is
///    one boolean on the row (PRODUCT.md §2.3). There is no second list, and
///    nothing here can produce one.
/// 2. **Nothing invents a label.** The noun comes from
///    `lib/library/entry_labels.dart` and nowhere else, and an `ordinal` is a
///    position in a sequence — not a licence to print "Part 12".
library;

import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/entry.dart';
import '../domain/reading_state.dart';
import '../library/entry_labels.dart';
import '../library/entry_presentation.dart';
import '../library/entry_sort.dart';

/// The vocabulary this UI speaks about Entries.
///
/// `kPlainEntryLabels` — *item* — rather than the `savedItem` fallback: V2 has
/// no stored content shape to read a confident noun from, and in this product
/// "saved" is heard as "downloaded", which is the exact conflation
/// PRODUCT.md §1.2 exists to correct. An Entry is in the library because the
/// user wants to read it.
const libraryEntryLabels = kPlainEntryLabels;

/// One Entry as a row: what to call it, whether it has been read, and whether
/// this device holds a copy.
class EntryRowView {
  const EntryRowView({
    required this.row,
    required this.status,
    required this.availableOffline,
    required this.label,
    this.progress = 0,
    this.sourceLabel,
    this.sourceNumber,
    this.publishedAt,
    this.addedAt,
    this.collectionName,
    this.subtitle,
  });

  factory EntryRowView.from({
    required EntryRow row,
    required ReadStatus status,
    required bool availableOffline,
    String? sourceLabel,
    double? sourceNumber,
    DateTime? publishedAt,
    DateTime? addedAt,
    String? collectionName,
    double progress = 0,
    EntryContext context = EntryContext.withinCollection,
  }) {
    final shown = entryPresentation(
      context: context,
      labels: libraryEntryLabels,
      ordinal: row.ordinal,
      title: row.title,
      sourceLabel: sourceLabel,
      collectionName: collectionName,
    );
    return EntryRowView(
      row: row,
      status: status,
      availableOffline: availableOffline,
      label: shown.primary,
      subtitle: shown.secondary,
      progress: progress,
      sourceLabel: sourceLabel,
      sourceNumber: sourceNumber,
      publishedAt: publishedAt,
      addedAt: addedAt,
      collectionName: collectionName,
    );
  }

  final EntryRow row;
  final ReadStatus status;

  /// An active OfflineCopy exists **on this device** (I13). Never a reason to
  /// hide, sort or group a row.
  final bool availableOffline;

  /// The Entry's identity on a row: its position inside a Collection, its
  /// name anywhere it has one, and never the work's name repeated.
  final String label;

  /// The quieter line under [label] — what the title still says once the
  /// position and the work's name are out of it. Null far more often than not.
  final String? subtitle;

  /// What a site printed for this Entry, kept as evidence. Not what the row
  /// draws; what *Entry details* shows.
  final String? sourceLabel;

  /// The number a site printed for this Entry, from its earliest active
  /// Location. Evidence, exactly like [sourceLabel] — **never an `ordinal`**
  /// (V2-D15). It is read here for one purpose: so a Collection the app was
  /// not willing to number can still be *drawn* in the order its own site
  /// printed. Nothing on this row can write it back.
  final double? sourceNumber;

  /// When the source said this Entry was published, where one said so. Null
  /// for every Entry nobody has downloaded yet and for every site that prints
  /// no date, which is ordinary and permanent.
  final DateTime? publishedAt;

  /// When this Entry reached the library: its earliest active Location's
  /// `discovered_at`. Null only for an Entry that has no address at all.
  final DateTime? addedAt;

  /// The Collection this Entry belongs to, when it belongs to one. Held for
  /// the details surface and for the surfaces that have to name it.
  final String? collectionName;

  /// How far through this Entry a reading got, as it was measured against the
  /// rendering it happened on — 0 when nothing has been measured.
  ///
  /// A Measurement is scoped to `(entry, source)` and there may be several;
  /// what a row shows is the furthest any of them reached, because "how far
  /// through this have I got" is a question about the Entry and the user does
  /// not think of it per rendering. Never a claim about a download: an Entry
  /// with no copy on this device has progress exactly when somebody read it
  /// somewhere.
  final double progress;

  /// What the row draws. A completed Entry is 100% read because its status
  /// says so — the rule enforced on write and again here on display (D39).
  double get readFraction =>
      status == ReadStatus.completed ? 1 : progress.clamp(0.0, 1.0);

  String get id => row.id;

  /// A position the app could not establish is a real, visible state — not an
  /// error, and not something to guess a number for (V2-D16).
  bool get needsPlacement => row.placement == Placement.unplaced.name;

  /// Everything a sort is allowed to know about this row.
  ///
  /// `ordinal ?? sourceNumber` is resolved here, once, and the precedence is
  /// the only one that could be right: an `ordinal` is the position the
  /// library established and a `sourceNumber` is what one site printed, so
  /// where both exist the library's own answer wins. Reading the second one
  /// does not make it the first — see `library/entry_sort.dart`.
  EntrySortFacts get sortFacts => EntrySortFacts(
    number: row.ordinal ?? sourceNumber,
    publishedAt: publishedAt,
    addedAt: addedAt,
    label: label,
  );

  String get statusLabel => switch (status) {
    ReadStatus.unread => 'Unread',
    ReadStatus.reading => 'Reading',
    ReadStatus.completed => 'Read',
  };
}

/// What a row prints for one Entry, wherever it is being drawn.
///
/// One line of forwarding to `library/entry_presentation.dart`, which is where
/// the rule lives so that a global surface and this one cannot disagree about
/// it. The Entry's own title is the name the library holds for it; a
/// Location's `source_label` is evidence of what one site printed and stands
/// in only when the Entry has none.
String entryRowLabel(
  EntryRow row, {
  String? sourceLabel,
  String? collectionName,
  EntryContext context = EntryContext.withinCollection,
}) => entryPresentation(
  context: context,
  labels: libraryEntryLabels,
  ordinal: row.ordinal,
  title: row.title,
  sourceLabel: sourceLabel,
  collectionName: collectionName,
).primary;

/// One Collection and its **one** Entry list.
///
/// The list is split for presentation only: unplaced Entries are shown last,
/// under their own heading, so the sequence above them stays true (O-B). Both
/// halves are the same rows, drawn the same way, in the same list.
///
/// **The split is about the numeric sequence, so it appears only when the list
/// is in it.** "Where this sits in the collection is not known" is a statement
/// about an `ordinal`, and it is worth making while the rows above are ordered
/// by one. Under a date sort nothing on screen is claiming a position at all:
/// every Entry has the date being sorted on, or sorts last for lacking it, and
/// holding some of them back under a heading about placement would be
/// answering a question the list is not asking. They merge into the one list,
/// still carrying their placement badge, still one tap from being placed.
class CollectionView {
  const CollectionView({
    required this.collection,
    required this.entries,
    required this.needsPlacement,
    this.sort = const EntrySort(EntrySortField.number),
    this.available = const [EntrySortField.number],
  });

  factory CollectionView.from({
    required CollectionRow collection,
    required List<EntryRowView> entries,
    EntrySort? sort,
    List<EntrySortField>? available,
  }) {
    final offered =
        available ??
        availableEntrySortFields([for (final e in entries) e.sortFacts]);
    final applied =
        sort ??
        defaultEntrySort(
          basis: OrderingBasis.values.byName(collection.orderingBasis),
          available: offered,
        );
    int bySort(EntryRowView a, EntryRowView b) =>
        compareEntriesBySort(applied, a.sortFacts, b.sortFacts);

    if (applied.field != EntrySortField.number) {
      return CollectionView(
        collection: collection,
        entries: [...entries]..sort(bySort),
        needsPlacement: const [],
        sort: applied,
        available: offered,
      );
    }
    final placed = [
      for (final e in entries)
        if (!e.needsPlacement) e,
    ]..sort(bySort);
    final unplaced = [
      for (final e in entries)
        if (e.needsPlacement) e,
    ]..sort(bySort);
    return CollectionView(
      collection: collection,
      entries: placed,
      needsPlacement: unplaced,
      sort: applied,
      available: offered,
    );
  }

  final CollectionRow collection;

  /// Entries with a position, in it.
  final List<EntryRowView> entries;

  /// Entries whose position in this Collection is not known. Empty under a
  /// date sort, where placement is not what the list is ordered by.
  final List<EntryRowView> needsPlacement;

  /// The order these lists are in — the user's remembered choice where there
  /// is one, and otherwise the one this Collection's own data earns.
  final EntrySort sort;

  /// The orders this Collection could be put in, in menu order. Never empty in
  /// practice, and the control draws exactly this.
  final List<EntrySortField> available;

  String get name => collection.name;

  /// A Collection in the library is followed; `archived` is how following
  /// stops, and it preserves everything (V2-D13).
  bool get archived =>
      collection.lifecycle == CollectionLifecycle.archived.name;

  int get total => entries.length + needsPlacement.length;

  int get unread => [
    ...entries,
    ...needsPlacement,
  ].where((e) => e.status != ReadStatus.completed).length;

  /// `12 items · 4 unread`. The count goes through the label file so no screen
  /// ever hand-rolls a plural.
  String get extentLine {
    final extent = libraryEntryLabels.count(total);
    return unread == 0 ? extent : '$extent · $unread unread';
  }
}
