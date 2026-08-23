/// Everything the library holds about one Entry, in one place a person can
/// look.
///
/// **Why this exists.** The Collection list now leads with an Entry's position
/// and drops the part of a page title that merely repeats it and the work's
/// name. That is a *presentation* rule and nothing is discarded by it — the
/// stored title, the label the site printed, the address, the Source, all of
/// it is still in the library exactly as it arrived. This is where the user
/// can see it, so "the row is quieter" never means "the evidence is gone".
///
/// It reads and shows. No verb here changes anything: the actions on an Entry
/// live on the menu this is reached from, and a details sheet that could also
/// act would be a second place to decide things.
///
/// **Four independent facts** (PRODUCT.md §2.3) — known, in the library,
/// downloaded, read — are four separate lines, and this sheet is careful never
/// to imply one from another. An Entry with no copy on this device says so and
/// stays an ordinary Entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schema.dart';
import '../domain/entry.dart';
import '../library/entry_presentation.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'collection_models.dart';
import 'providers.dart';

/// One row of the sheet: what it is, and what the library holds for it.
class EntryFact {
  const EntryFact(this.label, this.value);

  final String label;

  /// Never empty — a fact with nothing to say is left out rather than printed
  /// as a blank.
  final String value;
}

/// What the library holds about [entryId], assembled for display.
///
/// Deliberately a list of `(label, value)` rather than a typed object: this is
/// a *record*, and the only thing anything does with it is print it in order.
Future<List<EntryFact>> entryFactsFor(
  LibraryDatabase db,
  EntryRowView view,
) async {
  final row = view.row;
  final facts = <EntryFact>[];

  final collection = view.collectionName?.trim() ?? '';
  facts.add(
    EntryFact(
      'In your library',
      collection.isEmpty ? 'On its own, not in a collection' : collection,
    ),
  );

  final ordinal = row.ordinal;
  facts.add(
    EntryFact(
      'Position',
      ordinal == null
          ? (row.placement == Placement.unplaced.name
                ? 'Not established — you can set it'
                : 'None')
          : formatOrdinal(ordinal),
    ),
  );

  // The title the library holds, verbatim. Shown even when the row above it
  // shows something shorter, because the *point* of this sheet is that the
  // shorter thing is a reading and this is the record.
  final title = row.title.trim();
  if (title.isNotEmpty) facts.add(EntryFact('Title', title));

  final printed = view.sourceLabel?.trim() ?? '';
  if (printed.isNotEmpty && printed != title) {
    facts.add(EntryFact('The source called it', printed));
  }

  final location = await primaryLocation(db, row.id);
  if (location != null) {
    facts.add(EntryFact('Address', location.url));
    final sourceId = location.sourceId;
    if (sourceId != null) {
      final source = await (db.select(
        db.sources,
      )..where((s) => s.id.equals(sourceId))).getSingleOrNull();
      if (source != null) facts.add(EntryFact('Source', source.host));
    }
    final number = location.sourceNumber;
    if (number != null) {
      facts.add(EntryFact('Numbered there', formatOrdinal(number)));
    }
  }

  // How many places this one Entry can be read from. A number, not a list:
  // two Sources of the same work is an ordinary thing and the detail belongs
  // on the Collection's Sources, not here.
  final locations = await (db.select(
    db.locations,
  )..where((l) => l.entryId.equals(row.id))).get();
  // Retracted rows are filtered here rather than in the query: drift's
  // boolean operators need the whole library imported, and this file draws
  // widgets — `Column` would collide.
  final active = locations.where((l) => l.lifecycle == 'active').length;
  if (active > 1) {
    facts.add(EntryFact('Also readable at', '${active - 1} more'));
  }

  facts.add(EntryFact('Reading', view.statusLabel));
  facts.add(
    EntryFact(
      'On this device',
      view.availableOffline ? 'Downloaded' : 'Not downloaded',
    ),
  );
  return facts;
}

/// Show what the library holds about this Entry.
Future<void> showEntryDetails(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final facts = await entryFactsFor(ref.read(libraryDatabaseProvider), view);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _EntryDetailsSheet(view: view, facts: facts),
  );
}

class _EntryDetailsSheet extends StatelessWidget {
  const _EntryDetailsSheet({required this.view, required this.facts});

  final EntryRowView view;
  final List<EntryFact> facts;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('entryDetailsSheet'),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(view.label, style: serifStyle(size: 22)),
            ),
            const SizedBox(height: 14),
            for (final fact in facts) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fact.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w600,
                        color: palette.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Selectable, because an address is something people copy
                    // and a title is something people search for.
                    SelectableText(
                      fact.value,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
