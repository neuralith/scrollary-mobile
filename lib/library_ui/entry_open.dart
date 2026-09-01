/// What a tap on an Entry does: it **opens the Entry** (V2-D71).
///
/// A row used to open the actions menu from both of its controls, because the
/// reading lane did not exist yet. It does now, so the row's own tap is the
/// ordinary verb — read this — and the menu stays behind the three-dot
/// control, which is where the settings and the destructive verbs belong.
///
/// The decision the tap makes is one question asked in one place:
///
///  1. **This device holds a copy → the offline reader.** A download is a
///     property of this device (I13), and where the bytes are here they are
///     what "open it" means.
///  2. **It does not → the Entry's own site.** A non-downloaded Entry is a
///     first-class library item, never a dead end: its Locations are where it
///     is read, and opening one records that it was *opened* — never that it
///     was finished (I16).
///  3. **Several places, and no clear preferred one → ask.** An Entry may sit
///     on more than one of its Collection's Sources. The Collection's
///     preferred Source answers that where there is one, exactly as
///     `checkPreferredSource` uses it; where it does not, this file asks the
///     user rather than picking a site on their behalf.
///
/// Nothing here constructs an address. Every URL is read from a Location the
/// library recorded, because an Entry is not a URL (V2-D15).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location.dart';
import '../ui/menu_sheet.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'collection_models.dart';
import 'library_widgets.dart';
import 'providers.dart';

/// One place an Entry can be read at: an active Location, named by the site it
/// is on.
class EntrySourceOption {
  const EntrySourceOption({
    required this.url,
    required this.sourceId,
    required this.host,
  });

  final String url;

  /// Null for a standalone Entry's Location (I7).
  final String? sourceId;

  /// The site, as the library recorded it. The Source's own host where the
  /// Location belongs to one, and the address's host otherwise — never a name
  /// this file invents.
  final String host;
}

/// Where an Entry can be read at its source, and which of those places — if
/// any — needs no question.
class EntrySources {
  const EntrySources({required this.options, required this.preferred});

  /// Every active Location with an address, in discovery order. Empty is a
  /// real answer: an Entry may be in the library with no address recorded.
  final List<EntrySourceOption> options;

  /// The one place to open without asking, or null when the user has to
  /// choose between [options].
  final EntrySourceOption? preferred;
}

/// Read every place [entryId] can be opened at, and apply the preference rule.
///
/// The rule, in the same shape `SourceCheck.checkPreferredSource` uses: a
/// Collection with a preferred Source narrows the candidates to that Source's
/// Locations, and one candidate is an answer while several are a question.
Future<EntrySources> entrySourcesOf(WidgetRef ref, String entryId) async {
  final entries = ref.read(entryRepoProvider);
  final collections = ref.read(collectionRepoProvider);

  final entry = await entries.byId(entryId);
  final collectionId = entry?.collectionId;
  final hosts = <String, String>{
    if (collectionId != null)
      for (final source in await collections.sourcesOf(collectionId))
        source.id: source.host,
  };

  final options = <EntrySourceOption>[];
  for (final location in await entries.locationsOf(entryId)) {
    if (location.lifecycle != LocationLifecycle.active.name) continue;
    final url = location.url.trim();
    if (url.isEmpty) continue;
    options.add(
      EntrySourceOption(
        url: url,
        sourceId: location.sourceId,
        host: hosts[location.sourceId] ?? Uri.tryParse(url)?.host ?? url,
      ),
    );
  }

  final preferredSourceId = collectionId == null
      ? null
      : (await collections.byId(collectionId))?.preferredSourceId;
  final onPreferred = preferredSourceId == null
      ? const <EntrySourceOption>[]
      : [
          for (final option in options)
            if (option.sourceId == preferredSourceId) option,
        ];
  final candidates = onPreferred.isEmpty ? options : onPreferred;

  return EntrySources(
    options: candidates,
    preferred: candidates.length == 1 ? candidates.single : null,
  );
}

/// *Which site do you want to read it on?*
///
/// Asked only when the library genuinely holds no answer. Every row states the
/// site and the address it will open, because the two are what distinguishes
/// them and neither is guessable from the other.
Future<EntrySourceOption?> showEntrySourcePicker(
  BuildContext context,
  String entryLabel,
  List<EntrySourceOption> options,
) => showLibraryMenu<EntrySourceOption>(
  context: context,
  builder: (sheetContext) => Column(
    key: const ValueKey('entrySourcePicker'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
        child: Text(
          'Where do you want to read it?',
          style: serifStyle(size: 20),
        ),
      ),
      if (entryLabel.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Text(
            entryLabel.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(
              size: 11.5,
              color: AppPalette.of(sheetContext).inkStrong,
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
        child: Text(
          'This entry is published on more than one of this collection’s '
          'sites, and none of them is the preferred one.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppPalette.of(sheetContext).inkMuted,
          ),
        ),
      ),
      for (final option in options)
        ListTile(
          key: ValueKey('entrySourceOption-${option.url}'),
          leading: const Icon(Icons.public),
          title: Text(option.host),
          subtitle: Text(
            option.url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(sheetContext).pop(option),
        ),
      const SizedBox(height: 8),
    ],
  ),
);

/// Open [view] at one of its Sources, asking first where that is a real
/// question.
///
/// Two facts, in this order: the page opens, and the library records that it
/// was opened (I16 — never that it was finished).
Future<void> openEntryAtSource(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final sources = await entrySourcesOf(ref, view.id);
  if (!context.mounted) return;
  if (sources.options.isEmpty) {
    showLibraryMessage(context, 'No address is recorded for this entry.');
    return;
  }

  var chosen = sources.preferred;
  if (chosen == null) {
    chosen = await showEntrySourcePicker(context, view.label, sources.options);
    if (chosen == null || !context.mounted) return;
  }

  final opener = ref.read(sourceOpenerProvider);
  if (opener == null) {
    // Honest rather than silent: nothing opened, so nothing is recorded as
    // having been opened.
    showLibraryMessage(context, 'Opening a source is not available yet.');
    return;
  }
  await opener(chosen.url);
  await ref.read(readingRepoProvider).recordSourceAccess(view.id);
}

/// What a tap on an Entry row does, wherever that row is drawn.
///
/// The offline reader where this device holds the bytes, the Entry's site
/// where it does not. It never opens the actions menu — that is the three-dot
/// control's, and only its.
Future<void> openEntryFromRow(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  if (view.availableOffline) {
    final open = ref.read(entryOpenerProvider);
    if (open == null) {
      showLibraryMessage(
        context,
        'Opening the copy on this device is not available yet.',
      );
      return;
    }
    await open(view.id);
    return;
  }
  await openEntryAtSource(context, ref, view);
}
