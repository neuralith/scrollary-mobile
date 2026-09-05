import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'providers.dart';

/// Continue Reading, over the logical Entries.
///
/// Derived from reading state alone — an Entry appears because someone is
/// partway through it, never because of what this device happens to hold
/// (PRODUCT.md §2.3). Quiet by design: with nothing to resume the strip
/// draws nothing at all.
///
/// **What a card is, and why it has no picture on it.** There is no cover art
/// in this library and nothing here pretends otherwise: the card is words and
/// one small mark, in the order a reader recognises a resumable reading in.
/// The work's name leads, because that is what someone is coming back to; the
/// Entry's own position sits under it, because that is where they left off;
/// and how far the reading got is the one number, beside them both. Which
/// Entry each Collection is showing is [continueReadingProvider]'s answer —
/// the card draws it and decides nothing.
class ContinueReadingStrip extends ConsumerWidget {
  const ContinueReadingStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueReadingProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final open = ref.read(entryOpenerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'CONTINUE READING',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: palette.inkMuted,
            ),
          ),
        ),
        SizedBox(
          height: _kCardHeight,
          child: ListView.separated(
            key: const ValueKey('continueReadingStrip'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _ContinueReadCard(
              item: items[i],
              onOpen: open == null ? null : () => open(items[i].entryId),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tall enough for two lines of card text plus its padding, and no taller: the
/// strip is a band across the top of the Library, not a shelf of tiles.
const double _kCardHeight = 66;

/// Wide enough that a work's name and a position under it both survive at a
/// phone's width, narrow enough that the second card is visibly there to be
/// scrolled to.
const double _kCardWidth = 208;

class _ContinueReadCard extends StatelessWidget {
  const _ContinueReadCard({required this.item, required this.onOpen});

  final ContinueReadItem item;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final progress = item.progress;
    return SizedBox(
      width: _kCardWidth,
      child: Material(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('continueRead-${item.entryId}'),
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      if (item.entryLabel case final label?) ...[
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.inkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // The figure, where the library holds one. A reading anchored
                // inside a package on this device has a position but no
                // proportion, and no percentage is invented for it.
                if (progress != null) ...[
                  const SizedBox(width: 10),
                  EntryProgressRing(
                    fraction: progress,
                    completed: false,
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
