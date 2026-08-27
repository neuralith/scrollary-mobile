/// *How much?* — the question the V2 save sheet lost, restored, and now a
/// **section of the save sheet rather than a sheet after it** (V2-D62).
///
/// This is V1's range interaction, ported to the V2 domain rather than
/// redesigned. Every detail of its numeric behaviour was device-tested and is
/// here on purpose:
///
/// * the field is **digits only**, however the text arrives — typed, pasted or
///   dictated — and no longer than the ceiling needs, so nothing can overflow
///   the parse;
/// * an empty field and a zero are refused **where they were typed**, with the
///   keyboard put back under the thumb, because an error about a number the
///   user cannot currently reach is a dead end;
/// * the OK bar exists because iOS draws `TextInputType.number` as a number
///   pad with **no return key at all** — `TextInputAction.done` is inert there,
///   and Android's IME is the only platform where it fires;
/// * OK is not a launch. It confirms the number and stops.
///
/// **Why a controller.** The count, its focus, the chosen range and the two
/// refusals have to outlive any one widget in the sheet, and the OK bar has to
/// be pinned *outside* the scrolling body — a bar that scrolls away is not a
/// way out of a keyboard. So the state lives in [SaveScopeController], the
/// scrolling half is [SaveScopeSection], and the pinned half is
/// [SaveCountOkBar]. The surface that owns the sheet composes the two.
///
/// Two rules from CLAUDE.md this states rather than merely obeys: the ceiling
/// is a number the user can see, and **a queued download waits for an explicit
/// Start**.
///
/// **Two ranges take a count, and they answer different questions**
/// (docs/V2_SAVE_FLOW.md §4). *Entries from here* counts on the **Source**:
/// the ones the library has not seen are found by reading this site forward
/// from the page in front of the user. *Entries already in your library*
/// counts on the library and opens nothing. Both count the entry the user is
/// on as the first one, and the section says so in words rather than leaving
/// it to be inferred from a number.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import 'providers.dart' show StartWhere;
import '../features/storage_screen.dart' show formatBytes;
import '../save/size_estimate.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// What the user asked to happen once the rows are added.
///
/// Three answers, and each one is unambiguous about *what happens next*. The
/// pair they replace — a *Start now* button here and a separate sheet
/// afterwards asking where to wait — meant a user could choose *Add to queue*,
/// then choose *Start in Browser*, and have nothing start.
enum SaveStartMode {
  /// Add the work. Start nothing. The rows wait, as they do by default.
  queueOnly,

  /// Add it and start, with the Browser in front of the user.
  startNow,

  /// Add it and start, leaving the user where they are.
  keepWorking;

  bool get starts => this != SaveStartMode.queueOnly;

  /// The same answer in the vocabulary a Start is handed. Null for a launch
  /// that starts nothing and has nowhere to say.
  StartWhere? get where => switch (this) {
    SaveStartMode.queueOnly => null,
    SaveStartMode.startNow => StartWhere.inBrowser,
    SaveStartMode.keepWorking => StartWhere.keepWorking,
  };
}

/// A Collection that does not exist yet, named on the sheet that asks how
/// much of it to download.
///
/// Present only for *New collection*: an existing Collection's name is not
/// editable here, because renaming one on the way past is not what the user
/// came to this sheet to do.
class NewCollectionNaming {
  const NewCollectionNaming({required this.suggestedName, this.host = ''});

  /// What the page called the work. A suggestion the user may correct, and
  /// never a match key — nothing is selected or merged from it (V2-D44).
  final String suggestedName;

  /// The site this address is on, which becomes the Collection's first Source.
  /// Empty where the address has no host to name, and then simply not said.
  final String host;
}

/// The range the user chose, and what they asked to happen with it.
class SaveScopeChoice {
  const SaveScopeChoice({
    required this.limits,
    required this.start,
    this.discoverMissing = false,
    this.collectionName,
  });

  /// Built only ever through [SaveLimits.forScope], so there is no
  /// representation of an unbounded run in this file.
  final SaveLimits limits;

  /// Queue only, start now, or start and keep working. Whatever it says is
  /// what happens — this is the whole of the launch decision, taken once.
  final SaveStartMode start;

  /// Whether anything is started at all.
  bool get startNow => start.starts;

  /// True when the count is a claim about the **Source** rather than about
  /// the library: if the later Entries are not known yet, read forward on
  /// this site to find them (docs/V2_SAVE_FLOW.md §4).
  ///
  /// False is *Entries already in your library* — queue what the library
  /// already holds and say how many that was, opening nothing. Both are real
  /// answers, and the one that opens a site is the one the user picked.
  final bool discoverMissing;

  /// The name for the Collection about to be created, trimmed and non-empty.
  /// Null whenever the section was not naming one, which is every other case.
  final String? collectionName;
}

/// The *how much* question's whole state, and the only thing that validates it.
///
/// Lives on the surface that shows the section, so the section can be rebuilt,
/// scrolled past or briefly removed without the typed number, the chosen range
/// or a refusal going with it.
class SaveScopeController extends ChangeNotifier {
  SaveScopeController({
    SaveScope initialScope = SaveScope.currentPageOnly,
    int initialCount = 2,
    this.naming,
  }) : _scope = initialScope,
       count = TextEditingController(text: '$initialCount') {
    countFocus.addListener(notifyListeners);
    name = TextEditingController(text: naming?.suggestedName ?? '');
  }

  /// A harmless editable default, not a preset: the field opens with the
  /// range, the value is fully replaceable, and nothing is queued until one of
  /// the launches is pressed.
  final TextEditingController count;

  /// Held so the surface can put the keyboard away itself, and call it back
  /// when a number is refused.
  final FocusNode countFocus = FocusNode(debugLabel: 'saveCountField');

  /// The new Collection's name, and the focus a blank one is sent back to.
  late final TextEditingController name;
  final FocusNode nameFocus = FocusNode(debugLabel: 'saveCollectionNameField');

  /// The Collection this save is about to bring into existence, when it is
  /// about to. Null everywhere else, and then no name is asked for.
  final NewCollectionNaming? naming;

  SaveScope _scope;
  SaveScope get scope => _scope;

  /// The counted range on this sheet is always the one that reads the site
  /// forward (V2-D65). *Entries already in your library* was a third row that
  /// answered a different question — queue what is already known, open
  /// nothing — and nobody reaches for it while saving the page in front of
  /// them. `SaveScopePlanner` still implements it for the paths that do.
  bool get discoverMissing => _scope == SaveScope.fixedCount;

  String? _countError;
  String? get countError => _countError;

  String? _nameError;
  String? get nameError => _nameError;

  /// What entries of this Collection have already cost on this device — the
  /// estimate's only input, and **settable late**. Working it out walks every
  /// Entry of the Collection, so the sheet paints first and the line appears
  /// when the answer arrives rather than every save waiting on it (V2-D62).
  List<int> _alreadyDownloadedBytes = const [];
  set alreadyDownloadedBytes(List<int> bytes) {
    _alreadyDownloadedBytes = bytes;
    notifyListeners();
  }

  bool get takesCount => _scope == SaveScope.fixedCount;

  /// OK is offered only while the number pad is up: with nothing being typed
  /// there is nothing to confirm and nothing to dismiss.
  bool get showsOkBar => takesCount && countFocus.hasFocus;

  int get ceiling => kDefaultSaveConfig.maxEntriesPerRun;

  /// One digit more than the ceiling needs, so a number just over the limit —
  /// which has an answer of its own — can still be typed, and nothing longer
  /// can overflow the parse.
  int get maxDigits => '$ceiling'.length + 1;

  /// `digitsOnly` is the only way text reaches the field, so the string is
  /// always digits: no decimal, no sign, no whitespace, and nothing pasteable
  /// that is not a number. Empty parses to null, which is the same answer as
  /// "not a usable number".
  int? get _parsed => int.tryParse(count.text);

  void chooseThisEntry() {
    // The typed count survives the switch — coming back and finding the number
    // gone would be the sheet forgetting something the user said. The keyboard
    // and a complaint about a number no longer in use do not.
    countFocus.unfocus();
    _scope = SaveScope.currentPageOnly;
    _countError = null;
    notifyListeners();
  }

  void chooseCounted() {
    // Idempotent on purpose. The count field sits inside this row's tap
    // target, so a tap that lands beside the number reaches here too — and
    // re-choosing the range it is already on must not clear a refusal the
    // user is in the middle of reading.
    if (_scope == SaveScope.fixedCount) return;
    _scope = SaveScope.fixedCount;
    _countError = null;
    notifyListeners();
  }

  void clearCountError() {
    if (_countError == null) return;
    _countError = null;
    notifyListeners();
  }

  void clearNameError() {
    if (_nameError == null) return;
    _nameError = null;
    notifyListeners();
  }

  /// "OK": accept the number that has been typed and put the keyboard away.
  ///
  /// Not a launch. It keeps the typed value, runs the same validation the
  /// launches run, drops focus, and stops there with the sheet still open on
  /// the buttons that do queue something.
  void confirmCount() {
    final n = _validatedCount();
    if (n == null) return;
    // 004 is 4 — normalised here rather than while typing, because rewriting
    // the field under the cursor as digits arrive is how a text field starts
    // swallowing keystrokes.
    if ('$n' != count.text) count.text = '$n';
    _countError = null;
    countFocus.unfocus();
    notifyListeners();
  }

  int? _validatedCount() {
    if (_scope != SaveScope.fixedCount) return 1;
    final n = _parsed;
    if (n == null || n < 1) {
      _refuseCount('Enter a whole number of 1 or more.');
      return null;
    }
    if (n > ceiling) {
      _refuseCount('At most $ceiling entries at a time.');
      return null;
    }
    return n;
  }

  void _refuseCount(String message) {
    _countError = message;
    countFocus.requestFocus();
    notifyListeners();
  }

  /// The name for a Collection about to exist. Null and refused **where it was
  /// typed**, exactly as a blank count is: a Collection with no name is not a
  /// thing this sheet can ask the domain to create.
  ///
  /// Returns null where nothing is being named, which is not a refusal — there
  /// is simply no name to give.
  String? _validatedName() {
    if (naming == null) return null;
    final typed = name.text.trim();
    if (typed.isEmpty) {
      _nameError = 'Give this collection a name.';
      nameFocus.requestFocus();
      notifyListeners();
      return null;
    }
    return typed;
  }

  /// What the user asked for, or **null when something was refused in place**
  /// — the error is on screen and the keyboard is back under the thumb.
  SaveScopeChoice? choiceFor(SaveStartMode start) {
    // Identity before quantity, which is the order they are read in: a sheet
    // that complained about the number under a nameless collection would be
    // answering the second question first.
    final collectionName = _validatedName();
    if (naming != null && collectionName == null) return null;
    final count = _validatedCount();
    if (count == null) return null;
    return SaveScopeChoice(
      // The only way a limit is built, here as everywhere: it clamps the
      // number to the same ceiling the sentence above states.
      limits: SaveLimits.forScope(_scope, requestedCount: count),
      start: start,
      // *This entry* is the page already in front of the user: there is
      // nothing after it to look for, so it never asks a site for anything.
      discoverMissing: discoverMissing,
      collectionName: collectionName,
    );
  }

  /// What this many entries would be expected to cost, in words, or null when
  /// nothing comparable has been downloaded — a number invented for a
  /// Collection nothing has been saved from is a guess wearing an estimate's
  /// clothes.
  String? get estimateSentence {
    final n = _parsed;
    if (n == null || n < 1) return null;
    return downloadEstimateSentence(
      estimateDownload(alreadyDownloaded: _alreadyDownloadedBytes, entries: n),
      formatBytes,
    );
  }

  @override
  void dispose() {
    countFocus
      ..removeListener(notifyListeners)
      ..dispose();
    count.dispose();
    nameFocus.dispose();
    name.dispose();
    super.dispose();
  }
}

/// *How much*, as a block the save sheet contains.
///
/// Draws itself from [controller] and writes nothing else: the surface around
/// it owns the launch, the scroll and [SaveCountOkBar].
class SaveScopeSection extends StatelessWidget {
  const SaveScopeSection({super.key, required this.controller});

  final SaveScopeController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final palette = AppPalette.of(context);
    final naming = controller.naming;
    final typed = controller.takesCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Collection about to exist is named at the top of the block that
        // decides how much of it to take (V2-D57).
        if (naming != null) ...[
          TextField(
            key: const ValueKey('collectionNameField'),
            controller: controller.name,
            focusNode: controller.nameFocus,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            style: TextStyle(fontSize: 14, color: palette.ink),
            onChanged: (_) => controller.clearNameError(),
            onSubmitted: (_) => controller.nameFocus.unfocus(),
            onTapOutside: (_) => controller.nameFocus.unfocus(),
            decoration: InputDecoration(
              labelText: 'Collection name',
              errorText: controller.nameError,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            naming.host.isEmpty
                ? 'This site becomes its first source. Nothing is merged with '
                      'anything you already have.'
                : 'First source · ${naming.host}',
            key: const ValueKey('newCollectionSourceFact'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: naming.host.isEmpty
                ? TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: palette.inkMuted,
                  )
                : monoStyle(size: 12, color: palette.inkFaint),
          ),
          const SizedBox(height: 12),
        ],
        _RangeOption(
          key: const ValueKey('saveScopeThisEntry'),
          icon: Icons.article_outlined,
          title: 'This entry',
          selected: !typed,
          onTap: controller.chooseThisEntry,
        ),
        const SizedBox(height: 6),
        _RangeOption(
          key: const ValueKey('saveScopeFromHere'),
          icon: Icons.tag,
          title: 'Entries from here',
          selected: typed,
          onTap: controller.chooseCounted,
          // The count lives **on** the row it belongs to (V2-D65): a field
          // under three descriptions was a form, and the number is the second
          // half of this one answer rather than a question of its own.
          trailing: typed
              ? SizedBox(
                  width: 74,
                  child: TextField(
                    key: const ValueKey('saveCountField'),
                    controller: controller.count,
                    focusNode: controller.countFocus,
                    // **Not autofocused.** Choosing a range is not asking for
                    // a keyboard: the launches sit directly below this, and
                    // the number pad would bury them (V2-D62).
                    // Unsigned and non-decimal, so the platform draws the
                    // plain number pad rather than a punctuation keyboard.
                    keyboardType: TextInputType.number,
                    // Honoured where the platform draws a return key. Android
                    // does; iOS's number pad has none, which is why it is
                    // never the only way out — see [SaveCountOkBar].
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    // A number and nothing else, however the text arrives.
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(controller.maxDigits),
                    ],
                    style: monoStyle(size: 17, color: palette.ink),
                    onChanged: (_) => controller.clearCountError(),
                    onSubmitted: (_) => controller.confirmCount(),
                    // Flutter leaves a mobile text field focused when the user
                    // taps elsewhere. Tapping the sheet is a plain way to say
                    // "I have finished typing", and this does not consume the
                    // tap. OK is inside the field's own tap region and so is
                    // not "elsewhere".
                    onTapOutside: (_) => controller.countFocus.unfocus(),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                )
              : null,
        ),
        if (typed) ...[
          // The refusal, where the number was typed. `errorText` went with the
          // field's own decoration when the field became a chip on the row, so
          // it is stated here instead — under the row, still next to it.
          if (controller.countError case final error?)
            Padding(
              key: const ValueKey('saveCountError'),
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: TextStyle(fontSize: 11.5, color: palette.danger),
              ),
            ),
          const SizedBox(height: 5),
          Text(
            // The ceiling is a number the user can see (CLAUDE.md), and the
            // count is inclusive — the two facts the number itself does not
            // carry, on the secondary line under the row that takes it. The
            // paragraph this replaces also said the site is read one page at a
            // time and can be stopped at any point; both are still said, by
            // the run's own surface, at the moment they are true.
            'This entry counts as the first · up to ${controller.ceiling}',
            key: const ValueKey('saveScopeReadsForwardNote'),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: palette.inkMuted,
            ),
          ),
          // Roughly what it will cost, from what this collection has actually
          // cost. Arrives when the walk that works it out finishes, which is
          // after the sheet is already usable.
          if (controller.estimateSentence case final sentence?)
            Padding(
              key: const ValueKey('saveScopeEstimate'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                sentence,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: palette.inkMuted,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The way out of a keyboard iOS gives no return key of its own.
///
/// Pinned by the surface **below its scrolling body**, so it is reachable
/// whatever the sheet is scrolled to, and offered only while that keyboard is
/// up ([SaveScopeController.showsOkBar]).
class SaveCountOkBar extends StatelessWidget {
  const SaveCountOkBar({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Inside the field's own tap region, so pressing OK does not count as
    // tapping away: without this the field would unfocus on pointer-down and
    // take the button out of the tree before the tap could complete.
    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Divider(height: 1, color: palette.hairline),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('saveCountOk'),
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: palette.primaryContainer,
              foregroundColor: palette.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: palette.primaryBorder),
              ),
            ),
            // Two letters do not say what they do, so the screen reader gets
            // the sentence instead.
            child: const Text(
              'OK',
              semanticsLabel: 'OK, use this number',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One range, on one line. Selected state is a border and a tick, never colour
/// alone.
class _RangeOption extends StatelessWidget {
  const _RangeOption({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  /// The count, for the range that takes one. It sits inside the row's tap
  /// target and is not part of it — a tap on the field is a tap on the field.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.primaryBorder : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: palette.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: palette.ink,
                  ),
                ),
              ),
              if (trailing case final field?) ...[
                const SizedBox(width: 8),
                field,
              ] else if (selected)
                Icon(Icons.check_circle, size: 19, color: palette.primary),
            ],
          ),
        ),
      ),
    );
  }
}
