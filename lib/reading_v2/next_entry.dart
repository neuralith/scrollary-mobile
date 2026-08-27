/// *What does reading on from here actually lead to?* — asked once, answered
/// in one place.
///
/// The reader has three ways to ask for the next Entry: the control in the
/// bottom chrome, the end of an Entry the reader has finished, and the pull-up
/// from the bottom edge. All three ask **this**, because the rules they would
/// otherwise each carry are the same three rules:
///
///  1. **The next Entry is the Collection's own next**, by the Collection's
///     order — not the next URL, not the next id, and not the next thing this
///     device happens to hold bytes for. Same rule
///     `lib/reading_v2/forward_transition.dart` decides a forward move by, and
///     the same one `readerNeighbours` draws the bottom bar from.
///  2. **A downloaded copy is a property of this device, never of the Entry.**
///     An Entry with no copy here is an ordinary first-class library item; it
///     is simply not readable *offline*, and its Source still is.
///  3. **"Nothing follows this" is a fact about the library right now**, never
///     about the work. A Collection whose site has published more is a
///     Collection that has not been checked lately, and saying "that is the
///     end" would be a claim this app has no evidence for.
///
/// What this file does **not** do: open anything, ask anything, or navigate.
/// It reads rows and returns which of the four answers is true, so the surface
/// that asked can put the right question in front of the user. Deciding what a
/// move *means* — completion, the Collection's cleanup rule — stays with
/// `ForwardTransitionService`, which is a different question asked at a
/// different moment.
library;

import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/offline_copy_repository.dart';
import '../data/schema.dart';
import '../domain/location.dart';

/// The Entries of [collectionId] that have a position, in the Collection's own
/// order.
///
/// The one definition of "the reading order", so the bottom bar's neighbours,
/// a forward move and a next-Entry request cannot disagree about what follows
/// what. Unplaced Entries are deliberately absent: an Entry with no ordinal has
/// no position in the sequence to be read on from, which is what the NEEDS
/// PLACEMENT section on the Collection screen exists to resolve.
Future<List<EntryRow>> placedEntriesOf(
  EntryRepository entries,
  String collectionId,
) async => [
  for (final entry in await entries.entriesOf(collectionId))
    if (entry.ordinal != null) entry,
];

/// Where reading on from one Entry leads. Four answers, and no fifth.
sealed class NextEntryOutcome {
  const NextEntryOutcome();
}

/// The next Entry, and this device holds its bytes: it opens in the reader.
final class NextEntryDownloaded extends NextEntryOutcome {
  const NextEntryDownloaded(this.entryId);

  final String entryId;
}

/// The next Entry is in the library and this device holds no copy of it.
///
/// Not a dead end and not a failure — the Entry is first-class, it is simply
/// not on this device, so the way on is its Source.
final class NextEntryAtSourceOnly extends NextEntryOutcome {
  const NextEntryAtSourceOnly({
    required this.entryId,
    required this.entryName,
    required this.sourceUrl,
  });

  final String entryId;

  /// The Entry's own stored title, for the question that names it. Never
  /// rewritten here (V2-D55).
  final String entryName;

  /// The address the library actually recorded for it — its earliest active
  /// Location — or null when it has none.
  ///
  /// **Read, never constructed.** No URL is derived from a neighbour's
  /// address, a number in a path or anything else: an Entry is not a URL, and
  /// a guessed one would send the user to a page nobody recorded.
  final String? sourceUrl;
}

/// Nothing follows this Entry in the Collection **as the library stands now**.
///
/// The honest shape of the answer: the library has no next Entry, which is a
/// different statement from "the Collection has ended" and is the reason a
/// check is offered rather than a full stop announced.
final class NoNextEntryYet extends NextEntryOutcome {
  const NoNextEntryYet({
    required this.collectionId,
    required this.collectionName,
  });

  final String collectionId;
  final String collectionName;
}

/// This Entry has no reading order to move forward through — a standalone
/// Entry, or one that is not placed in its Collection yet.
///
/// By construction, not by omission: there is no next Entry to look for, so
/// nothing is offered and nothing is checked.
final class NoReadingOrder extends NextEntryOutcome {
  const NoReadingOrder();
}

/// Answers "what follows this Entry?" over the real library rows.
class NextEntryResolver {
  const NextEntryResolver({
    required this.entries,
    required this.collections,
    required this.offlineCopies,
  });

  final EntryRepository entries;
  final CollectionRepository collections;
  final OfflineCopyRepository offlineCopies;

  /// Resolved fresh on every request, never cached: a check run a moment ago
  /// may have written the very row this is about, and a download may have
  /// landed since the reader opened.
  Future<NextEntryOutcome> after(String entryId) async {
    final entry = await entries.byId(entryId);
    final collectionId = entry?.collectionId;
    if (entry == null || collectionId == null || entry.ordinal == null) {
      return const NoReadingOrder();
    }

    final placed = await placedEntriesOf(entries, collectionId);
    final index = placed.indexWhere((e) => e.id == entryId);
    final next = index >= 0 && index < placed.length - 1
        ? placed[index + 1]
        : null;
    if (next == null) {
      final collection = await collections.byId(collectionId);
      return NoNextEntryYet(
        collectionId: collectionId,
        collectionName: collection?.name ?? '',
      );
    }

    if (await offlineCopies.activeCopyOf(next.id) != null) {
      return NextEntryDownloaded(next.id);
    }
    return NextEntryAtSourceOnly(
      entryId: next.id,
      entryName: next.title.trim(),
      sourceUrl: await _addressOf(next.id),
    );
  }

  /// The Entry's earliest active Location — the same one the library opens an
  /// Entry at its source from everywhere else.
  Future<String?> _addressOf(String entryId) async {
    for (final location in await entries.locationsOf(entryId)) {
      if (location.lifecycle != LocationLifecycle.active.name) continue;
      final url = location.url.trim();
      if (url.isNotEmpty) return url;
    }
    return null;
  }
}
