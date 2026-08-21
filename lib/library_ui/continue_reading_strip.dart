import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/palette.dart';
import 'providers.dart';

/// Continue Reading, over the logical Entries.
///
/// Derived from reading state alone — an Entry appears because someone is
/// partway through it, never because of what this device happens to hold
/// (PRODUCT.md §2.3). Quiet by design: with nothing to resume the strip
/// draws nothing at all.
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
          height: 64,
          child: ListView.separated(
            key: const ValueKey('continueReadingStrip'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final item = items[i];
              return ActionChip(
                key: ValueKey('continueRead-${item.entryId}'),
                avatar: Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: palette.inkMuted,
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.collectionName != null)
                        Text(
                          item.collectionName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.inkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                onPressed: open == null ? null : () => open(item.entryId),
              );
            },
          ),
        ),
      ],
    );
  }
}
