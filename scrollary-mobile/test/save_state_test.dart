import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/save_state.dart';

void main() {
  group('save state transitions', () {
    test('the happy path for a single entry is legal end to end', () {
      const path = [
        SaveState.idle,
        SaveState.inspecting,
        SaveState.scrolling,
        SaveState.waitingForAssets,
        SaveState.verifying,
        SaveState.extracting,
        SaveState.fetchingAssets,
        SaveState.saving,
        SaveState.complete,
      ];

      for (var i = 0; i < path.length - 1; i++) {
        expect(
          isTransitionAllowed(path[i], path[i + 1]),
          isTrue,
          reason: '${path[i].name} -> ${path[i + 1].name}',
        );
      }
    });

    test('the multi-entry loop closes back to inspecting', () {
      expect(
        isTransitionAllowed(SaveState.saving, SaveState.detectingNext),
        isTrue,
      );
      expect(
        isTransitionAllowed(SaveState.detectingNext, SaveState.navigating),
        isTrue,
      );
      expect(
        isTransitionAllowed(SaveState.navigating, SaveState.inspecting),
        isTrue,
      );
    });

    test('save can never jump straight from scrolling to complete', () {
      expect(
        isTransitionAllowed(SaveState.scrolling, SaveState.complete),
        isFalse,
      );
    });

    test('downloading cannot skip saving', () {
      expect(
        isTransitionAllowed(SaveState.fetchingAssets, SaveState.complete),
        isFalse,
      );
      expect(
        isTransitionAllowed(SaveState.fetchingAssets, SaveState.saving),
        isTrue,
      );
    });

    test('every running state can be paused and cancelled', () {
      const running = [
        SaveState.inspecting,
        SaveState.scrolling,
        SaveState.waitingForAssets,
        SaveState.verifying,
        SaveState.extracting,
        SaveState.fetchingAssets,
        SaveState.detectingNext,
        SaveState.navigating,
      ];
      for (final state in running) {
        expect(
          isTransitionAllowed(state, SaveState.paused),
          isTrue,
          reason: '${state.name} -> paused',
        );
        expect(
          isTransitionAllowed(state, SaveState.cancelled),
          isTrue,
          reason: '${state.name} -> cancelled',
        );
      }
    });

    test('pause returns to any working state', () {
      expect(
        isTransitionAllowed(SaveState.paused, SaveState.fetchingAssets),
        isTrue,
      );
      expect(
        isTransitionAllowed(SaveState.paused, SaveState.scrolling),
        isTrue,
      );
    });

    test('terminal states are terminal, and only restart into a new save', () {
      for (final state in [
        SaveState.complete,
        SaveState.partial,
        SaveState.failed,
        SaveState.cancelled,
      ]) {
        expect(state.isTerminal, isTrue);
        expect(state.isRunning, isFalse);
        expect(isTransitionAllowed(state, SaveState.fetchingAssets), isFalse);
        expect(isTransitionAllowed(state, SaveState.inspecting), isTrue);
      }
    });

    test('idle and paused are not "running"', () {
      expect(SaveState.idle.isRunning, isFalse);
      expect(SaveState.paused.isRunning, isFalse);
      expect(SaveState.scrolling.isRunning, isTrue);
    });

    test('staying in the same state is always legal', () {
      for (final state in SaveState.values) {
        expect(isTransitionAllowed(state, state), isTrue);
      }
    });

    test('every state has a human label', () {
      for (final state in SaveState.values) {
        expect(state.label, isNotEmpty);
      }
    });
  });

  group('SaveProgress', () {
    test('copyWith preserves untouched fields', () {
      const p = SaveProgress(
        state: SaveState.fetchingAssets,
        currentUrl: 'https://x.example/1',
        detectedImages: 6,
        requestedEntries: 3,
      );
      final next = p.copyWith(storedImages: 4);

      expect(next.storedImages, 4);
      expect(next.detectedImages, 6);
      expect(next.currentUrl, 'https://x.example/1');
      expect(next.requestedEntries, 3);
      expect(next.state, SaveState.fetchingAssets);
    });

    test('clearError wipes the error rather than carrying it forward', () {
      const p = SaveProgress(lastError: 'HTTP 503');
      expect(p.copyWith(clearError: true).lastError, isNull);
      expect(p.copyWith(storedImages: 1).lastError, 'HTTP 503');
    });
  });
}
