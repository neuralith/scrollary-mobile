import 'dart:async';

import 'package:flutter/material.dart';

import '../browser/browser_controller.dart';
import '../save/next_page.dart';
import '../save/selection_request.dart';
import '../save/page_hint.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// Shown when a save run or an update check is holding for the user to
/// point at a control.
///
/// Follows the design's element-picker sheet: what the app found, what the
/// user picked, and how widely the rule should apply — as tappable cards, not
/// a segmented control.
class RuleSelectionOverlay extends StatefulWidget {
  const RuleSelectionOverlay({
    super.key,
    required this.run,
    required this.request,
  });

  final SelectionHost run;
  final SelectionRequest request;

  @override
  State<RuleSelectionOverlay> createState() => _RuleSelectionOverlayState();
}

class _RuleSelectionOverlayState extends State<RuleSelectionOverlay> {
  SelectedElement? _picked;
  HintScope _scope = HintScope.collection;
  StreamSubscription<SelectedElement>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.run.browser.selections.listen((element) {
      if (mounted) setState(() => _picked = element);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool get _isLink => widget.request.kind == HintKind.nextLink;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final request = widget.request;

    return Material(
      color: palette.surface,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 420),
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
              Text(
                _isLink
                    ? 'Show the app the next-entry control'
                    : 'Show the app where the content is',
                style: serifStyle(size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                '${request.isHintFailure ? 'A saved rule stopped working' : 'Automatic detection was not confident'}'
                ': ${request.reason}. '
                '${_isLink ? 'Tap the control that opens the next entry — taps will not navigate while you are choosing.' : 'Tap the area that contains the entry images — the app remembers it.'}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: palette.inkMuted,
                ),
              ),

              if (request.errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: palette.dangerContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.dangerBorder),
                  ),
                  child: Text(
                    request.errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: palette.onDangerContainer,
                    ),
                  ),
                ),
              ],

              if (request.candidates.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: palette.border),
                          ),
                        ),
                        child: Text(
                          'WHAT THE APP FOUND',
                          style: TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 0.58,
                            fontVariations: wght(600),
                            fontWeight: FontWeight.w600,
                            color: palette.inkMuted,
                          ),
                        ),
                      ),
                      for (final c in request.candidates.take(4))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: palette.hairline),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.help_outline,
                                size: 17,
                                color: palette.warn,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  c.href,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoStyle(
                                    size: 11.5,
                                    color: palette.inkStrong,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                c.strategy.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              if (_picked == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    'Nothing selected yet — tap an element in the page above.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: palette.inkMuted,
                    ),
                  ),
                )
              else
                _PickedDetails(element: _picked!, isLink: _isLink),

              const SizedBox(height: 16),
              Text(
                'USE THIS RULE FOR',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.6,
                  fontVariations: wght(600),
                  fontWeight: FontWeight.w600,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              for (final option in const [
                (
                  HintScope.collection,
                  Icons.menu_book,
                  'This collection on this host',
                  'Recommended — safest scope',
                ),
                (
                  HintScope.pathPattern,
                  Icons.bookmark,
                  'Collection with this URL shape',
                  'Same path pattern on this site',
                ),
                (
                  HintScope.host,
                  Icons.language,
                  'Everything on this site',
                  'Widest, may break on other layouts',
                ),
              ]) ...[
                _ScopeCard(
                  icon: option.$2,
                  label: option.$3,
                  sub: option.$4,
                  selected: _scope == option.$1,
                  onTap: () => setState(() => _scope = option.$1),
                ),
                const SizedBox(height: 7),
              ],

              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _picked == null
                          ? null
                          : () => widget.run.submitSelection(
                              _picked!,
                              scope: _scope,
                            ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _isLink ? 'Use this control' : 'Use this area',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: widget.run.retryAutomaticDetection,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Retry auto'),
                  ),
                ],
              ),
              Center(
                child: TextButton(
                  onPressed: widget.run.cancelSelection,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.inkMuted,
                  ),
                  child: const Text('Cancel run'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                color: selected ? palette.primary : palette.inkMuted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
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
                        color: selected
                            ? palette.onPrimaryContainer
                            : palette.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickedDetails extends StatelessWidget {
  const _PickedDetails({required this.element, required this.isLink});

  final SelectedElement element;
  final bool isLink;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final rows = <(String, String)>[
      ('tag', '<${element.tag}>'),
      if (element.text.isNotEmpty) ('text', element.text),
      if (isLink) ('url', element.href.isEmpty ? '(no href)' : element.href),
      if (element.rel.isNotEmpty) ('rel', element.rel),
      if (element.ariaLabel.isNotEmpty) ('aria-label', element.ariaLabel),
      if (element.title.isNotEmpty) ('title', element.title),
      if (element.imgAlt.isNotEmpty) ('img alt', element.imgAlt),
      if (element.classes.isNotEmpty) ('stable classes', element.classes),
      if (element.selector != null) ('selector', element.selector!),
      if (element.containerSelector != null)
        ('container', element.containerSelector!),
      if (!isLink) ('images inside', '${element.imageCount}'),
      if (!isLink && element.minImageEdge > 0)
        ('smallest edge', '${element.minImageEdge}px'),
    ];

    final signalCount = [
      element.rel,
      element.selector ?? '',
      element.containerSelector ?? '',
      element.text,
      element.ariaLabel,
      element.title,
      element.imgAlt,
    ].where((s) => s.trim().isNotEmpty).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOU PICKED',
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.58,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 5),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: monoStyle(color: palette.onPrimaryContainer),
                  children: [
                    TextSpan(
                      text: '$label  ',
                      style: TextStyle(color: palette.primary),
                    ),
                    TextSpan(
                      text: value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            signalCount < 2
                ? 'Only $signalCount stable signal — this rule may break '
                      'when the site changes.'
                : '$signalCount stable signals will be stored.',
            style: TextStyle(
              fontSize: 10.5,
              color: signalCount < 2 ? palette.danger : palette.primary,
            ),
          ),
        ],
      ),
    );
  }
}
