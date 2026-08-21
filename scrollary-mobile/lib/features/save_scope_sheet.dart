import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/device_storage.dart';
import '../library/content_shape.dart';
import '../save/capture_mode.dart';
import '../save/size_estimate.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import '../library/entry_labels.dart';

/// What the user asked the save sheet to do (D58).
///
/// Both launches are offered in the sheet itself, next to the range that was
/// just chosen — there is no second drawer asking "queue or start?", because
/// that question is part of the same decision.
enum SaveSheetAction {
  /// Save it for later. Nothing navigates, nothing starts, the user stays on
  /// the page they were reading.
  addToQueue,

  /// Save now, in the Browser that is already on screen.
  startNow,

  /// The Browser is busy: show what is already running instead.
  viewActiveTask,
}

/// What the user chose in the save range sheet.
class SaveRangeChoice {
  const SaveRangeChoice(
    this.mode, {
    this.count = 1,
    required this.action,
    this.maxBytes,
    this.captureMode,
    this.captureModeIsUserSet = false,
    this.rememberForCollection = false,
  });

  final SaveScope mode;

  /// The number of new entries to save. Meaningful for
  /// [SaveScope.fixedCount]; 1 for the current page.
  final int count;

  /// The user's storage ceiling for this run, when they set one.
  final int? maxBytes;

  /// What to save — images, text, or text with images.
  ///
  /// **Independent of [mode].** How much of a collection to walk and what to
  /// take from each page are separate decisions, and folding them together is
  /// what made the previous `includeImages` boolean unusable: it could not
  /// say "an ordered sequence of full-size images" and "an article with
  /// pictures in it" are different things.
  ///
  /// Null when the page could not be analysed, which leaves the run to decide
  /// per page rather than forcing a guess.
  final CaptureMode? captureMode;

  /// True when the user changed the mode away from the detected default.
  final bool captureModeIsUserSet;

  /// "Use this for the whole collection." Applied once a collection is
  /// resolved, and re-validated against every later page.
  final bool rememberForCollection;

  /// Which of the two launches was pressed. Carried by the caller through the
  /// duplicate preflight, so "Start Save" that turns into "Re-download"
  /// still starts, and a queued request that turns into a re-download still
  /// waits (D58).
  final SaveSheetAction action;
}

/// The two save ranges — no count presets — and the two things that can be
/// done with the chosen range.
///
/// "Number of entries" takes a typed positive integer (new save attempts;
/// skipped existing entries do not consume it) and shows what disk space the
/// run can expect to use.
///
/// There is deliberately **no open-ended range**. The app used to offer
/// "until there is no next page", bounded by an internal ceiling the user
/// never saw — and, because the sheet had no field for it, it passed a count
/// of 1 and saved exactly one entry. A typed number is the same safety
/// guarantee stated plainly: the run stops where the person said it would.
///
/// [busyLabel] names whatever already owns the Browser. When it is set, direct
/// start is not on offer at all — queueing still is, because queueing starts
/// nothing and so cannot conflict with anything.
Future<SaveRangeChoice?> showSaveRangeSheet({
  required BuildContext context,
  required SaveConfig config,
  required DeviceStorage deviceStorage,
  String currentTitle = '',
  String? busyLabel,

  /// What this page can honestly be saved as. Measured before the sheet opens
  /// so it offers only what `SaveEngine` can actually carry out — a mode shown
  /// here and refused later would be a button that lies.
  CaptureCapabilities capabilities = const CaptureCapabilities.unanalysed(),

  /// The collection's remembered mode, when it has one and this page can
  /// honour it. Preselected; never forced.
  CaptureMode? preferredMode,

  /// Whether "remember for this collection" is worth offering — false for a
  /// page with no collection to remember anything on.
  bool canRemember = false,

  /// What entries already saved in this page's collection actually cost. The
  /// sheet's size estimate is built from this; empty is the honest state for a
  /// collection nothing has been saved from, and for a page in none.
  CollectionSizeHistory sizeHistory = const CollectionSizeHistory.empty(),
}) async {
  final free = await deviceStorage.freeBytes();
  if (!context.mounted) return null;

  // Not enough room for even one entry: say so and refuse here, before a
  // run exists — the run would refuse anyway, but a dead-on-arrival queue
  // entry teaches the user nothing.
  if (free != null && free < config.minFreeSpaceToStart) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.sd_card_alert, color: AppPalette.of(context).danger),
        title: const Text('Not enough space'),
        content: Text(
          '${_gb(free)} available — saving needs at least '
          '${_gb(config.minFreeSpaceToStart)} free. Existing downloads are '
          'not affected. Free some space, or remove offline entries you '
          'have finished.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return null;
  }

  return showModalBottomSheet<SaveRangeChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _RangeSheet(
      config: config,
      freeBytes: free,
      currentTitle: currentTitle,
      busyLabel: busyLabel,
      capabilities: capabilities,
      preferredMode: preferredMode,
      canRemember: canRemember,
      sizeHistory: sizeHistory,
    ),
  );
}

class _RangeSheet extends StatefulWidget {
  const _RangeSheet({
    required this.config,
    required this.freeBytes,
    required this.currentTitle,
    required this.busyLabel,
    required this.capabilities,
    required this.preferredMode,
    required this.canRemember,
    required this.sizeHistory,
  });

  final SaveConfig config;
  final int? freeBytes;
  final String currentTitle;
  final String? busyLabel;
  final CaptureCapabilities capabilities;
  final CaptureMode? preferredMode;
  final bool canRemember;
  final CollectionSizeHistory sizeHistory;

  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  // A harmless editable default, not a preset: the field opens with the range,
  // the value is fully replaceable, and nothing is enqueued until the user
  // presses one of the two launches.
  final _count = TextEditingController(text: '2');

  /// Held so the sheet can put the keyboard away itself, and call it back when
  /// a number is refused.
  ///
  /// iOS draws `TextInputType.number` as `UIKeyboardTypeNumberPad`, which has
  /// **no return key at all** — so `TextInputAction.done` is inert there and
  /// the OK button below the field is the only way out. Android's IME does
  /// draw a Done key and does honour it; both paths land on [_confirmCount].
  final _countFocus = FocusNode(debugLabel: 'saveCountField');

  SaveScope _mode = SaveScope.currentPageOnly;
  String? _countError;

  /// What to capture. Starts at the collection's remembered mode when this
  /// page can honour it, else at the detected default.
  CaptureMode? _capture;

  /// True once the user picks a mode themselves, so the run can tell a
  /// deliberate choice from a detected default and not re-decide on a resume.
  bool _captureIsUserSet = false;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _countFocus.addListener(_onCountFocusChanged);
    final preferred = widget.preferredMode;
    _capture = preferred != null && widget.capabilities.allows(preferred)
        ? preferred
        : widget.capabilities.defaultMode;
    // A remembered mode that survived validation starts the checkbox ticked:
    // the user already said this, and unticking is how they take it back.
    _remember =
        widget.canRemember && preferred != null && _capture == preferred;
  }

  @override
  void dispose() {
    _countFocus
      ..removeListener(_onCountFocusChanged)
      ..dispose();
    _count.dispose();
    super.dispose();
  }

  /// OK is offered only while the keyboard is up: with nothing being typed
  /// there is nothing to confirm and nothing to dismiss.
  void _onCountFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Set the moment an action is taken, so a second tap on either button
  /// cannot launch the same request twice while the first is being handled.
  bool _busy = false;

  /// One digit more than the ceiling needs, so every number the user might
  /// reasonably try — including one over the limit, which has an answer of its
  /// own — can be typed, and nothing longer can overflow the parse.
  int get _maxDigits => '${widget.config.maxEntriesPerRun}'.length + 1;

  /// `digitsOnly` is the only way text reaches the field, so the string is
  /// always digits: no decimal, no sign, no whitespace, and nothing pasteable
  /// that is not a number. Empty parses to null, which is the same answer as
  /// "not a usable number", and the length limit keeps it inside an int.
  int? get _parsedCount => int.tryParse(_count.text);

  /// Validate the typed count when it is the chosen range. Returns null and
  /// leaves the error on screen — with the keyboard back up, because an error
  /// about a number the user cannot currently reach is a dead end.
  int? _validatedCount() {
    if (_mode != SaveScope.fixedCount) return 1;
    final n = _parsedCount;
    if (n == null || n < 1) {
      _refuseCount('Enter a whole number of 1 or more.');
      return null;
    }
    if (n > widget.config.maxEntriesPerRun) {
      _refuseCount(
        'At most ${widget.config.maxEntriesPerRun} entries per run.',
      );
      return null;
    }
    return n;
  }

  /// Say what is wrong and put the keys back under the thumb.
  void _refuseCount(String message) {
    setState(() => _countError = message);
    _countFocus.requestFocus();
  }

  /// How many entries the estimate should be for, or null when there is no
  /// usable number to multiply.
  ///
  /// The current-entry range is always exactly one. The typed range is the
  /// number only while it passes the same validation the launches apply: an
  /// empty field, a zero and a number over the ceiling all mean "no estimate",
  /// which is the honest answer and keeps a stale figure off the screen while
  /// the error beside it says what is wrong.
  int? get _estimateCount {
    if (_mode != SaveScope.fixedCount) return 1;
    final n = _parsedCount;
    if (n == null || n < 1 || n > widget.config.maxEntriesPerRun) return null;
    return n;
  }

  /// What this save is likely to cost, from this collection's own entries when
  /// it has any. Recomputed on build because both of its inputs — the count and
  /// the capture mode — are things the user changes inside the sheet.
  SaveSizeEstimate get _estimate {
    final mode = _capture;
    return estimateSaveSize(
      entryCount: _estimateCount,
      historyBytes: widget.sizeHistory.forArtifact(mode?.artifact),
      fetchesImages: mode?.fetchesImages ?? true,
    );
  }

  /// "OK": accept the number that has been typed and put the keyboard away.
  ///
  /// **It is not a third launch.** It keeps the typed value, runs the same
  /// validation the two launches run so a bad number is answered where it was
  /// typed, drops focus — and stops there, with the sheet still open on the
  /// buttons that do start something. Confirming how much to save and
  /// authorising the save are separate acts, and an OK that quietly started a
  /// run would be exactly the button that lies this sheet is built to avoid.
  ///
  /// A number that does not validate leaves the keyboard up: it has just been
  /// told what is wrong, and the keys to fix it must stay under its thumb.
  void _confirmCount() {
    final n = _validatedCount();
    if (n == null) return;
    // 004 is 4 — normalised here rather than while typing, because rewriting
    // the field under the cursor as digits arrive is how a text field starts
    // swallowing keystrokes.
    if ('$n' != _count.text) _count.text = '$n';
    setState(() => _countError = null);
    _countFocus.unfocus();
  }

  /// True when this page can hold nothing at all — a video with no readable
  /// text is the case that produces it. Queueing a save that is going to
  /// refuse would be a button that lies just as much as offering a mode the
  /// engine cannot honour.
  bool get _nothingToSave =>
      widget.capabilities.analysed && !widget.capabilities.canSaveAnything;

  void _submit(SaveSheetAction action) {
    if (_busy || (_nothingToSave && action != SaveSheetAction.viewActiveTask)) {
      return;
    }
    final count = _validatedCount();
    if (count == null) return;
    setState(() => _busy = true);
    Navigator.pop(
      context,
      SaveRangeChoice(
        _mode,
        count: count,
        action: action,
        captureMode: _capture,
        captureModeIsUserSet: _captureIsUserSet,
        rememberForCollection: _remember && _capture != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final free = widget.freeBytes;
    final n = _parsedCount;
    final estimate = _estimate;
    final busy = widget.busyLabel;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        // The sheet is padded by the keyboard inset, so anything below the
        // scrolling body sits on the line directly above the keyboard. That is
        // where OK belongs, and pinning it there is the whole reason this is a
        // column rather than a bare scroll view: scrolling it into place
        // instead would race the field's own caret reveal, which scrolls to
        // show the caret and nothing under it.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    Text(
                      'Save entries',
                      style: serifStyle(size: 20, color: palette.ink),
                    ),
                    if (widget.currentTitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Starting from: ${widget.currentTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(size: 11.5, color: palette.inkMuted),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _CaptureSection(
                      capabilities: widget.capabilities,
                      selected: _capture,
                      onSelect: (mode) => setState(() {
                        _capture = mode;
                        _captureIsUserSet = true;
                      }),
                    ),
                    if (widget.canRemember && _capture != null) ...[
                      const SizedBox(height: 4),
                      _RememberToggle(
                        value: _remember,
                        label: _capture!.label,
                        onChanged: (v) => setState(() => _remember = v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Divider(height: 1, color: palette.hairline),
                    const SizedBox(height: 16),
                    Text(
                      'How many entries',
                      style: serifStyle(size: 15, color: palette.ink),
                    ),
                    const SizedBox(height: 10),
                    _RangeOption(
                      icon: Icons.article,
                      title: 'Current entry',
                      sub: 'Only the entry open in the browser',
                      selected: _mode == SaveScope.currentPageOnly,
                      // The typed count survives the switch — coming back to it and
                      // finding the number gone would be the sheet forgetting
                      // something the user said. The keyboard and any complaint
                      // about a number that is no longer being used do not.
                      onTap: () {
                        _countFocus.unfocus();
                        setState(() {
                          _mode = SaveScope.currentPageOnly;
                          _countError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 7),
                    _RangeOption(
                      icon: Icons.tag,
                      title: 'Number of entries',
                      sub:
                          'Type how many to save from here — up to '
                          '${widget.config.maxEntriesPerRun}',
                      selected: _mode == SaveScope.fixedCount,
                      // The range and the keys arrive together: choosing this range
                      // is asking to type a number, and the field autofocuses when
                      // it is built.
                      onTap: () => setState(() {
                        _mode = SaveScope.fixedCount;
                        _countError = null;
                      }),
                    ),
                    if (_mode == SaveScope.fixedCount) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('saveCountField'),
                        controller: _count,
                        focusNode: _countFocus,
                        autofocus: true,
                        // Unsigned and non-decimal, so the platform draws the plain
                        // number pad rather than a punctuation keyboard.
                        keyboardType: TextInputType.number,
                        // Honoured where the platform draws a return key. Android
                        // does; iOS's number pad has none, which is why it is never
                        // the only way out — see the OK bar under the sheet.
                        textInputAction: TextInputAction.done,
                        // A number and nothing else, however the text arrives —
                        // typed, dictated, pasted or from a hardware keyboard.
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_maxDigits),
                        ],
                        style: monoStyle(size: 20, color: palette.ink),
                        onChanged: (_) => setState(() => _countError = null),
                        onSubmitted: (_) => _confirmCount(),
                        // Flutter leaves a mobile text field focused when the user
                        // taps elsewhere. Tapping the sheet is a plain way to say "I
                        // have finished typing", and this does not consume the tap,
                        // so whatever was tapped still does its own job. OK is inside
                        // the field's own tap region and so is not "elsewhere".
                        onTapOutside: (_) => _countFocus.unfocus(),
                        decoration: InputDecoration(
                          labelText: 'How many new entries?',
                          errorText: _countError,
                          errorMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'New saves only — already saved entries that get skipped do '
                        'not use up this number. The save stops here, or sooner if '
                        'the collection ends.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: palette.inkMuted,
                        ),
                      ),
                      if (n != null &&
                          n >= 1 &&
                          n <= widget.config.maxEntriesPerRun) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Save ${kPlainEntryLabels.count(n)}'
                          '${widget.currentTitle.isNotEmpty ? ' starting from "${widget.currentTitle}"' : ''}.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: palette.inkMuted,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _estimateLine(estimate),
                      key: const ValueKey('saveEstimatedSize'),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      free == null
                          ? 'Free space could not be checked — it will be checked '
                                'again before each entry.'
                          : 'Available: ${_gb(free)}. Space is re-checked before '
                                'every entry.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (busy != null)
                      _BusyNote(label: busy)
                    else
                      Text(
                        'Start Save opens and uses the current Browser now.\n'
                        'Add to Queue saves it for later.',
                        key: const ValueKey('saveLaunchExplainer'),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: palette.inkFaint,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('saveAddToQueue'),
                            onPressed: _busy || _nothingToSave
                                ? null
                                : () => _submit(SaveSheetAction.addToQueue),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              foregroundColor: palette.inkStrong,
                              side: BorderSide(color: palette.borderStrong),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Add to Queue',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: busy != null
                              ? FilledButton(
                                  key: const ValueKey('saveViewActiveTask'),
                                  onPressed: _busy
                                      ? null
                                      : () => _submit(
                                          SaveSheetAction.viewActiveTask,
                                        ),
                                  style: _primaryStyle,
                                  child: const Text(
                                    'View active task',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13.5),
                                  ),
                                )
                              : FilledButton(
                                  key: const ValueKey('saveStartNow'),
                                  onPressed: _busy || _nothingToSave
                                      ? null
                                      : () => _submit(SaveSheetAction.startNow),
                                  style: _primaryStyle,
                                  child: const Text(
                                    'Start Save',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13.5),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('saveSheetCancel'),
                        onPressed: () => Navigator.pop(context),
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
            if (_mode == SaveScope.fixedCount && _countFocus.hasFocus)
              _ConfirmCountBar(onPressed: _confirmCount),
          ],
        ),
      ),
    );
  }

  /// The size line: a range, and what the range is built from.
  ///
  /// Never a bare figure. An estimate that reads as a measurement is worse than
  /// no estimate, because the user cannot tell which one they were given —
  /// which is exactly what "up to ~1.0 GB", computed by multiplying a flat
  /// constant by the entry count, was doing to ordinary saves.
  static String _estimateLine(SaveSizeEstimate estimate) {
    final label = estimate.sizeLabel;
    if (label == null) return kSizeUnknownMessage;
    return 'Estimated size: $label — ${estimate.qualifier}.';
  }

  static final ButtonStyle _primaryStyle = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 13),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

/// "OK": the way out of the number pad, drawn by the app because iOS does not
/// draw one.
///
/// iOS renders `TextInputType.number` as `UIKeyboardTypeNumberPad`, a pad with
/// no return key, so `TextInputAction.done` has nothing to label there and
/// nothing but this can hand the focus back. Android's IME does draw a Done
/// key; both arrive at the same [_RangeSheetState._confirmCount], so a number
/// is confirmed the same way on either platform.
///
/// Sits below the sheet's scrolling body, which the keyboard inset already
/// pads — so it lands on the line directly above the keyboard and stays there,
/// whatever the body above it is scrolled to. Styled as the end of *this step*
/// and visibly not the solid primary of *Start Save*, which is the thing that
/// actually saves.
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

/// Why direct start is not on offer, without hiding the queue action behind
/// the same explanation.
class _BusyNote extends StatelessWidget {
  const _BusyNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const ValueKey('saveBusyNote'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.warnContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.warnBorder),
      ),
      child: Text(
        '$label. Only one save can use the Browser at a time — this '
        'request can still wait in the queue.',
        style: TextStyle(
          fontSize: 11.5,
          height: 1.45,
          color: palette.onWarnContainer,
        ),
      ),
    );
  }
}

/// The capture-mode block: what will be taken off this page.
///
/// Every honourable mode is shown as a live option and every unavailable one
/// is shown **disabled with its reason**, rather than hidden. A missing option
/// reads as a bug; a greyed one with "no readable text was found on this page"
/// beside it reads as an answer.
class _CaptureSection extends StatelessWidget {
  const _CaptureSection({
    required this.capabilities,
    required this.selected,
    required this.onSelect,
  });

  final CaptureCapabilities capabilities;
  final CaptureMode? selected;
  final ValueChanged<CaptureMode> onSelect;

  static const _icons = {
    CaptureMode.imageSequence: Icons.photo_library_outlined,
    CaptureMode.textOnly: Icons.notes,
    CaptureMode.textAndImages: Icons.article_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What to save', style: serifStyle(size: 15, color: palette.ink)),
        const SizedBox(height: 6),
        Text(
          _summary(),
          key: const ValueKey('captureDetectionSummary'),
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: palette.inkMuted,
          ),
        ),
        if (capabilities.videoDominant) ...[
          const SizedBox(height: 10),
          _VideoNotice(hasAlternative: capabilities.canSaveAnything),
        ],
        const SizedBox(height: 10),
        for (final mode in CaptureMode.values) ...[
          _RangeOption(
            key: ValueKey('captureMode_${mode.name}'),
            icon: _icons[mode]!,
            title: mode.label,
            sub: capabilities.allows(mode)
                ? mode.description
                : (capabilities.blocked[mode]?.message ??
                      'Not possible on this page.'),
            selected: selected == mode,
            enabled: capabilities.allows(mode),
            onTap: () => onSelect(mode),
          ),
          const SizedBox(height: 7),
        ],
      ],
    );
  }

  /// One line of what was detected, and how sure. Never presents a
  /// low-confidence guess as a firm answer — the sheet says "this looks like",
  /// and every alternative stays one tap away regardless.
  String _summary() {
    if (!capabilities.analysed) {
      return 'This page could not be analysed, so every option is offered. '
          'Pick what fits.';
    }
    if (!capabilities.canSaveAnything) {
      return 'Nothing on this page can be saved offline.';
    }
    final kind = switch (capabilities.content.kind) {
      ContentKind.imageDominant => 'a page of full-size images',
      ContentKind.article => 'an article',
      ContentKind.datedPost => 'a dated post',
      ContentKind.sequentialText => 'part of a longer text',
      ContentKind.longFormDocument => 'a long document',
      ContentKind.paginatedDocument => 'one page of a document',
      ContentKind.videoDominant => 'a video page',
      ContentKind.standalonePage || ContentKind.unknownWebContent => null,
    };
    // "Not classified" is a real answer and gets its own sentence rather than
    // being forced through the "this looks like …" template, which would read
    // as "this looks like not something we could classify".
    if (kind == null) {
      return 'This page did not say clearly what it is. Pick what fits.';
    }
    return capabilities.content.confidence.isActionable
        ? 'This looks like $kind.'
        : 'This might be $kind — the page did not say clearly.';
  }
}

/// Says plainly that video is not saved, and what will happen instead.
class _VideoNotice extends StatelessWidget {
  const _VideoNotice({required this.hasAlternative});

  final bool hasAlternative;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const ValueKey('videoNotSavedNotice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.videocam_off_outlined, size: 18, color: palette.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasAlternative
                  ? 'Video is not saved. The readable text on this page can '
                        'be, and the entry will link back to the original for '
                        'anything that plays.'
                  : 'Video is not saved, and this page has no readable text '
                        'to save instead. Open it in the Browser when you '
                        'want to watch it.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Use this for the whole collection."
class _RememberToggle extends StatelessWidget {
  const _RememberToggle({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      key: const ValueKey('rememberCaptureMode'),
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Use "$label" for this collection from now on',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: palette.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeOption extends StatelessWidget {
  const _RangeOption({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  /// A disabled option stays on screen with its reason in [sub]. Hiding it
  /// would answer "why can I not save the text here" with silence.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.primaryBorder : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled ? palette.primary : palette.inkFaint,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: enabled ? palette.ink : palette.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: enabled ? palette.inkMuted : palette.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 19, color: palette.primary),
            ],
          ),
        ),
      ),
    );
  }
}

String _gb(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).round()} MB';
}
