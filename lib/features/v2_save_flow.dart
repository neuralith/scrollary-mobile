import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/recognition_index.dart';
import '../domain/domain.dart';
import '../library_ui/providers.dart';
import '../recognition/history.dart';
import '../recognition/recognise.dart';
import '../save/capture_policy.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';

/// The Browser's save flow over the V2 library.
///
/// The rule carried over from V1 unchanged: on a restricted host the save
/// control is **absent** — not disabled, not a warning — which is why
/// [v2SaveAvailable] is asked before the control is even built. Everything
/// else is new underneath: the page is recognised against the V2 library, the
/// save enqueues a V2 task for `(entry, location)`, and nothing captures
/// until the user's explicit Start.
bool v2SaveAvailable(String url) =>
    url.startsWith('http') && !isCaptureRestricted(url);

/// What the sheet knows about the page it was opened for.
class V2PageStatus {
  const V2PageStatus({
    required this.result,
    this.entryId,
    this.hasCopy = false,
    this.task,
  });

  final RecognitionResult result;

  /// The Entry this page already is, when the address is known.
  final String? entryId;

  /// This device already holds readable bytes for it.
  final bool hasCopy;

  /// The open or most recent queue row covering it.
  final SaveTask? task;
}

Future<V2PageStatus> v2PageStatusFor(WidgetRef ref, String url) async {
  final services = ref.read(libraryUiServicesProvider);
  final recogniser = Recogniser(
    index: RecognitionIndexOf(services).index,
    collections: services.collections,
    reading: services.reading,
  );
  final result = await recogniser.recognise(url);
  if (result is! RecognisedLocation) {
    return V2PageStatus(result: result);
  }
  final entryId = result.entry.id;
  return V2PageStatus(
    result: result,
    entryId: entryId,
    hasCopy: await services.offline.activeCopyOf(entryId) != null,
    task: await services.queue.openTaskFor(entryId),
  );
}

/// Saving this page: make sure the library holds it, then queue the capture.
///
/// Returns the sentence the sheet shows, or null when everything is queued
/// and there is nothing to explain.
Future<String?> v2SavePage(
  WidgetRef ref, {
  required String url,
  required String pageTitle,
}) async {
  if (!v2SaveAvailable(url)) return kCaptureRestrictedMessage;
  final services = ref.read(libraryUiServicesProvider);
  final status = await v2PageStatusFor(ref, url);

  String entryId;
  String? locationId;
  switch (status.result) {
    case RecognisedLocation(:final entry, :final location):
      entryId = entry.id;
      locationId = location.id;
    case RecognisedSource(:final source, :final collection, :final keys):
      // The page sits on a known Source at a new address: the Entry joins its
      // Collection, honestly unplaced until something numbers it.
      final (entry, violation) = await services.entries.createInCollection(
        collectionId: collection.id,
        placement: Placement.unplaced,
        title: pageTitle,
      );
      if (entry == null) {
        return 'Could not add this page: ${violation?.message}';
      }
      final (location, locViolation) = await services.entries.addLocation(
        entryId: entry.id,
        url: url,
        urlKey: keys.urlKey,
        sourceId: source.id,
        discoveryBasis: 'userSave',
      );
      if (location == null) {
        return 'Could not add this page: ${locViolation?.message}';
      }
      entryId = entry.id;
      locationId = location.id;
    case Unrecognised():
      // A page the library knows nothing about becomes a standalone item,
      // through the same promotion path history uses.
      final history = HistoryStore(services.db);
      final (row, violation) = await history.recordVisit(
        url: url,
        title: pageTitle,
        userInitiated: true,
      );
      if (row == null) return 'This page can’t be saved: ${violation?.message}';
      final promotion = LibraryPromotion(
        folders: services.folders,
        collections: services.collections,
        entries: services.entries,
      );
      final outcome = await promotion.promoteToLibrary(
        row: row,
        result: status.result,
      );
      if (outcome.entryId == null) {
        return 'Could not add this page: ${outcome.violation?.message}';
      }
      entryId = outcome.entryId!;
      locationId = outcome.locationId;
  }

  final enqueue = await services.queue.enqueue(
    entryId: entryId,
    locationId: locationId,
    locationUrl: url,
  );
  if (enqueue.refusedReason != null) return enqueue.refusedReason;
  return null;
}

/// Follow the Collection this page's Source belongs to.
Future<void> v2FollowCollection(WidgetRef ref, String collectionId) =>
    ref.read(libraryUiServicesProvider).collections.follow(collectionId);

/// A small helper so the recogniser can be built from the one services
/// object without the panel importing the index type directly.
class RecognitionIndexOf {
  RecognitionIndexOf(this.services);
  final LibraryUiServices services;
  RecognitionIndex get index => RecognitionIndex(services.db);
}

/// The sheet behind the Browser's save control.
class V2SavePanel extends ConsumerStatefulWidget {
  const V2SavePanel({super.key, required this.url, required this.pageTitle});

  final String url;
  final String pageTitle;

  @override
  ConsumerState<V2SavePanel> createState() => _V2SavePanelState();
}

class _V2SavePanelState extends ConsumerState<V2SavePanel> {
  V2PageStatus? _status;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await v2PageStatusFor(ref, widget.url);
    if (mounted) setState(() => _status = status);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final message = await v2SavePage(
      ref,
      url: widget.url,
      pageTitle: widget.pageTitle,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
    await _refresh();
  }

  Future<void> _start() async {
    final starter = ref.read(saveQueueStarterProvider);
    if (starter != null) await starter();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = _status;
    final task = status?.task;
    final result = status?.result;

    final lines = <Widget>[];
    if (status == null) {
      lines.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else {
      final describe = switch (result) {
        RecognisedLocation(:final collection) =>
          collection == null
              ? 'In your library.'
              : 'In your library — ${collection.name}.',
        RecognisedSource(:final collection) =>
          'On a site you know — ${collection.name}.',
        _ => 'Not in your library yet.',
      };
      lines.add(Text(describe, style: TextStyle(color: palette.inkMuted)));
      if (status.hasCopy) {
        lines.add(
          Text('On this device.', style: TextStyle(color: palette.inkMuted)),
        );
      }
      if (task != null && !task.state.isTerminal) {
        lines.add(
          Text(
            task.state == SaveTaskState.queued
                ? 'Queued — waiting for Start.'
                : 'Saving…',
            style: TextStyle(color: palette.inkMuted),
          ),
        );
      }
      if (_message != null) {
        lines.add(Text(_message!, style: TextStyle(color: palette.inkMuted)));
      }
    }

    final canSave =
        status != null && (task == null || task.state.isTerminal) && !_busy;
    final canStart =
        task != null && task.state == SaveTaskState.queued && !_busy;
    final source = result is RecognisedSource ? result : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.pageTitle.isEmpty ? widget.url : widget.pageTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...[
              for (final line in lines)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: line),
            ],
            const SizedBox(height: 8),
            if (source != null && !source.followed)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await v2FollowCollection(ref, source.collection.id);
                        await _refresh();
                      },
                child: Text('Follow ${source.collection.name}'),
              ),
            if (canSave)
              FilledButton(
                key: const ValueKey('v2SaveButton'),
                onPressed: _save,
                child: const Text('Save for offline'),
              ),
            if (canStart)
              FilledButton.tonal(
                key: const ValueKey('v2StartButton'),
                onPressed: _start,
                child: const Text('Start'),
              ),
          ],
        ),
      ),
    );
  }
}
