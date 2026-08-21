import 'package:flutter/material.dart';
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

/// A save request, before it is written.
class SavedSiteDraft {
  const SavedSiteDraft({
    required this.title,
    required this.url,
    this.host,
    this.editingId,
    this.siteRootOption,
    this.fromManualEntry = false,
  });

  final String title;
  final String url;
  final String? host;

  /// Set when editing an existing row rather than creating one.
  final String? editingId;

  /// A site-level URL the user may choose instead of this page. Null when no
  /// reliable one could be derived — in which case the page URL is saved and
  /// nothing is invented (§5).
  final String? siteRootOption;

  final bool fromManualEntry;
}

/// The two-tab Add flow: recent pages, visited sites, or type it yourself.
///
/// Returns true when something was saved, so the caller can confirm.
Future<bool> showAddSavedSiteSheet(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => const _AddSavedSiteSheet(),
  );
  return saved ?? false;
}

/// Straight to the edit step for a page the caller already has.
Future<bool> showSaveSiteSheet(
  BuildContext context, {
  required String url,
  required String title,
  String? editingId,
  bool offerSiteRoot = true,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _EditSavedSite(
        draft: SavedSiteDraft(
          title: title,
          url: url,
          host: displayHost(url),
          editingId: editingId,
          siteRootOption: offerSiteRoot ? siteRootFor(url) : null,
        ),
        onBack: null,
      ),
    ),
  );
  return saved ?? false;
}

class _AddSavedSiteSheet extends ConsumerStatefulWidget {
  const _AddSavedSiteSheet();

  @override
  ConsumerState<_AddSavedSiteSheet> createState() => _AddSavedSiteSheetState();
}

class _AddSavedSiteSheetState extends ConsumerState<_AddSavedSiteSheet> {
  int _tab = 0;
  SavedSiteDraft? _editing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final draft = _editing;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: draft != null
            // Reached from the picker, so Back always returns to it.
            ? _EditSavedSite(
                draft: draft,
                onBack: () => setState(() => _editing = null),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Add a saved site',
                          style: serifStyle(size: 20, color: palette.ink),
                        ),
                        const SizedBox(height: 12),
                        BrowserSegmented(
                          labels: const ['Recent pages', 'Visited sites'],
                          selected: _tab,
                          onSelect: (i) => setState(() => _tab = i),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: _tab == 0
                        ? _RecentPagesTab(onPick: _startEdit)
                        : _VisitedSitesTab(onPick: _startEdit),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: palette.hairline)),
                    ),
                    child: ListTile(
                      key: const ValueKey('addSavedSiteManual'),
                      leading: Icon(Icons.edit, color: palette.inkMuted),
                      title: Text(
                        'Enter URL manually',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontVariations: wght(500),
                          fontWeight: FontWeight.w500,
                          color: palette.ink,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: palette.inkDisabled,
                      ),
                      onTap: () => _startEdit(
                        const SavedSiteDraft(
                          title: '',
                          url: 'https://',
                          fromManualEntry: true,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _startEdit(SavedSiteDraft draft) => setState(() => _editing = draft);
}

class _RecentPagesTab extends ConsumerWidget {
  const _RecentPagesTab({required this.onPick});

  final void Function(SavedSiteDraft) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final visits = ref.watch(browsingHistoryProvider).value ?? const [];
    final saved = ref.watch(savedSitesProvider).value ?? const [];
    final savedKeys = saved.map((s) => s.urlKey).toSet();

    if (visits.isEmpty) {
      return const BrowserEmptyState(
        icon: Icons.history,
        title: 'No pages yet',
        body: 'Browse to a page first, or enter an address by hand below.',
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        for (final visit in visits.take(12))
          BrowserListRow(
            key: ValueKey('addRecent-${visit.id}'),
            host: visit.host,
            title: visit.title,
            subtitle:
                '${shortUrl(visit.url)} · ${formatVisitTime(visit.visitedAt)}',
            iconSize: 30,
            trailing: savedKeys.contains(visit.urlKey)
                ? Text(
                    'Saved',
                    style: TextStyle(
                      fontSize: 11,
                      fontVariations: wght(600),
                      fontWeight: FontWeight.w600,
                      color: palette.warn,
                    ),
                  )
                : null,
            onTap: () => onPick(
              SavedSiteDraft(
                title: visit.title,
                url: visit.url,
                host: visit.host,
                siteRootOption: siteRootFor(visit.url),
              ),
            ),
          ),
      ],
    );
  }
}

class _VisitedSitesTab extends ConsumerWidget {
  const _VisitedSitesTab({required this.onPick});

  final void Function(SavedSiteDraft) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final hosts = ref.watch(visitedHostsProvider).value ?? const [];
    final saved = ref.watch(savedSitesProvider).value ?? const [];
    final savedKeys = saved.map((s) => s.urlKey).toSet();

    if (hosts.isEmpty) {
      return const BrowserEmptyState(
        icon: Icons.public_off,
        title: 'No sites yet',
        body: 'Sites you visit are grouped here once you have browsed to one.',
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [
        for (final host in hosts)
          _VisitedHostRow(
            host: host,
            alreadySaved: savedKeys.contains(
              normalizeUrl(host.siteRoot ?? host.latestUrl),
            ),
            palette: palette,
            onTap: () => onPick(
              SavedSiteDraft(
                // A hostname is a poor title; the user renames it, and the
                // field is pre-filled with something recognisable.
                title: host.siteRoot != null
                    ? host.host.split('.').first
                    : host.latestTitle,
                url: host.siteRoot ?? host.latestUrl,
                host: host.host,
                siteRootOption: host.siteRoot,
              ),
            ),
          ),
      ],
    );
  }
}

class _VisitedHostRow extends StatelessWidget {
  const _VisitedHostRow({
    required this.host,
    required this.alreadySaved,
    required this.palette,
    required this.onTap,
  });

  final VisitedHost host;
  final bool alreadySaved;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Only said when it is true: a host we have only ever seen one deep page
    // of gets the page saved, not a guessed homepage (§5).
    final noReliableRoot = host.siteRoot == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: InkWell(
        key: ValueKey('addHost-${host.host}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaviconTile(host: host.host, size: 30, radius: 9),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      host.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${host.visitCount} '
                      '${host.visitCount == 1 ? 'visit' : 'visits'} · last '
                      '${formatVisitTime(host.lastVisitedAt)}',
                      style: monoStyle(size: 11, color: palette.inkMuted),
                    ),
                    if (noReliableRoot) ...[
                      const SizedBox(height: 3),
                      Text(
                        'No reliable home page seen — the last visited page '
                        'will be saved.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: palette.warn,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (alreadySaved)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    'Saved',
                    style: TextStyle(
                      fontSize: 11,
                      fontVariations: wght(600),
                      fontWeight: FontWeight.w600,
                      color: palette.warn,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The save/edit step: title, URL, an optional site-vs-page choice, and the
/// duplicate notice.
class _EditSavedSite extends ConsumerStatefulWidget {
  const _EditSavedSite({required this.draft, required this.onBack});

  final SavedSiteDraft draft;
  final VoidCallback? onBack;

  @override
  ConsumerState<_EditSavedSite> createState() => _EditSavedSiteState();
}

class _EditSavedSiteState extends ConsumerState<_EditSavedSite> {
  late final TextEditingController _title;
  late final TextEditingController _url;

  /// True when the user picked "save the whole site" over "save this page".
  bool _useSiteRoot = false;
  SavedSite? _duplicate;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.draft.title);
    _url = TextEditingController(text: widget.draft.url);
    _useSiteRoot =
        widget.draft.siteRootOption != null &&
        widget.draft.siteRootOption == widget.draft.url;
    _checkDuplicate();
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  String get _effectiveUrl => _url.text.trim();

  bool get _urlIsValid {
    final intent = interpretUrlInput(_effectiveUrl);
    return !intent.isEmpty &&
        !intent.isSearch &&
        !isExternalAppScheme(intent.url);
  }

  bool get _canSave => _urlIsValid && _title.text.trim().isNotEmpty;

  Future<void> _checkDuplicate() async {
    if (!_urlIsValid) {
      if (mounted && _duplicate != null) setState(() => _duplicate = null);
      return;
    }
    final existing = await ref
        .read(savedSitesRepositoryProvider)
        .findByUrl(_effectiveUrl);
    if (!mounted) return;
    setState(
      () =>
          _duplicate = existing != null && existing.id != widget.draft.editingId
          ? existing
          : null,
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(savedSitesRepositoryProvider);
    final result = await repo.save(
      url: _effectiveUrl,
      title: _title.text.trim(),
      // Reaching Save with the duplicate notice visible is the user having
      // read it and chosen to edit the existing tile — never a silent
      // second row (§4).
      updateExisting: _duplicate != null,
      editingId: widget.draft.editingId,
    );
    navigator.pop(true);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.outcome == SaveSiteOutcome.updated
                ? 'Saved site updated'
                : '“${savedSiteDisplayTitle(result.site)}” added to saved sites',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final root = widget.draft.siteRootOption;
    final showScope = root != null && root != widget.draft.url;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.draft.editingId == null ? 'Save site' : 'Edit saved site',
            style: serifStyle(size: 20, color: palette.ink),
          ),
          const SizedBox(height: 4),
          Text(
            widget.draft.fromManualEntry
                ? 'Type the address you want one tap away.'
                : _duplicate != null
                ? 'This address is already saved.'
                : "Give it a short name you'll recognise.",
            style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
          ),
          const SizedBox(height: 14),
          _FieldLabel('Title'),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('savedSiteTitleField'),
            controller: _title,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 14, color: palette.ink),
            decoration: _inputDecoration(palette),
          ),
          const SizedBox(height: 12),
          _FieldLabel('URL'),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('savedSiteUrlField'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) {
              setState(() {});
              _checkDuplicate();
            },
            style: monoStyle(size: 12, color: palette.ink),
            decoration: _inputDecoration(
              palette,
              borderColor: _effectiveUrl.isNotEmpty && !_urlIsValid
                  ? palette.danger
                  : null,
            ),
          ),
          if (_effectiveUrl.isNotEmpty && !_urlIsValid) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(Icons.error, size: 15, color: palette.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Enter a full address, starting with https://',
                    style: TextStyle(fontSize: 11.5, color: palette.danger),
                  ),
                ),
              ],
            ),
          ],
          if (_duplicate != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.warnContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.warnBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.bookmark_added, size: 17, color: palette.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Already in saved sites — saving again will update the '
                      'existing tile instead of adding a duplicate.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.onWarnContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showScope) ...[
            const SizedBox(height: 14),
            _ScopeOption(
              label: 'Save site',
              subtitle: root,
              selected: _useSiteRoot,
              onTap: () {
                setState(() {
                  _useSiteRoot = true;
                  _url.text = root;
                });
                _checkDuplicate();
              },
            ),
            const SizedBox(height: 6),
            _ScopeOption(
              label: 'Save this page',
              subtitle: shortUrl(widget.draft.url),
              selected: !_useSiteRoot,
              onTap: () {
                setState(() {
                  _useSiteRoot = false;
                  _url.text = widget.draft.url;
                });
                _checkDuplicate();
              },
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed:
                    widget.onBack ?? () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
                child: Text(widget.onBack == null ? 'Cancel' : 'Back'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('savedSiteSaveButton'),
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(_duplicate != null ? 'Update tile' : 'Save site'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, {Color? borderColor}) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: palette.surfaceInset,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: border(borderColor ?? palette.borderStrong),
      enabledBorder: border(borderColor ?? palette.borderStrong),
      focusedBorder: border(borderColor ?? palette.primary),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        letterSpacing: 0.6,
        fontVariations: wght(600),
        fontWeight: FontWeight.w600,
        color: palette.inkMuted,
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: selected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? palette.primaryBorder : palette.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 19,
                color: selected ? palette.primary : palette.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: monoStyle(size: 10.5, color: palette.inkMuted),
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
