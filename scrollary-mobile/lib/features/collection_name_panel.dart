import 'package:flutter/material.dart';

import '../library/collection_repository.dart';
import '../ui/palette.dart';
import '../ui/theme.dart';

/// Shown in place of the save panel while the running run holds on a
/// collection it is about to create.
///
/// The run is paused underneath: no row has been written, nothing has been
/// downloaded and no page has been navigated to. What the source called this
/// group is offered as a suggestion in the field, and it is only a suggestion
/// — a site that titles its pages "Part 12: The Fall" would otherwise have
/// named the whole collection after one of its parts.
///
/// Takes a proposal and a callback rather than the run itself: this panel has
/// no other reason to hold a controller, and a widget that is a pure function
/// of its arguments is one a test can drive without standing up a save.
class CollectionNamePanel extends StatefulWidget {
  const CollectionNamePanel({
    super.key,
    required this.proposal,
    required this.onSubmit,
  });

  final NewCollectionProposal proposal;

  /// The chosen name, or null when the user cancelled — which stops the save.
  final ValueChanged<String?> onSubmit;

  @override
  State<CollectionNamePanel> createState() => _CollectionNamePanelState();
}

class _CollectionNamePanelState extends State<CollectionNamePanel> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.proposal.suggestedName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final host = widget.proposal.host;

    return Material(
      color: palette.surface,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 430),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: palette.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.folder_outlined, size: 24, color: palette.primary),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Name this collection',
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.3,
                            fontVariations: wght(600),
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'The pages this save collects will be grouped under '
                          'this name. Nothing has been saved yet.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: palette.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('collectionNameField'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_canSave) _submit(_name.text);
                },
                style: TextStyle(fontSize: 14, color: palette.ink),
              ),
              const SizedBox(height: 8),
              Text(
                widget.proposal.suggestedName.isEmpty
                    ? host.isEmpty
                          ? 'The page did not offer a name.'
                          : 'The page did not offer a name. It came from $host.'
                    : host.isEmpty
                    ? 'Suggested from the page. Change it to anything you like.'
                    : 'Suggested from the page on $host. Change it to anything '
                          'you like.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: palette.inkFaint,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    key: const ValueKey('collectionNameCancel'),
                    onPressed: () => _submit(null),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('collectionNameSave'),
                      onPressed: _canSave ? () => _submit(_name.text) : null,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Save collection'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Cancelling stops this save. Nothing is created and nothing '
                'you already have is touched.',
                style: TextStyle(fontSize: 11, color: palette.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit(String? name) {
    // The keyboard belongs to a panel that is about to go; leaving it up over
    // a running save is how the page underneath ends up unreachable.
    FocusScope.of(context).unfocus();
    widget.onSubmit(name);
  }
}
