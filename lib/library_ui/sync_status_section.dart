/// `Settings → Sync`, and nothing else (roadmap D7).
///
/// This is the **only** surface in the app that says anything about
/// synchronisation. Nothing about it appears in the Library, the Browser or
/// the reader; a healthy sync produces no event, no badge and no message
/// anywhere, including here — it produces one calm line of text that says
/// *up to date* and a door marked *Sync now*.
///
/// Two consequences worth stating, because both are easy to undo:
///
/// - **Calm text, not status furniture.** No chip, no meter, no colour that
///   means alarm, and no snackbar on success. The only row with any weight to
///   it is the one that appears when the service refused a change, because
///   that is the one thing here a person might want to know about.
/// - **Absent when nothing is attached.** [syncStatusSourceProvider] is null
///   until the composition wires a scheduler, and a null source draws nothing
///   at all. A build with no sync says nothing about sync rather than
///   inventing an empty section for it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/status.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// Where the section gets its state, and the two things it may ask for.
///
/// Null by default, in the same spirit as `sourceOpenerProvider`: the
/// scheduler is built by the composition, which overrides this with it. Kept
/// here rather than in `library_ui/providers.dart` because that file is the
/// library UX's own service holder and sync is not one of its services — the
/// section needs exactly one seam and this is it.
final syncStatusSourceProvider = Provider<SyncStatusSource?>((ref) => null);

/// Whether a sync source is attached at all. The settings screen asks so its
/// closing note can describe the app it is actually running in.
bool syncIsAttached(WidgetRef ref) =>
    ref.watch(syncStatusSourceProvider) != null;

/// The section, drawn inside the Settings list.
class SyncStatusSection extends ConsumerStatefulWidget {
  const SyncStatusSection({super.key});

  @override
  ConsumerState<SyncStatusSection> createState() => _SyncStatusSectionState();
}

class _SyncStatusSectionState extends ConsumerState<SyncStatusSection> {
  @override
  void initState() {
    super.initState();
    // One read when the screen opens. The counts move as the rest of the app
    // writes, and this is the moment somebody is looking at them.
    final source = ref.read(syncStatusSourceProvider);
    if (source != null) unawaited(source.refreshStatus());
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(syncStatusSourceProvider);
    if (source == null) return const SizedBox.shrink();
    return StreamBuilder<SyncStatusView>(
      stream: source.statusChanges,
      initialData: source.status,
      builder: (context, snapshot) =>
          _SyncStatusBody(source: source, view: snapshot.data ?? source.status),
    );
  }
}

class _SyncStatusBody extends StatelessWidget {
  const _SyncStatusBody({required this.source, required this.view});

  final SyncStatusSource source;
  final SyncStatusView view;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final now = DateTime.now().toUtc();
    return Column(
      key: const ValueKey('syncStatusSection'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('SYNC'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 3),
          child: Text(
            key: const ValueKey('syncStateSentence'),
            syncStatusSentence(view, now),
            style: TextStyle(fontSize: 14, height: 1.4, color: palette.ink),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            key: const ValueKey('syncDetailLine'),
            syncDetailLine(view, now),
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: palette.inkFaint,
            ),
          ),
        ),
        // The one row that asks for anything, and only when there is something
        // to ask about. A transport failure never draws it: the app will try
        // again on its own and there is nothing for the user to do.
        if (view.problemCount > 0)
          ListTile(
            key: const ValueKey('syncAttentionRow'),
            leading: Icon(Icons.report_outlined, color: palette.warn),
            title: Text(syncProblemHeadline(view.problemCount)),
            subtitle: const Text(kSyncProblemNote),
          ),
        ListTile(
          key: const ValueKey('syncNowButton'),
          leading: const Icon(Icons.sync),
          title: const Text('Sync now'),
          subtitle: Text(
            view.isRunning
                ? 'Working…'
                : view.phase == SyncPhase.neverConfigured
                ? 'Nothing to sync with yet'
                : 'Library organisation and reading state',
          ),
          enabled: !view.isRunning,
          onTap: view.isRunning ? null : () => unawaited(source.syncNow()),
        ),
      ],
    );
  }
}

/// What the app is honest about once sync is attached. Downloaded pages,
/// browsing history and taught rules never cross the network (V2_SYNC.md §4.8).
const String kSyncSettingsNote =
    'Saves and update checks only run when you start them. Library '
    'organisation and reading state synchronise on their own; downloaded '
    'pages, browsing history and saved rules stay on this device.';
