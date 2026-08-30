/// The control that puts a Collection's Entries in an order.
///
/// **It sits on the Entries heading, not in the Collection menu.** The order a
/// list is in is a property of the list you are looking at, and it is changed
/// while looking at it — usually more than once, to see what the collection
/// looks like the other way round. A setting three taps into an overflow menu
/// is a setting nobody finds, and one that closes the screen to apply is one
/// nobody plays with. The button says the current order, so reading it costs
/// nothing (the same rule the capture-mode row follows, V2-D60).
///
/// **Only what the data supports is offered.** The list of fields comes from
/// the Entries themselves — see `availableEntrySortFields` — so a Collection
/// where no site ever printed a date has no *Publish date* row to tap. An
/// order that would draw the list exactly as it already is, because nothing in
/// it can answer the question, is not a choice; it is a dead end with a
/// checkmark.
///
/// Direction is offered for every field, always, and both of its labels are
/// written per field: "Newest first" is the answer to a question somebody
/// actually has, and "descending" is not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/entry_sort.dart';
import '../ui/menu_sheet.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'collection_models.dart';
import 'providers.dart';

/// The button that opens the sort sheet, sized for a section heading.
///
/// Draws the current order rather than the word "Sort": the heading it sits on
/// is already the only place this could be about, so the space is better spent
/// on the answer than on repeating the question.
class EntrySortButton extends ConsumerWidget {
  const EntrySortButton({super.key, required this.view});

  final CollectionView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: const ValueKey('entrySortButton'),
      onTap: () => showEntrySortMenu(context, ref, view),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              view.sort.isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: palette.inkMuted,
            ),
            const SizedBox(width: 4),
            Text(
              view.sort.field.label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.84,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.inkMuted,
              ),
            ),
            Icon(Icons.expand_more, size: 16, color: palette.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// The sheet: the orders this Collection can be in, then which way round.
///
/// Every tap writes the preference and closes. Writing on tap rather than on a
/// *Done* is what makes the control worth having — the list is behind the
/// sheet, and seeing it redraw is the whole point of changing the order.
Future<void> showEntrySortMenu(
  BuildContext context,
  WidgetRef ref,
  CollectionView view,
) async {
  final sort = view.sort;
  final store = ref.read(entrySortPreferenceProvider);
  final chosen = await showLibraryMenu<EntrySort>(
    context: context,
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              'Order ${libraryEntryLabels.many}',
              style: serifStyle(size: 20),
            ),
          ),
          // Only ever more than one row where the data supports more than one
          // order; a single-option list is still drawn, because seeing which
          // one it is in is why somebody opened this.
          for (final field in view.available)
            ListTile(
              key: ValueKey('entrySortField-${field.name}'),
              leading: Icon(
                field == sort.field
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(field.label),
              subtitle: Text(field.explanation),
              onTap: () =>
                  Navigator.of(sheetContext).pop(sort.withField(field)),
            ),
          const Divider(height: 17),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'DIRECTION',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.84,
                  fontVariations: wght(600),
                  fontWeight: FontWeight.w600,
                  color: palette.inkMuted,
                ),
              ),
            ),
          ),
          for (final direction in EntrySortDirection.values)
            ListTile(
              key: ValueKey('entrySortDirection-${direction.name}'),
              leading: Icon(
                direction == sort.direction
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(direction.labelFor(sort.field)),
              onTap: () =>
                  Navigator.of(sheetContext).pop(sort.withDirection(direction)),
            ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
  if (chosen == null) return;
  // Written even when it matches what the list was already showing: the
  // Collection was following its data until now, and tapping the order it
  // happens to be in is how somebody says "keep it this way" (the same
  // distinction the capture preference draws, V2-D61).
  await store.remember(view.collection.id, chosen);
}
