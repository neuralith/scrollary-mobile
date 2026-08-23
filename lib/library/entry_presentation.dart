/// What one Entry looks like on a row, and how much of its identity the
/// surface has to repeat.
///
/// **Why this file exists.** Inside a Collection, every row printed the whole
/// page title a site had written — so a work whose site titles its pages
/// *"Quiet Harbour — Part 101"* produced a list where the only thing that
/// varied was three digits at the far right of four identical lines. The
/// Collection's name is already at the top of that screen; repeating it on
/// every row is noise, and it made an ordered work look unordered.
///
/// **The identity a serialized Entry has is its position.** `101` is what the
/// reader is looking for and what the source itself calls it, so that is what
/// the row leads with. Everything else — the site's title for the page, the
/// address it lives at, the Source it came from — is still stored, still
/// intact and still inspectable; this file decides only what a *row* prints.
///
/// **Context decides, and it is passed in.** The same Entry on Continue
/// Reading or in Activity has no Collection name above it, so there it needs
/// one. There is no global "strip the collection name" rule here and there
/// must not be: a caller says where it is drawing, and gets what belongs
/// there.
///
/// Nothing here invents a number, mutates a stored title, or reaches a
/// database. The vocabulary is `entry_labels.dart`'s, as it is everywhere.
library;

import 'collection_identity.dart';
import 'entry_labels.dart';

/// Where an Entry is being drawn — which is what decides how much of its
/// identity has to be spelled out.
enum EntryContext {
  /// The Collection's own screen. The work is named above the list, and the
  /// reader is looking down a sequence.
  withinCollection,

  /// A surface that spans the library: Continue Reading, Activity, a search
  /// result. Nothing above the row says which work this is.
  acrossLibrary,
}

/// What a row prints: one line that identifies the Entry, and at most one
/// quieter line under it.
class EntryPresentation {
  const EntryPresentation({required this.primary, this.secondary});

  /// The Entry's identity, and the largest thing on the row.
  final String primary;

  /// Whatever else is worth saying and is not already said by [primary] or by
  /// the surface around it. Null far more often than not, and deliberately.
  final String? secondary;

  bool get hasSecondary => (secondary?.isNotEmpty ?? false);
}

/// A position as this app prints one: `3`, `3.5`, `12` — never `3.0`.
///
/// A trailing `.0` reads as precision the sequence does not have, and the same
/// number must print identically in a row, in the placement field, in a
/// refusal and in a confirmation. `99.5` keeps its half, because 100 and 99.5
/// are two Entries (V2-D16) and printing them the same would say otherwise.
///
/// Moved down here from `library_ui/placement_models.dart`, which re-exports
/// it: a row now prints a position, so the rule belongs beside the rest of the
/// presentation rather than in the dialog that happened to need it first.
String formatOrdinal(double ordinal) {
  if (ordinal == ordinal.roundToDouble() && ordinal.abs() < 1e15) {
    return ordinal.toStringAsFixed(0);
  }
  return ordinal.toString();
}

/// How to draw one Entry.
///
/// [ordinal] is the Entry's own position, when the Collection could establish
/// one. [title] is what the library holds for it and [sourceLabel] is what a
/// site printed; neither is modified here, and the one shown is whichever the
/// caller's rules already prefer.
///
/// The three cases, in order:
///
/// 1. **A position, on the Collection's own screen.** The number leads. The
///    title follows *only if it says something the number and the work's name
///    do not* — see [entrySubtitle].
/// 2. **A position, anywhere else.** The row has to name itself: the work,
///    then the number. The caller supplies the Collection's name where it has
///    one, and where it does not the number stands alone rather than being
///    dressed up.
/// 3. **No position.** The best title there is, verbatim. Nothing invents a
///    number, and *Prologue* and *Appendix B* are real names that survive
///    exactly as written.
EntryPresentation entryPresentation({
  required EntryContext context,
  EntryLabels labels = kPlainEntryLabels,
  double? ordinal,
  String? title,
  String? sourceLabel,
  String? collectionName,
}) {
  final name = _firstNonEmpty([title, sourceLabel]);

  if (ordinal == null) {
    return EntryPresentation(
      primary: name ?? labels.One,
      // Across the library an unnumbered Entry still needs to say where it is
      // from, and its own title is the only thing identifying it.
      secondary: context == EntryContext.acrossLibrary
          ? _clean(collectionName)
          : null,
    );
  }

  final position = formatOrdinal(ordinal);
  if (context == EntryContext.acrossLibrary) {
    final work = _clean(collectionName);
    return EntryPresentation(
      primary: work == null ? position : '$work · $position',
      secondary: entrySubtitle(
        title: name,
        ordinal: ordinal,
        collectionName: collectionName,
      ),
    );
  }

  return EntryPresentation(
    primary: position,
    secondary: entrySubtitle(
      title: name,
      ordinal: ordinal,
      collectionName: collectionName,
    ),
  );
}

/// The Entry's **own name**, with no position in it.
///
/// A different question from [entryPresentation], and the difference matters
/// wherever a sentence already carries the number: *"Position 5 is already
/// taken by …"* wants to know **which Entry**, and answering it with `5` is a
/// tautology. So this is the name and nothing else — what the library holds,
/// what the source printed, or the generic noun — and it never reaches for the
/// ordinal.
String entryOwnName({
  EntryLabels labels = kPlainEntryLabels,
  String? title,
  String? sourceLabel,
}) => entryDisplayLabel(
  labels: labels,
  title: _firstNonEmpty([title, sourceLabel]),
);

/// What a title still says once the position and the work's name are taken
/// out of it — or null when it said nothing else.
///
/// The two removals are both narrow, and both refuse to guess:
///
/// * **The work's name**, whole-token and case-insensitive. `"Quiet Harbour
///   Part 101"` gives it up; `"Quietly"` keeps every letter.
/// * **A marker naming this Entry's own number**, and only that number.
///   `"Part 101"` goes from Entry 101 and stays on Entry 7, because on Entry 7
///   the 101 is something the title knows and the row does not.
///
/// What is left is returned as the site wrote it, so `"Part 101 — The Quiet
/// Night"` becomes `"The Quiet Night"` and `"Prologue"` stays `"Prologue"`.
/// A title that survives both removals unchanged is returned unchanged: the
/// point is to drop repetition, never to edit prose.
///
/// **The stored title is untouched.** This is a reading of it, computed per
/// row, and `Entry details` still shows what the source actually said.
String? entrySubtitle({
  required String? title,
  required double? ordinal,
  required String? collectionName,
}) {
  final text = title?.trim() ?? '';
  if (text.isEmpty) return null;

  var residue = stripCollectionName(text, collectionName);
  residue = stripEntryMarkerFor(residue, ordinal);

  // Nothing left, or nothing left but the number itself: the title was a
  // restatement of the row and the work above it.
  if (residue.isEmpty) return null;
  if (_isJustANumber(residue)) return null;
  return residue;
}

/// True for a residue that is only digits and punctuation — `"101"`, `"#101"`,
/// `"- 101 -"`. A row that already prints the position must not print it again
/// in smaller type.
bool _isJustANumber(String text) => RegExp(
  r'^[\s\-–—:|,\.#()\[\]]*\d+(?:[.,]\d+)?[\s\-–—:|,\.#()\[\]]*$',
).hasMatch(text);

String? _clean(String? text) {
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String? _firstNonEmpty(List<String?> candidates) {
  for (final candidate in candidates) {
    final trimmed = candidate?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}
