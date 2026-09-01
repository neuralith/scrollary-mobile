/// Choosing the Collection something belongs to — the one picker every
/// *adopt* uses.
///
/// **The user decides identity; the app never infers it.** A detected title
/// pre-fills the filter and the name field and does nothing else: there is no
/// auto-selection, no similarity score, no "did you mean", and no row is
/// preselected however close its name is (V2-D44, PRODUCT.md §5.3). A
/// Collection is chosen by a tap or it is not chosen at all.
///
/// The list is every Collection in the library, archived ones included. An
/// archived Collection is one Scrollary has stopped keeping current, not one
/// that has left the library, and hiding it here would make a user's own
/// Collection unreachable from the flow that fills it.
library;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schema.dart';
import '../domain/collection.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'providers.dart';

/// What the user picked. Two answers, and they are different operations: one
/// adds this site as another Source of a Collection that already exists, the
/// other starts a Collection with this site as its first Source.
sealed class CollectionChoice {
  const CollectionChoice();

  const factory CollectionChoice.existing(String id, String name) =
      ExistingCollectionChoice;

  const factory CollectionChoice.create(String name) = NewCollectionChoice;
}

/// An existing Collection, by the id the row actually has.
final class ExistingCollectionChoice extends CollectionChoice {
  const ExistingCollectionChoice(this.id, this.name);

  final String id;
  final String name;
}

/// A Collection that does not exist yet, under the name the user typed.
final class NewCollectionChoice extends CollectionChoice {
  const NewCollectionChoice(this.name);

  final String name;
}

/// Every Collection in the library, by name.
///
/// Local to this file on purpose: the picker is the only surface that wants a
/// flat, unfiltered list of Collections, and the shelf's own providers are
/// shaped for a Folder tree.
final pickableCollectionsProvider = StreamProvider<List<CollectionRow>>((ref) {
  final db = ref.watch(libraryDatabaseProvider);
  return (db.select(
    db.collections,
  )..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();
});

/// Ask which Collection this belongs to. Null when the user backed out.
///
/// [suggestedTitle] pre-fills **the filter text and the new-collection name**
/// and nothing else — it never selects a row.
/// [allowCreate] is false where creating one would be wrong: adopting a
/// standalone Entry moves it into a Collection that already exists, and
/// wrapping one Entry in a Collection of its own is exactly what I3 forbids.
///
/// [confirmNameHere] is whether *New collection* stops on a name field of its
/// own. It does when this picker is the last surface the user will see, which
/// is the listing case — a listing is not an Entry, so no sheet follows it and
/// the name has nowhere else to be confirmed. It does **not** when a sheet
/// does follow: the Entry save flow's next surface already prints the
/// Collection's name in its header, and a whole screen for one field whose
/// value is echoed on the next one is the step this removes (V2-D57). The row
/// then hands [suggestedTitle] back as it stands, unconfirmed, and the caller
/// is the one that asks.
///
/// [attachingSourceHost] is the site the caller is about to attach, on the
/// paths where picking an existing Collection **adds this site to it as
/// another Source**. Naming it here is what makes this sheet an operation the
/// user can recognise rather than a list of Collections: its two answers are
/// *start one for this site* and *add this site to one you already have*, and
/// only the first said so. It is null or empty where picking one means
/// something else — adopting a standalone Entry moves that Entry and attaches
/// no site — and then nothing is said.
Future<CollectionChoice?> showCollectionPicker(
  BuildContext context,
  // The caller already holds a ref; taking it keeps this signature honest
  // about needing the library's provider graph, which the sheet reads through
  // its own `Consumer` below.
  WidgetRef ref, {
  String? suggestedTitle,
  bool allowCreate = true,
  bool confirmNameHere = true,
  String? attachingSourceHost,
}) {
  return showModalBottomSheet<CollectionChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _CollectionPicker(
      suggestedTitle: suggestedTitle?.trim() ?? '',
      allowCreate: allowCreate,
      confirmNameHere: confirmNameHere,
      attachingSourceHost: attachingSourceHost?.trim() ?? '',
    ),
  );
}

class _CollectionPicker extends ConsumerStatefulWidget {
  const _CollectionPicker({
    required this.suggestedTitle,
    required this.allowCreate,
    required this.confirmNameHere,
    required this.attachingSourceHost,
  });

  final String suggestedTitle;
  final bool allowCreate;

  /// The site an existing Collection would gain. Empty where none would.
  final String attachingSourceHost;

  /// Whether *New collection* names it here. See [showCollectionPicker].
  final bool confirmNameHere;

  @override
  ConsumerState<_CollectionPicker> createState() => _CollectionPickerState();
}

class _CollectionPickerState extends ConsumerState<_CollectionPicker> {
  late final TextEditingController _filter = TextEditingController(
    text: widget.suggestedTitle,
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestedTitle,
  );

  /// True while the new-collection name is being typed. The list is not shown
  /// underneath it: naming a new Collection and picking an existing one are
  /// two answers to the same question, and offering both at once is how a tap
  /// lands on the wrong one.
  bool _naming = false;

  @override
  void dispose() {
    _filter.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submitName() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(CollectionChoice.create(name));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  _naming ? 'New collection' : 'Add to a collection',
                  style: serifStyle(size: 20),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  _naming
                      ? 'This site becomes its first source. Nothing is '
                            'merged with anything you already have.'
                      : 'Pick the collection this belongs to. Scrollary never '
                            'matches one for you.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: palette.inkMuted,
                  ),
                ),
              ),
              if (_naming) ..._nameFields(palette) else ..._pickFields(palette),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _nameFields(AppPalette palette) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
        key: const ValueKey('collectionNameField'),
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Collection name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submitName(),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          TextButton(
            key: const ValueKey('collectionCreateBack'),
            onPressed: () => setState(() => _naming = false),
            child: const Text('Back'),
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('collectionCreateConfirm'),
            onPressed: _name.text.trim().isEmpty ? null : _submitName,
            child: const Text('Create collection'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _pickFields(AppPalette palette) {
    final collections = ref.watch(pickableCollectionsProvider);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: TextField(
          key: const ValueKey('collectionPickerFilter'),
          controller: _filter,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'Find a collection',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
          onChanged: (_) => setState(() {}),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
      ),
      // The other answer, said where it is given. The *New collection* row
      // below has always named what it does to this site; picking a
      // Collection that exists does the same thing to it and said nothing,
      // which left the operation the user came for looking like a list.
      if (widget.attachingSourceHost.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Picking one adds ${widget.attachingSourceHost} to it as another '
            'source. What it already holds is kept.',
            key: const ValueKey('collectionPickerSourceNote'),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.inkMuted,
            ),
          ),
        ),
      if (widget.allowCreate)
        ListTile(
          key: const ValueKey('collectionPickerNew'),
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('New collection'),
          subtitle: const Text(
            'Starts a collection with this site as its first source.',
          ),
          // Which of its two answers this row gives is the caller's: name it
          // here, or hand the suggestion straight to the surface that will.
          onTap: () => widget.confirmNameHere
              ? setState(() => _naming = true)
              : Navigator.of(
                  context,
                ).pop(CollectionChoice.create(widget.suggestedTitle)),
        ),
      const Divider(height: 1),
      Flexible(
        child: collections.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Your collections could not be read.',
              style: TextStyle(color: palette.inkMuted),
            ),
          ),
          data: (rows) => _list(palette, rows),
        ),
      ),
    ];
  }

  Widget _list(AppPalette palette, List<CollectionRow> rows) {
    final query = _filter.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? rows
        : [
            for (final row in rows)
              if (row.name.toLowerCase().contains(query)) row,
          ];
    if (matches.isEmpty) {
      final String empty;
      if (rows.isNotEmpty) {
        empty = 'No collection is named like “${_filter.text.trim()}”.';
      } else if (widget.allowCreate) {
        empty =
            'You have no collections yet. Create one above and this becomes '
            'its first entry.';
      } else {
        empty =
            'You have no collections yet. One is created the first time you '
            'add a page from a site.';
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              empty,
              key: const ValueKey('collectionPickerEmpty'),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: palette.inkMuted,
              ),
            ),
            // A suggestion that hides every row is still only a suggestion:
            // the way back to the whole list is one tap, and it is visible.
            if (rows.isNotEmpty)
              TextButton(
                key: const ValueKey('collectionPickerClearFilter'),
                onPressed: () => setState(_filter.clear),
                child: Text('Show all ${rows.length} collections'),
              ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = matches[index];
        final archived = row.lifecycle == CollectionLifecycle.archived.name;
        return ListTile(
          key: ValueKey('collectionOption-${row.id}'),
          leading: Icon(
            Icons.collections_bookmark_outlined,
            size: 20,
            color: palette.inkMuted,
          ),
          title: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: archived
              ? const Text('Archived — Scrollary is not keeping it current.')
              : null,
          onTap: () => Navigator.of(
            context,
          ).pop(CollectionChoice.existing(row.id, row.name)),
        );
      },
    );
  }
}
