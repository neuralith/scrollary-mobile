/// Choosing a Folder: the one picker every *move* uses (roadmap D2).
///
/// It offers the **whole tree**, including places a move will be refused
/// from. That is deliberate. The rule that a Folder may not contain itself
/// lives in the repository (I2), and a picker that quietly hid the offending
/// rows would be a second, silent copy of it — one that drifts, and one the
/// user can never see the reason for. The refusal comes back named, and the
/// caller prints it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'providers.dart';

/// Shows the tree and resolves to the chosen Folder's id, or null if the
/// sheet was dismissed.
Future<String?> pickFolder(
  BuildContext context, {
  required String title,
  String? currentId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: _FolderPicker(title: title, currentId: currentId),
    ),
  );
}

class _FolderPicker extends ConsumerWidget {
  const _FolderPicker({required this.title, this.currentId});

  final String title;
  final String? currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final tree = ref.watch(folderTreeProvider);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(title, style: serifStyle(size: 20)),
          ),
          Flexible(
            child: tree.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$error'),
              ),
              data: (nodes) => ListView(
                shrinkWrap: true,
                children: [
                  for (final node in nodes)
                    ListTile(
                      key: ValueKey('folderOption-${node.id}'),
                      leading: Padding(
                        padding: EdgeInsets.only(left: node.depth * 16.0),
                        child: Icon(
                          node.isRoot ? Icons.home_outlined : Icons.folder,
                          size: 20,
                          color: palette.inkMuted,
                        ),
                      ),
                      title: Text(node.name),
                      trailing: node.id == currentId
                          ? Icon(Icons.check, size: 18, color: palette.primary)
                          : null,
                      onTap: () => Navigator.of(context).pop(node.id),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
