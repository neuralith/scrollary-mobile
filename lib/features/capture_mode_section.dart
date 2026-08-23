/// "What to save" — the capture-mode block of the save sheet.
///
/// **This is fixed store copy.** STORE_PACKAGE.md §6.3 and §6.6 are marked
/// *Built — verbatim*, and they are transcribed from this widget: the
/// detection summary, the three mode rows with their descriptions, the reason
/// each unavailable mode gives, and the two video sentences. Change a word
/// here and §6.3/§6.6 stop describing the app; change one there and this stops
/// matching. `test/capture_mode_section_test.dart` holds the pairing.
///
/// Two rules the layout carries rather than states:
///
/// * **Every mode is always on screen.** An unavailable one is disabled with
///   its reason in place of its description, because a missing option reads as
///   a bug while a greyed one with "no readable text was found on this page"
///   beside it reads as an answer.
/// * **A mode is only offered when the engine can carry it out.**
///   [CaptureCapabilities] is measured on the settled page, so the sheet can
///   never offer a mode the save would then refuse. There is no video mode,
///   and there is no code path here that could add one.
library;

import 'package:flutter/material.dart';

import '../library/content_shape.dart';
import '../save/capture_mode.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';

/// One line of what was detected, and how sure — STORE_PACKAGE.md §6.3.
///
/// Never presents a low-confidence guess as a firm answer: the sheet says
/// "this looks like", and every alternative stays one tap away regardless.
String captureDetectionSummary(CaptureCapabilities capabilities) {
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
  // being forced through the "this looks like …" template, which would read as
  // "this looks like not something we could classify".
  if (kind == null) {
    return 'This page did not say clearly what it is. Pick what fits.';
  }
  return capabilities.content.confidence.isActionable
      ? 'This looks like $kind.'
      : 'This might be $kind — the page did not say clearly.';
}

/// The capture-mode block: what will be taken off this page.
class CaptureModeSection extends StatelessWidget {
  const CaptureModeSection({
    super.key,
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

  /// The glyph this app draws a mode with, so the collapsed line beside this
  /// block and the block itself cannot drift apart.
  static IconData iconFor(CaptureMode mode) => _icons[mode]!;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What to save', style: serifStyle(size: 15, color: palette.ink)),
        const SizedBox(height: 6),
        Text(
          captureDetectionSummary(capabilities),
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
          _ModeOption(
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
}

/// *What to save*, for a Collection that has already answered.
///
/// The whole block, collapsed to a line. Deliberately **not** a variant of
/// [CaptureModeSection]: that widget is fixed store copy (STORE_PACKAGE.md
/// §6.3 and §6.6, transcribed word for word and pinned by
/// `test/capture_mode_section_test.dart`) and it stays exactly as it is. This
/// is what stands in its place once the question has been answered for this
/// work, and *Change* is one tap away from the full block with every reason
/// and every blocked mode still in it.
///
/// Only ever drawn for a mode the page can actually honour — a preference
/// proposes and the page disposes, so a Collection normally kept as images
/// asks again on the page that has none rather than showing a line that
/// promises something the save would refuse.
class RememberedCaptureLine extends StatelessWidget {
  const RememberedCaptureLine({
    super.key,
    required this.mode,
    required this.onChange,
  });

  final CaptureMode mode;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const ValueKey('captureModeRemembered'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(
            CaptureModeSection.iconFor(mode),
            size: 18,
            color: palette.inkMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'What this collection is usually saved as.',
                  style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('captureModeChange'),
            onPressed: onChange,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// Says plainly that video is not saved, and what will happen instead —
/// STORE_PACKAGE.md §6.6, verbatim.
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

class _ModeOption extends StatelessWidget {
  const _ModeOption({
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
