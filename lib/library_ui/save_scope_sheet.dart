/// *How much?* — the question the V2 save sheet lost, restored.
///
/// This is V1's range sheet, ported to the V2 domain rather than redesigned.
/// Its numeric interaction was device-tested and every detail of it is here on
/// purpose:
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
/// * OK is not a third launch. It confirms the number and stops.
///
/// Two rules from CLAUDE.md the sheet states rather than merely obeys: the
/// ceiling is a number the user can see, and **a queued download waits for an
/// explicit Start**. *Start now* is that Start, taken in the same tap — it is
/// not a second kind of start, and nothing here runs anything on its own.
///
/// **Two ranges take a count, and they answer different questions**
/// (docs/V2_SAVE_FLOW.md §4). *Entries from here* counts on the **Source**:
/// the ones the library has not seen are found by reading this site forward
/// from the page in front of the user. *Entries already in your library*
/// counts on the library and opens nothing. Both count the entry the user is
/// on as the first one, and the sheet says so in words rather than leaving it
/// to be inferred from a number.
///
/// **A Collection that does not exist yet is named here**
/// ([NewCollectionNaming], V2-D57). The sheet already printed the Collection's
/// name in its header, so the name arrived confirmed by a screen of its own
/// whose only content was one text field. That screen is gone: the header line
/// becomes the field, the site about to become the Collection's first Source
/// is stated beside it, and the answer travels back on
/// [SaveScopeChoice.collectionName]. Which
/// Collection this is remains the picker's question and is not asked here —
/// this sheet only ever names the new one the user has already chosen to
/// start.
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
  /// Null whenever the sheet was not naming one, which is every other caller.
  final String? collectionName;
}

/// Ask how much of [collectionName] to download, starting from this page.
///
/// Returns null when the sheet was dismissed — nothing chosen, nothing queued.
/// [launchActions] supplies the launch row, so the surface that owns the
/// foreground boundary can offer *its* rows here rather than in a second sheet
/// afterwards. It is handed a callback that validates the typed count and pops
/// with the chosen mode; it must not pop the sheet itself. Null falls back to
/// the two launches this lane can describe on its own, which is what a test
/// with no such surface around it sees.
///
/// [naming] is set only for a Collection that does not exist yet: the header
/// line becomes an editable field, and the confirmed name comes back on
/// [SaveScopeChoice.collectionName] (V2-D57). [collectionName] is still what
/// the sheet is *about* either way, and is the field's initial value when
/// [naming] is set.
Future<SaveScopeChoice?> showSaveScopeSheet(
  BuildContext context, {
  required String collectionName,
  int initialCount = 2,
  List<int> alreadyDownloadedBytes = const [],
  Widget Function(BuildContext, void Function(SaveStartMode))? launchActions,
  NewCollectionNaming? naming,
}) {
  return showModalBottomSheet<SaveScopeChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _SaveScopeSheet(
      collectionName: collectionName,
      initialCount: initialCount,
      alreadyDownloadedBytes: alreadyDownloadedBytes,
      launchActions: launchActions,
      naming: naming,
    ),
  );
}

class _SaveScopeSheet extends StatefulWidget {
  const _SaveScopeSheet({
    required this.collectionName,
    required this.initialCount,
    this.alreadyDownloadedBytes = const [],
    this.launchActions,
    this.naming,
  });

  final String collectionName;
  final int initialCount;

  /// The Collection this sheet is about to bring into existence, when it is
  /// about to. See [showSaveScopeSheet].
  final NewCollectionNaming? naming;

  /// The launch row, when a caller owns one. See [showSaveScopeSheet].
  final Widget Function(BuildContext, void Function(SaveStartMode))?
  launchActions;

  /// What entries of this collection have already cost on this device. The
  /// only input the estimate has, and empty is an honest state.
  final List<int> alreadyDownloadedBytes;

  @override
  State<_SaveScopeSheet> createState() => _SaveScopeSheetState();
}

class _SaveScopeSheetState extends State<_SaveScopeSheet> {
  /// What this many entries would be expected to cost, in words.
  Widget? _estimateLine(AppPalette palette) {
    final count = _parsed;
    if (count == null || count < 1) return null;
    final sentence = downloadEstimateSentence(
      estimateDownload(
        alreadyDownloaded: widget.alreadyDownloadedBytes,
        entries: count,
      ),
      formatBytes,
    );
    if (sentence == null) return null;
    return Padding(
      key: const ValueKey('saveScopeEstimate'),
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        sentence,
        style: TextStyle(fontSize: 11.5, height: 1.45, color: palette.inkMuted),
      ),
    );
  }

  /// A harmless editable default, not a preset: the field opens with the
  /// range, the value is fully replaceable, and nothing is queued until one of
  /// the two launches is pressed.
  late final TextEditingController _count = TextEditingController(
    text: '${widget.initialCount}',
  );

  /// Held so the sheet can put the keyboard away itself, and call it back when
  /// a number is refused.
  final _countFocus = FocusNode(debugLabel: 'saveCountField');

  /// The new Collection's name, and the focus a blank one is sent back to.
  ///
  /// **Not autofocused.** The field opens holding what the page called the
  /// work, and the common answer to it is *yes*: raising a keyboard over the
  /// ranges and the launches would make confirming the suggestion cost a
  /// dismissal, which is the opposite of what removing the naming screen was
  /// for. Tapping it is how the minority who correct it get there.
  late final TextEditingController _name = TextEditingController(
    text: widget.naming?.suggestedName ?? '',
  );
  final _nameFocus = FocusNode(debugLabel: 'saveCollectionNameField');

  String? _nameError;

  SaveScope _scope = SaveScope.currentPageOnly;

  /// Which of the two counted ranges is selected, while [_scope] is
  /// [SaveScope.fixedCount]. It survives a switch to *This entry* for the same
  /// reason the typed number does: coming back and finding the answer changed
  /// would be the sheet forgetting something the user said.
  bool _discoverMissing = true;

  String? _countError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _countFocus.addListener(_onCountFocusChanged);
  }

  @override
  void dispose() {
    _countFocus
      ..removeListener(_onCountFocusChanged)
      ..dispose();
    _count.dispose();
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  /// OK is offered only while the keyboard is up: with nothing being typed
  /// there is nothing to confirm and nothing to dismiss.
  void _onCountFocusChanged() {
    if (mounted) setState(() {});
  }

  int get _ceiling => kDefaultSaveConfig.maxEntriesPerRun;

  /// One digit more than the ceiling needs, so a number just over the limit —
  /// which has an answer of its own — can still be typed, and nothing longer
  /// can overflow the parse.
  int get _maxDigits => '$_ceiling'.length + 1;

  /// `digitsOnly` is the only way text reaches the field, so the string is
  /// always digits: no decimal, no sign, no whitespace, and nothing pasteable
  /// that is not a number. Empty parses to null, which is the same answer as
  /// "not a usable number".
  int? get _parsed => int.tryParse(_count.text);

  /// Validate the typed count when it is the chosen range. Returns null and
  /// leaves the error on screen, with the keyboard back up.
  int? _validated() {
    if (_scope != SaveScope.fixedCount) return 1;
    final n = _parsed;
    if (n == null || n < 1) {
      _refuse('Enter a whole number of 1 or more.');
      return null;
    }
    if (n > _ceiling) {
      _refuse('At most $_ceiling entries at a time.');
      return null;
    }
    return n;
  }

  void _refuse(String message) {
    setState(() => _countError = message);
    _countFocus.requestFocus();
  }

  /// The name for a Collection about to exist. Null and refused **where it was
  /// typed**, exactly as a blank count is: a Collection with no name is not a
  /// thing this sheet can ask the domain to create.
  ///
  /// Returns null for a sheet that is not naming anything, which is not a
  /// refusal — there is simply no name to give.
  String? _validatedName() {
    if (widget.naming == null) return null;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give this collection a name.');
      _nameFocus.requestFocus();
      return null;
    }
    return name;
  }

  /// "OK": accept the number that has been typed and put the keyboard away.
  ///
  /// Not a launch. It keeps the typed value, runs the same validation the two
  /// launches run, drops focus, and stops there with the sheet still open on
  /// the buttons that do queue something.
  void _confirmCount() {
    final n = _validated();
    if (n == null) return;
    // 004 is 4 — normalised here rather than while typing, because rewriting
    // the field under the cursor as digits arrive is how a text field starts
    // swallowing keystrokes.
    if ('$n' != _count.text) _count.text = '$n';
    setState(() => _countError = null);
    _countFocus.unfocus();
  }

  void _submit(SaveStartMode start) {
    if (_busy) return;
    // Identity before quantity, which is the order they are read in: a sheet
    // that complained about the number under a nameless collection would be
    // answering the second question first.
    final name = _validatedName();
    if (widget.naming != null && name == null) return;
    final count = _validated();
    if (count == null) return;
    setState(() => _busy = true);
    Navigator.of(context).pop(
      SaveScopeChoice(
        // The only way a limit is built, here as everywhere: it clamps the
        // number to the same ceiling the sentence above states.
        limits: SaveLimits.forScope(_scope, requestedCount: count),
        start: start,
        // *This entry* is the page already in front of the user: there is
        // nothing after it to look for, so it never asks a site for anything.
        discoverMissing: _scope == SaveScope.fixedCount && _discoverMissing,
        collectionName: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typed = _scope == SaveScope.fixedCount;
    final naming = widget.naming;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        // The keyboard inset pads the sheet, so anything below the scrolling
        // body sits on the line directly above the keyboard. That is where OK
        // belongs, and pinning it there is why this is a column rather than a
        // bare scroll view.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    Text(
                      naming == null ? 'How many entries' : 'New collection',
                      style: serifStyle(size: 20, color: palette.ink),
                    ),
                    const SizedBox(height: 4),
                    // One header, two shapes. Without a Collection to name it
                    // says which one this is about; with one, the same line
                    // becomes the field that decides — and the site about to
                    // become its first Source is stated rather than implied,
                    // because "this site" is the only thing the old naming
                    // screen said about it and it never named it.
                    if (naming != null) ...[
                      TextField(
                        key: const ValueKey('collectionNameField'),
                        controller: _name,
                        focusNode: _nameFocus,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: 14, color: palette.ink),
                        onChanged: (_) => setState(() => _nameError = null),
                        onSubmitted: (_) => _nameFocus.unfocus(),
                        onTapOutside: (_) => _nameFocus.unfocus(),
                        decoration: InputDecoration(
                          labelText: 'Collection name',
                          errorText: _nameError,
                          errorMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        naming.host.isEmpty
                            ? 'This site becomes its first source. Nothing is '
                                  'merged with anything you already have.'
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
                      Text(
                        'How many entries, starting at this page.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: palette.inkMuted,
                        ),
                      ),
                    ] else
                      Text(
                        'From ${widget.collectionName}, starting at this page.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: palette.inkMuted,
                        ),
                      ),
                    const SizedBox(height: 14),
                    _RangeOption(
                      key: const ValueKey('saveScopeThisEntry'),
                      icon: Icons.article_outlined,
                      title: 'This entry',
                      sub: 'Only the page you are on.',
                      selected: !typed,
                      // The typed count survives the switch — coming back and
                      // finding the number gone would be the sheet forgetting
                      // something the user said. The keyboard and a complaint
                      // about a number no longer in use do not.
                      onTap: () {
                        _countFocus.unfocus();
                        setState(() {
                          _scope = SaveScope.currentPageOnly;
                          _countError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 7),
                    _RangeOption(
                      key: const ValueKey('saveScopeFromHere'),
                      icon: Icons.tag,
                      title: 'Entries from here',
                      sub:
                          'Type how many to download from this page onward — '
                          'up to $_ceiling.',
                      selected: typed && _discoverMissing,
                      // The range and the keys arrive together: choosing this
                      // range is asking to type a number, and the field
                      // autofocuses when it is built.
                      onTap: () => setState(() {
                        _scope = SaveScope.fixedCount;
                        _discoverMissing = true;
                        _countError = null;
                      }),
                    ),
                    const SizedBox(height: 7),
                    _RangeOption(
                      key: const ValueKey('saveScopeKnownOnly'),
                      icon: Icons.library_books_outlined,
                      title: 'Entries already in your library',
                      sub:
                          'The same count, but only the ones your library '
                          'already knows.',
                      selected: typed && !_discoverMissing,
                      onTap: () => setState(() {
                        _scope = SaveScope.fixedCount;
                        _discoverMissing = false;
                        _countError = null;
                      }),
                    ),
                    if (typed) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('saveCountField'),
                        controller: _count,
                        focusNode: _countFocus,
                        autofocus: true,
                        // Unsigned and non-decimal, so the platform draws the
                        // plain number pad rather than a punctuation keyboard.
                        keyboardType: TextInputType.number,
                        // Honoured where the platform draws a return key.
                        // Android does; iOS's number pad has none, which is
                        // why it is never the only way out — see the OK bar.
                        textInputAction: TextInputAction.done,
                        // A number and nothing else, however the text arrives.
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_maxDigits),
                        ],
                        style: monoStyle(size: 20, color: palette.ink),
                        onChanged: (_) => setState(() => _countError = null),
                        onSubmitted: (_) => _confirmCount(),
                        // Flutter leaves a mobile text field focused when the
                        // user taps elsewhere. Tapping the sheet is a plain
                        // way to say "I have finished typing", and this does
                        // not consume the tap. OK is inside the field's own
                        // tap region and so is not "elsewhere".
                        onTapOutside: (_) => _countFocus.unfocus(),
                        decoration: InputDecoration(
                          // The count's meaning, at the point it is typed:
                          // ten from entry 101 is 101 through 110, and a
                          // sheet that leaves that to be inferred has told
                          // half its readers the wrong thing.
                          labelText: 'How many entries, counting this one?',
                          errorText: _countError,
                          errorMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _discoverMissing
                            // What the operation is, in the words the user
                            // can act on: where it starts, how it goes on,
                            // what it does not do, and that it ends when they
                            // say so. Said once and briefly — the option
                            // above already named the range, and a paragraph
                            // that restates it is a paragraph nobody
                            // finishes.
                            ? '5 means this entry and the next four. '
                                  'Scrollary downloads this page, then reads '
                                  'forward for the next one and downloads '
                                  'that — one page at a time, nothing else '
                                  'downloaded, and you can stop it at any '
                                  'point.'
                            : '5 means this entry and the next four. Only '
                                  'entries your library already knows, and '
                                  'this site is not opened — if it knows '
                                  'fewer, Scrollary says so.',
                        key: _discoverMissing
                            ? const ValueKey('saveScopeReadsForwardNote')
                            : const ValueKey('saveScopeLibraryOnlyNote'),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: palette.inkMuted,
                        ),
                      ),
                      // Roughly what it will cost, from what this collection
                      // has actually cost. Absent when nothing comparable has
                      // been downloaded, because a number invented for a
                      // collection nothing has been saved from is a guess
                      // wearing an estimate's clothes.
                      ?_estimateLine(palette),
                    ],
                    const SizedBox(height: 12),
                    // Said here only when the launch rows below do not say it
                    // themselves. The gate's own rows each carry a sentence
                    // about what happens and where the user waits, and a
                    // fourth statement of the same rule above them is text
                    // people learn to skip.
                    if (widget.launchActions == null) ...[
                      Text(
                        'Queued downloads wait for Start. Nothing downloads '
                        'on its own, and nothing at all runs while the app is '
                        'not in front of you.',
                        key: const ValueKey('saveScopeLaunchExplainer'),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: palette.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // The launch, taken once. The caller's rows when it has
                    // them — the same rows the foreground boundary offers
                    // everywhere else — and this lane's two when it does not.
                    if (widget.launchActions case final build?)
                      build(context, _busy ? (_) {} : _submit)
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey('saveScopeAddToQueue'),
                              onPressed: _busy
                                  ? null
                                  : () => _submit(SaveStartMode.queueOnly),
                              child: const Text(
                                'Queue only',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('saveScopeStartNow'),
                              onPressed: _busy
                                  ? null
                                  : () => _submit(SaveStartMode.startNow),
                              child: const Text(
                                'Start now',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('saveScopeCancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The way out of a keyboard iOS gives no return key of its own.
            // Offered only while that keyboard is up, and pinned here so it is
            // reachable whatever the sheet above it is scrolled to.
            if (typed && _countFocus.hasFocus)
              _ConfirmCountBar(onPressed: _confirmCount),
          ],
        ),
      ),
    );
  }
}

/// One range, with its own sentence. Selected state is a border and a tick,
/// never colour alone.
class _RangeOption extends StatelessWidget {
  const _RangeOption({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? palette.primaryContainer : palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.primaryBorder : palette.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? palette.onPrimaryContainer : palette.inkMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? palette.onPrimaryContainer
                          : palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: selected
                          ? palette.onPrimaryContainer
                          : palette.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: palette.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

/// "OK": the way out of the number pad, drawn by the app because iOS does not
/// draw one.
///
/// Sits below the sheet's scrolling body, which the keyboard inset already
/// pads — so it lands on the line directly above the keyboard and stays there,
/// whatever the body above it is scrolled to.
class _ConfirmCountBar extends StatelessWidget {
  const _ConfirmCountBar({required this.onPressed});

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
