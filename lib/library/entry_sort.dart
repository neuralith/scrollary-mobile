/// How one Collection's Entries are ordered on screen.
///
/// **This file is presentation and nothing else.** It reads `ordinal`; it can
/// never write one. That distinction is the whole reason it exists as its own
/// module rather than as a comparator inside a view model: an `ordinal` is
/// identity — it is what cross-source merge keys on (V2-D16), what the update
/// check measures novelty against, and what the server arbitrates placement
/// for — while the order a list happens to be drawn in is a preference someone
/// can change twice in a minute. Sorting a list must not be able to reach the
/// first thing, so nothing here returns anything but a comparison.
///
/// The same rule is why [EntrySortFacts.number] may come from a Location's
/// `source_number`. That number is evidence of what a site printed and is
/// deliberately *not* an ordinal (V2-D15): a Collection whose basis is not
/// `explicitNumericIndex` never gets positions written from it. Reading it to
/// decide which of two rows is drawn first borrows none of that meaning, and
/// it is what lets a Collection the app could not number still be shown in the
/// order its own site printed, rather than alphabetically — where "Part 10"
/// sorts before "Part 9".
///
/// **Unknowns sort last in both directions.** Reversing a list should reverse
/// the entries that have an answer, not promote the ones that do not: a
/// descending sort that opened with every undated Entry would bury the newest
/// thing, which is the one question descending was asked to answer.
library;

import '../domain/collection.dart';

/// What a list of Entries is ordered by.
enum EntrySortField {
  /// The number the sequence runs on: an Entry's `ordinal` where it has one,
  /// and otherwise the number its source printed. Never written back.
  number,

  /// The date the source said the page was published.
  publishDate,

  /// When this address first entered the library — a Location's
  /// `discovered_at`. The floor: it exists for every Entry that has ever been
  /// seen anywhere, which is why nothing below it is needed.
  addedDate;

  /// What the control calls it.
  String get label => switch (this) {
    EntrySortField.number => 'Number',
    EntrySortField.publishDate => 'Publish date',
    EntrySortField.addedDate => 'Date added',
  };

  /// What the control says underneath, in the vocabulary of the thing being
  /// ordered rather than of the column it came from.
  String get explanation => switch (this) {
    EntrySortField.number => 'The order this collection is numbered in.',
    EntrySortField.publishDate => 'When each entry was published.',
    EntrySortField.addedDate => 'When each entry reached your library.',
  };

  static EntrySortField? fromName(String? name) {
    for (final field in EntrySortField.values) {
      if (field.name == name) return field;
    }
    return null;
  }
}

/// Which way round.
enum EntrySortDirection {
  ascending,
  descending;

  EntrySortDirection get flipped => this == EntrySortDirection.ascending
      ? EntrySortDirection.descending
      : EntrySortDirection.ascending;

  /// Named for what the user is choosing between, per field: "1 → 99" says
  /// more than "ascending", and "Newest first" says more than "descending".
  String labelFor(EntrySortField field) => switch ((field, this)) {
    (EntrySortField.number, EntrySortDirection.ascending) => 'Lowest first',
    (EntrySortField.number, EntrySortDirection.descending) => 'Highest first',
    (_, EntrySortDirection.ascending) => 'Oldest first',
    (_, EntrySortDirection.descending) => 'Newest first',
  };

  static EntrySortDirection? fromName(String? name) {
    for (final direction in EntrySortDirection.values) {
      if (direction.name == name) return direction;
    }
    return null;
  }
}

/// One Collection's sort: a field and a direction.
class EntrySort {
  const EntrySort(this.field, [this.direction = EntrySortDirection.ascending]);

  final EntrySortField field;
  final EntrySortDirection direction;

  bool get isAscending => direction == EntrySortDirection.ascending;

  EntrySort withField(EntrySortField field) => EntrySort(field, direction);

  EntrySort withDirection(EntrySortDirection direction) =>
      EntrySort(field, direction);

  EntrySort get flipped => EntrySort(field, direction.flipped);

  /// The stored form. Two names and a separator, so a value written by a build
  /// that knew a field this one does not reads back as null rather than as
  /// something else — [parseEntrySort] refuses what it cannot name.
  String get storedValue => '${field.name}:${direction.name}';

  @override
  bool operator ==(Object other) =>
      other is EntrySort &&
      other.field == field &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);

  @override
  String toString() => storedValue;
}

/// Reads back what [EntrySort.storedValue] wrote.
///
/// Null for anything this build cannot name — an unset key, a field or a
/// direction it does not have, a value some other writer left. The caller then
/// resolves the default, which is always a sort the Collection's own data
/// supports. An unreadable preference must never resolve to a *value*: it
/// would pin a list to an order nothing chose.
EntrySort? parseEntrySort(String? stored) {
  if (stored == null) return null;
  final parts = stored.split(':');
  if (parts.length != 2) return null;
  final field = EntrySortField.fromName(parts[0]);
  final direction = EntrySortDirection.fromName(parts[1]);
  if (field == null || direction == null) return null;
  return EntrySort(field, direction);
}

/// What one Entry offers a sort, and nothing else about it.
///
/// A plain value so the comparator can be tested without a database, a widget
/// or a row: every rule in this file is a rule about these four fields.
class EntrySortFacts {
  const EntrySortFacts({
    this.number,
    this.publishedAt,
    this.addedAt,
    this.label = '',
  });

  /// `ordinal ?? source_number` — resolved by the caller, because which of the
  /// two a row has is a fact about the row and not a judgement.
  final double? number;

  final DateTime? publishedAt;

  /// Null only for an Entry with no Location at all, which is possible and is
  /// why the floor is still allowed to be missing.
  final DateTime? addedAt;

  /// The tiebreak, and the one that makes an order total: two Entries with the
  /// same date, or neither of them dated, still have to be drawn in some order
  /// and it should be the same one on every rebuild.
  final String label;

  DateTime? dateFor(EntrySortField field) => switch (field) {
    EntrySortField.publishDate => publishedAt,
    EntrySortField.addedDate => addedAt,
    EntrySortField.number => null,
  };

  /// Whether this Entry can answer [field] at all.
  bool has(EntrySortField field) => switch (field) {
    EntrySortField.number => number != null,
    EntrySortField.publishDate => publishedAt != null,
    EntrySortField.addedDate => addedAt != null,
  };
}

/// Which fields [facts] can actually be sorted by, in menu order.
///
/// A field nobody can answer is not offered: a Collection where no site ever
/// printed a date has no *Publish date* order to be in, and a control that
/// listed one would be offering to rearrange a list into the order it is
/// already in. [EntrySortField.addedDate] is included whenever any Entry has
/// one, which in practice is always — an Entry reaches the library through an
/// address, and an address is stamped when it is stored.
List<EntrySortField> availableEntrySortFields(Iterable<EntrySortFacts> facts) {
  final available = <EntrySortField>[];
  for (final field in EntrySortField.values) {
    if (facts.any((f) => f.has(field))) available.add(field);
  }
  return available;
}

/// The order a Collection nobody has given an instruction about is drawn in.
///
/// The ladder, in the product's own words: a reliably numbered Collection is
/// numbered; otherwise publish date if there is one to use; otherwise the date
/// it arrived.
///
/// "Reliably numbered" is the model's existing answer and not a new one —
/// [OrderingBasis.explicitNumericIndex] is precisely the basis under which the
/// app is willing to write positions at all (V2-D16), so a Collection that
/// carries it *and* has numbers to show is the one case where the sequence is
/// the source's own. Every other Collection may still be sorted by number by
/// hand, on `source_number`; it is simply not what it opens as, because
/// nothing has vouched for those numbers being a sequence.
///
/// Always returns a field in [available] when that list is non-empty, so the
/// resolved default is never one the control cannot show as selected.
EntrySort defaultEntrySort({
  required OrderingBasis basis,
  required List<EntrySortField> available,
}) {
  if (available.isEmpty) return const EntrySort(EntrySortField.addedDate);
  if (basis.supportsCrossSourceMerge &&
      available.contains(EntrySortField.number)) {
    return const EntrySort(EntrySortField.number);
  }
  for (final field in const [
    EntrySortField.publishDate,
    EntrySortField.addedDate,
  ]) {
    if (available.contains(field)) return EntrySort(field);
  }
  return EntrySort(available.first);
}

/// [stored] when this Collection's data still supports it, and the default
/// otherwise.
///
/// A remembered choice is not a promise the data will keep: a Collection sorted
/// by publish date whose only dated Entry is removed can no longer honour it.
/// Falling back to the default beats drawing a list ordered by a field nothing
/// in it has, and the stored preference is deliberately **not** rewritten — the
/// user's answer stands, and is honoured again the moment a dated Entry
/// returns.
EntrySort resolveEntrySort({
  required EntrySort? stored,
  required OrderingBasis basis,
  required List<EntrySortField> available,
}) {
  if (stored != null && available.contains(stored.field)) return stored;
  return defaultEntrySort(basis: basis, available: available);
}

/// Compare two Entries under [sort].
///
/// Three tiers, and the middle one is the load-bearing one:
///
/// 1. Both answer the field, and differently — the comparison, reversed for a
///    descending sort.
/// 2. **One answers and one does not — the one that answers comes first, in
///    both directions.** An unknown is not a low value or a high one; it is
///    the absence of one, and it belongs at the end of the list either way.
/// 3. Neither answers, or they answer identically — the label, ascending,
///    always. It is not a fourth sort option, it is what stops a list from
///    shuffling between rebuilds.
int compareEntriesBySort(EntrySort sort, EntrySortFacts a, EntrySortFacts b) {
  final ordered = _compareField(sort.field, a, b);
  if (ordered != 0) return sort.isAscending ? ordered : -ordered;
  final present = _comparePresence(sort.field, a, b);
  if (present != 0) return present;
  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

/// The field's own comparison, for the pair that both have it. Zero covers
/// "equal" and "at least one is missing" alike; [_comparePresence] separates
/// those two afterwards, where the direction can no longer flip the answer.
int _compareField(EntrySortField field, EntrySortFacts a, EntrySortFacts b) {
  if (field == EntrySortField.number) {
    final x = a.number;
    final y = b.number;
    return x == null || y == null ? 0 : x.compareTo(y);
  }
  final x = a.dateFor(field);
  final y = b.dateFor(field);
  return x == null || y == null ? 0 : x.compareTo(y);
}

int _comparePresence(EntrySortField field, EntrySortFacts a, EntrySortFacts b) {
  final hasA = a.has(field);
  final hasB = b.has(field);
  if (hasA == hasB) return 0;
  return hasA ? -1 : 1;
}
