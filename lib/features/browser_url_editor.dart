import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_url.dart';
import '../browser/history_repository.dart';
import '../browser/saved_sites_repository.dart';
import '../core/url_utils.dart';
import '../providers.dart';
import '../storage/database.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'browser_ui.dart';

/// Where a suggestion came from. Ranking is by group first, then by the
/// strength of the match inside it (§6).
enum SuggestionKind { search, savedSite, history, visitedHost }

class UrlSuggestion {
  const UrlSuggestion({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.host,
    this.score = 0,
  });

  final SuggestionKind kind;
  final String title;
  final String subtitle;
  final String url;
  final String host;

  /// Higher is better. Only compared within a group.
  final int score;

  IconData get icon => switch (kind) {
    SuggestionKind.search => Icons.search,
    SuggestionKind.savedSite => Icons.bookmark,
    SuggestionKind.history => Icons.history,
    SuggestionKind.visitedHost => Icons.public,
  };
}

/// Score [text] against [query]: exact beats prefix beats contains.
///
/// Pure and exported so the ranking can be asserted directly rather than
/// through a rendered list.
int matchScore(String text, String query) {
  if (query.isEmpty) return 1;
  final haystack = text.toLowerCase();
  final needle = query.toLowerCase();
  if (haystack == needle) return 100;
  if (haystack.startsWith(needle)) return 60;
  // A prefix match on a host that only differs by `www.` is still a prefix.
  if (haystack.startsWith('www.') && haystack.substring(4).startsWith(needle)) {
    return 55;
  }
  return haystack.contains(needle) ? 20 : 0;
}

/// Build the local suggestion list.
///
/// Saved sites rank above history at equal relevance, and more recent visits
/// above older ones. Nothing here touches the network — the copy at the
/// bottom of the sheet promises exactly that.
List<(String, List<UrlSuggestion>)> buildSuggestions({
  required String query,
  required List<SavedSite> saved,
  required List<BrowsingHistoryData> visits,
  int perGroup = 4,
}) {
  final trimmed = query.trim();
  final groups = <(String, List<UrlSuggestion>)>[];

  if (trimmed.isNotEmpty) {
    final intent = interpretUrlInput(trimmed);
    groups.add((
      intent.isSearch ? 'Search' : 'Open',
      [
        if (intent.isSearch)
          UrlSuggestion(
            kind: SuggestionKind.search,
            title: 'Search Google for “$trimmed”',
            subtitle: kSearchEngineHost,
            url: intent.url,
            host: kSearchEngineHost,
          )
        else
          UrlSuggestion(
            kind: SuggestionKind.search,
            title: trimmed,
            subtitle: intent.addedScheme
                ? 'open as ${shortUrl(intent.url)}'
                : shortUrl(intent.url),
            url: intent.url,
            host: displayHost(intent.url),
          ),
      ],
    ));
  }

  final savedHits =
      saved
          .map((s) {
            final score = [
              matchScore(savedSiteDisplayTitle(s), trimmed),
              matchScore(s.host, trimmed),
              matchScore(s.url, trimmed),
            ].reduce((a, b) => a > b ? a : b);
            return (s, score);
          })
          .where((e) => e.$2 > 0)
          .toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
  if (savedHits.isNotEmpty) {
    groups.add((
      'Saved sites',
      [
        for (final (site, score) in savedHits.take(perGroup))
          UrlSuggestion(
            kind: SuggestionKind.savedSite,
            title: savedSiteDisplayTitle(site),
            subtitle: shortUrl(site.url),
            url: site.url,
            host: site.host,
            score: score,
          ),
      ],
    ));
  }

  final savedKeys = saved.map((s) => s.urlKey).toSet();
  final historyHits =
      visits
          .where((v) => !savedKeys.contains(v.urlKey))
          .map((v) {
            final score = [
              matchScore(v.title, trimmed),
              matchScore(v.url, trimmed),
              matchScore(v.host, trimmed),
            ].reduce((a, b) => a > b ? a : b);
            return (v, score);
          })
          .where((e) => e.$2 > 0)
          .toList()
        // Visits arrive newest-first, so a stable sort on score alone keeps
        // recency as the tiebreak without a second comparison.
        ..sort((a, b) => b.$2.compareTo(a.$2));
  if (historyHits.isNotEmpty) {
    groups.add((
      'History',
      [
        for (final (visit, score) in historyHits.take(perGroup))
          UrlSuggestion(
            kind: SuggestionKind.history,
            title: visit.title,
            subtitle: shortUrl(visit.url),
            url: visit.url,
            host: visit.host,
            score: score,
          ),
      ],
    ));
  }

  final hosts = HistoryRepository.groupByHost(
    visits,
  ).where((h) => matchScore(h.host, trimmed) > 0).take(3).toList();
  if (hosts.isNotEmpty) {
    groups.add((
      'Visited sites',
      [
        for (final host in hosts)
          UrlSuggestion(
            kind: SuggestionKind.visitedHost,
            title: host.host,
            subtitle:
                '${host.visitCount} '
                '${host.visitCount == 1 ? 'visit' : 'visits'}',
            url: host.siteRoot ?? host.latestUrl,
            host: host.host,
            score: matchScore(host.host, trimmed),
          ),
      ],
    ));
  }

  return groups;
}

/// The expanded URL editor: a full surface over the page, not an inline
/// field.
///
/// Its whole reason for existing is that an entry URL does not fit in the
/// toolbar. The full address is shown on its own horizontally-scrolling line
/// above the input, so it can be *read* as well as edited (§6).
class BrowserUrlEditor extends ConsumerStatefulWidget {
  const BrowserUrlEditor({
    super.key,
    required this.initialText,
    required this.selectAll,
    required this.onSubmit,
    required this.onCancel,
    required this.onSaveSite,
    this.currentPageUrl = '',
  });

  final String initialText;

  /// True when opened on a live page: the whole URL starts selected so
  /// typing replaces it, which is what a person about to go somewhere else
  /// wants.
  final bool selectAll;

  /// Fires with the raw text; the caller interprets it.
  final void Function(String text) onSubmit;
  final VoidCallback onCancel;

  /// "Save site" from the action row.
  final void Function(String url, String title) onSaveSite;

  final String currentPageUrl;

  @override
  ConsumerState<BrowserUrlEditor> createState() => _BrowserUrlEditorState();
}

class _BrowserUrlEditorState extends ConsumerState<BrowserUrlEditor> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  Timer? _debounce;

  /// The text suggestions are computed from. Deliberately lags the field by
  /// [_debounceDelay] so a fast typist does not trigger a rebuild — and, when
  /// the sources are large, a query — per keystroke (§20).
  String _query = '';

  static const Duration _debounceDelay = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _query = widget.initialText;
    if (widget.selectAll) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialText.length,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (!mounted) return;
      setState(() => _query = text);
    });
  }

  /// Apply the pending text immediately — submitting must not wait out a
  /// debounce that only exists to save work.
  void _flush() {
    _debounce?.cancel();
    _query = _controller.text;
  }

  void _submit() {
    _flush();
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
  }

  Future<void> _paste({required bool andGo}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _onChanged(text);
    if (andGo) widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = _controller.text;
    final intent = interpretUrlInput(text.trim());
    final saved = ref.watch(savedSitesProvider).value ?? const [];
    final visits = ref.watch(browsingHistoryProvider).value ?? const [];
    final groups = buildSuggestions(
      query: _query,
      saved: saved,
      visits: visits,
    );

    return Material(
      color: palette.surface,
      child: SafeArea(
        child: Column(
          children: [
            _EditorHeader(
              controller: _controller,
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmit: _submit,
              onCancel: widget.onCancel,
              onClear: () {
                _controller.clear();
                _onChanged('');
              },
            ),
            _FullUrlStrip(text: text.isEmpty ? widget.currentPageUrl : text),
            _ActionRow(
              text: text,
              currentPageUrl: widget.currentPageUrl,
              onSelectAll: () {
                _controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _controller.text.length,
                );
                _focus.requestFocus();
              },
              onCopy: () async {
                final value = text.isEmpty ? widget.currentPageUrl : text;
                if (value.isEmpty) return;
                final messenger = ScaffoldMessenger.maybeOf(context);
                await Clipboard.setData(ClipboardData(text: value));
                messenger?.showSnackBar(
                  const SnackBar(content: Text('URL copied')),
                );
              },
              onPasteAndGo: () => _paste(andGo: true),
              onClear: () {
                _controller.clear();
                _onChanged('');
                _focus.requestFocus();
              },
              onOpenHost: () {
                final root = siteRootFor(
                  text.isEmpty ? widget.currentPageUrl : text,
                );
                if (root != null) widget.onSubmit(root);
              },
              onSaveSite: () => widget.onSaveSite(
                text.isEmpty ? widget.currentPageUrl : text,
                '',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 30),
                children: [
                  for (final (label, items) in groups)
                    _SuggestionGroup(
                      label: label,
                      items: items,
                      onTap: (s) => widget.onSubmit(s.url),
                    ),
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        _query.trim().isEmpty
                            ? 'Type an address, or search for what you want.'
                            : 'Nothing saved or visited matches that — type a '
                                  'full address to open it.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: palette.inkFaint,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      'Suggestions come from your saved sites and history on '
                      'this device only.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: palette.inkGhost,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _EditorFooter(
              intent: intent,
              onCancel: widget.onCancel,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.only(left: 11, right: 2),
              decoration: BoxDecoration(
                color: palette.surfaceInset,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: palette.primary, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.public, size: 17, color: palette.inkMuted),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('urlEditorField'),
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.go,
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmit(),
                      style: monoStyle(size: 12.5, color: palette.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Search or enter address',
                        hintStyle: monoStyle(
                          size: 12.5,
                          color: palette.inkFaint,
                        ),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    IconButton(
                      onPressed: onClear,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Clear',
                      color: palette.inkMuted,
                      icon: const Icon(Icons.cancel),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('urlEditorCancel'),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// The whole address on one horizontally-scrolling line.
class _FullUrlStrip extends StatelessWidget {
  const _FullUrlStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (text.trim().isEmpty) return const SizedBox(height: 9);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: palette.surfaceInset,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: palette.borderInset),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: monoStyle(size: 11, color: palette.inkStrong),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({
    required this.text,
    required this.currentPageUrl,
    required this.onSelectAll,
    required this.onCopy,
    required this.onPasteAndGo,
    required this.onClear,
    required this.onOpenHost,
    required this.onSaveSite,
  });

  final String text;
  final String currentPageUrl;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;
  final VoidCallback onPasteAndGo;
  final VoidCallback onClear;
  final VoidCallback onOpenHost;
  final VoidCallback onSaveSite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final effective = text.trim().isEmpty ? currentPageUrl : text.trim();
    final saved = ref.watch(savedSitesProvider).value ?? const [];
    final isSaved = saved.any((s) => s.urlKey == _normalizedOrEmpty(effective));
    final hasHost = siteRootFor(effective) != null;

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
        children: [
          _Chip(
            icon: Icons.select_all,
            label: 'Select all',
            onTap: text.isEmpty ? null : onSelectAll,
          ),
          _Chip(
            icon: Icons.content_copy,
            label: 'Copy',
            onTap: effective.isEmpty ? null : onCopy,
          ),
          _Chip(
            icon: Icons.content_paste_go,
            label: 'Paste and go',
            primary: true,
            onTap: onPasteAndGo,
          ),
          _Chip(
            icon: Icons.backspace,
            label: 'Clear',
            onTap: text.isEmpty ? null : onClear,
          ),
          if (hasHost)
            _Chip(icon: Icons.home, label: 'Open host', onTap: onOpenHost),
          _Chip(
            icon: isSaved ? Icons.bookmark_added : Icons.bookmark_add,
            label: isSaved ? 'Already saved' : 'Save site',
            onTap: effective.isEmpty
                ? null
                : isSaved
                ? () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text('This page is already in saved sites'),
                    ),
                  )
                : onSaveSite,
          ),
          SizedBox(width: 4, child: ColoredBox(color: palette.surface)),
        ],
      ),
    );
  }

  /// The saved-site key for whatever is in the field, or empty when it is
  /// not an address at all.
  static String _normalizedOrEmpty(String url) {
    if (url.trim().isEmpty) return '';
    final intent = interpretUrlInput(url);
    if (intent.isEmpty || intent.isSearch) return '';
    return normalizeUrl(intent.url);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onTap != null;
    final bg = primary ? palette.primaryContainer : palette.surfaceInset;
    final bd = primary ? palette.primaryBorder : palette.borderInset;
    final fg = !enabled
        ? palette.inkDisabled
        : (primary ? palette.onPrimaryContainer : palette.inkStrong);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: bd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionGroup extends StatelessWidget {
  const _SuggestionGroup({
    required this.label,
    required this.items,
    required this.onTap,
  });

  final String label;
  final List<UrlSuggestion> items;
  final void Function(UrlSuggestion) onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 20, 5),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.6,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.inkFaint,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.hairline)),
          ),
          child: Column(
            children: [
              for (final item in items)
                BrowserListRow(
                  key: ValueKey('suggestion-${item.kind.name}-${item.url}'),
                  host: item.host,
                  title: item.title,
                  subtitle: item.subtitle,
                  iconSize: 26,
                  dense: true,
                  trailing: Icon(
                    item.icon,
                    size: 17,
                    color: palette.inkDisabled,
                  ),
                  onTap: () => onTap(item),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.intent,
    required this.onCancel,
    required this.onSubmit,
  });

  final UrlIntent intent;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = !intent.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('urlEditorGo'),
              onPressed: enabled ? onSubmit : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: Text(intent.isSearch ? 'Search Google' : 'Go'),
            ),
          ),
        ],
      ),
    );
  }
}
