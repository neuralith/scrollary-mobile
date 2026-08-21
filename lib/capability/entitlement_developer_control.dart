import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../ui/palette.dart';
import 'entitlement.dart';
import 'foreground_multitasking.dart';

/// The internal entitlement simulator: Production · Force Free · Force Pro.
///
/// Writes the override onto the one capability object, which is the only thing
/// that resolves an entitlement. No screen reads this preference directly —
/// that indirection is what lets StoreKit or Play Billing replace the
/// production source later without touching a single screen.
class EntitlementOverridePicker extends ConsumerStatefulWidget {
  const EntitlementOverridePicker({super.key});

  @override
  ConsumerState<EntitlementOverridePicker> createState() =>
      EntitlementOverridePickerState();
}

class EntitlementOverridePickerState
    extends ConsumerState<EntitlementOverridePicker> {
  late final ForegroundMultitasking _capability;

  @override
  void initState() {
    super.initState();
    _capability = ref.read(foregroundMultitaskingProvider);
    _capability.addListener(_onChanged);
  }

  @override
  void dispose() {
    _capability.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _set(EntitlementOverride value) async {
    // The rule for a change during live work: the *next* task picks it up.
    // A run already in flight keeps the capability it started with, because
    // pulling the painted surface out from under a scrolling save is exactly
    // the corruption this whole feature exists to avoid.
    _capability.override = value;
    await ref
        .read(databaseProvider)
        .setSetting(ForegroundMultitasking.overrideSettingKey, value.name);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simulated entitlement',
            style: TextStyle(fontSize: 13, color: palette.ink),
          ),
          const SizedBox(height: 8),
          SegmentedButton<EntitlementOverride>(
            key: const ValueKey('developerEntitlementOverride'),
            segments: [
              for (final v in EntitlementOverride.values)
                ButtonSegment(
                  value: v,
                  label: Text(v.label, style: const TextStyle(fontSize: 11.5)),
                ),
            ],
            selected: {_capability.override},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _set(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Effective: ${_capability.effectiveEntitlement.name} · '
            'Pro available: ${_capability.proAvailable} · '
            'Keep working preference: ${_capability.preference} · '
            'Active: ${_capability.enabled}',
            style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
          ),
        ],
      ),
    );
  }
}
