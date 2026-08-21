import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../ui/palette.dart';
import '../ui/theme.dart';
import 'browser_ui.dart';

/// The design's three-up appearance control.
///
/// The reader is deliberately excluded: it is dark in every appearance,
/// because it is built for night reading and a "light reader" nobody asked for
/// would be a regression, not a feature.
class AppearanceSelector extends ConsumerWidget {
  const AppearanceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final mode = ref.watch(appearanceProvider).value ?? AppearanceMode.system;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrowserSegmented(
            key: const ValueKey('appearanceSelector'),
            labels: const ['System', 'Light', 'Dark'],
            selected: AppearanceMode.values.indexOf(mode),
            onSelect: (i) => setAppearance(ref, AppearanceMode.values[i]),
          ),
          const SizedBox(height: 9),
          Text(
            "The reader stays dark in every theme — it's built for night "
            'reading.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: palette.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
