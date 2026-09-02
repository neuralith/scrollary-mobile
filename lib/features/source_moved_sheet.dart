/// *This collection's site has moved.* The question, and the three answers.
///
/// **Why this file exists.** A check can now tell that the listing it was sent
/// to is not the one this Collection's Source claims — the site redirected it
/// somewhere else on the same host. That is strong evidence and it is still
/// only evidence: `(host, path_key)` is persistent Source identity, it is what
/// recognition, traversal and every guard key on, and changing it silently
/// would be the app deciding on its own that two addresses name one work.
/// V2-D14 and V2-D45 both say the same thing about this class of decision —
/// the person who can see both pages is the one who answers it.
///
/// So the check stops and reports, and this is where the answer is asked for.
/// Three answers, and each one is a thing the library can already do:
///
/// * **Update this source** — the move is real. `SourceRelocator` writes the
///   `resolvedInto` transition V2-D14 designed: the old row stays and points
///   forward, so nothing is deleted, and the Collection reads at its new
///   address from now on.
/// * **Add as another source** — both addresses are live. The Collection gains
///   a second Source, which is the ordinary multi-Source state (V2-D14) and
///   exactly what the save flow's *add this site as another source* produces.
/// * **It's different content** — this is not the same work. That answer needs
///   a name and a page, which is the save flow's job and not this sheet's, so
///   it opens the address in the Browser and lets the flow that already starts
///   Collections start one (V2-D45, V2-D69). Nothing is written here.
///
/// Backing out writes nothing and leaves the Source exactly as it was. The
/// check that produced the evidence has already stopped, so declining costs
/// the user nothing but another check later.
library;

import 'package:flutter/material.dart';

import '../recognition/relocation.dart' show SourceRelocationCandidate;
import '../ui/menu_sheet.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// Where the question is being asked from.
///
/// The three answers are the same operations either way; what differs is the
/// evidence that produced the question and what *carrying on* means. Keeping
/// both wordings here rather than at the two call sites is the terminology
/// rule: one surface, one place its sentences live.
enum SourceMovedOrigin {
  /// A check followed the Source's stored listing address and was redirected.
  check,

  /// The user is standing on the page and has just said which Collection it
  /// belongs to.
  save,
}

/// What the user answered.
enum SourceMovedChoice {
  /// Confirm the relocation: this Source now lives at the new address.
  updateSource,

  /// Keep the old Source and add the new address beside it.
  addAsAnotherSource,

  /// Not the same work — open it so the save flow can start a Collection.
  differentContent,
}

/// The address a candidate points at, as a person reads it.
String movedAddressLabel(SourceRelocationCandidate candidate) =>
    '${candidate.host}${candidate.pathKey}';

/// The address it used to be at.
String previousAddressLabel(SourceRelocationCandidate candidate) =>
    '${candidate.host}${candidate.previousPathKey}';

/// Ask which of the three this is.
///
/// Returns null when the sheet was dismissed, which is an answer: nothing is
/// written and the Source keeps the identity it has.
Future<SourceMovedChoice?> showSourceMovedSheet({
  required BuildContext context,
  required String collectionName,
  required SourceRelocationCandidate candidate,
  SourceMovedOrigin origin = SourceMovedOrigin.check,
}) {
  final seen = candidate.listingsSeen;
  final listed = seen == 1 ? '1 entry' : '$seen entries';
  final title = switch (origin) {
    SourceMovedOrigin.check => 'This collection\'s site has moved',
    SourceMovedOrigin.save => 'Is this the same site at a new address?',
  };
  // What was actually observed, in each case. The check followed an address
  // and was sent elsewhere; the save flow is standing on the page and has the
  // user's own answer about which Collection it is.
  final evidence = switch (origin) {
    SourceMovedOrigin.check =>
      '$collectionName is recorded at ${previousAddressLabel(candidate)}. '
          'Reading it was redirected to ${movedAddressLabel(candidate)}, '
          'which listed $listed.',
    SourceMovedOrigin.save =>
      'You are on ${movedAddressLabel(candidate)}. $collectionName is '
          'recorded at ${previousAddressLabel(candidate)} on the same site.',
  };
  // The third answer is the one that genuinely differs: from a check there is
  // nowhere to carry on *to*, so it opens the address; from the save flow the
  // user is already there and the ordinary create-a-Collection path continues.
  final differentSubtitle = switch (origin) {
    SourceMovedOrigin.check =>
      'Opens the new address in the Browser, where you can save it as a '
          'collection of its own. $collectionName is left alone.',
    SourceMovedOrigin.save =>
      'Carry on and save this as a new collection instead. $collectionName '
          'is left alone.',
  };
  return showLibraryMenu<SourceMovedChoice>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: serifStyle(size: 20),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '$evidence\n\nNothing has been changed yet.',
            style: TextStyle(
              fontSize: 13,
              color: AppPalette.of(sheetContext).inkMuted,
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('sourceMovedUpdate'),
          leading: const Icon(Icons.move_down),
          title: const Text('Update this source'),
          subtitle: const Text(
            'Read this collection at its new address from now on. Its '
            'entries, reading progress and anything downloaded stay exactly '
            'as they are.',
          ),
          onTap: () =>
              Navigator.of(sheetContext).pop(SourceMovedChoice.updateSource),
        ),
        ListTile(
          key: const ValueKey('sourceMovedAddSource'),
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add as another source'),
          subtitle: const Text(
            'Keep the old address and add this one beside it, as a second '
            'site for the same collection.',
          ),
          onTap: () => Navigator.of(
            sheetContext,
          ).pop(SourceMovedChoice.addAsAnotherSource),
        ),
        ListTile(
          key: const ValueKey('sourceMovedDifferent'),
          leading: const Icon(Icons.open_in_browser),
          title: const Text('It\'s different content'),
          subtitle: Text(differentSubtitle),
          onTap: () => Navigator.of(
            sheetContext,
          ).pop(SourceMovedChoice.differentContent),
        ),
        // An explicit way out, beside the ones that act. Dismissing does the
        // same thing; a person deciding between three writes should not have
        // to work out that backing out is safe.
        ListTile(
          key: const ValueKey('sourceMovedNotNow'),
          leading: const Icon(Icons.close),
          title: const Text('Not now'),
          subtitle: const Text(
            'Changes nothing. This collection keeps the address it has.',
          ),
          onTap: () => Navigator.of(sheetContext).pop(),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
