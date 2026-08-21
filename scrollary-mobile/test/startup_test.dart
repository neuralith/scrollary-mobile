import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/startup.dart';

void main() {
  group('StartupController', () {
    test('runs steps in order and reports progress as it goes', () async {
      final ran = <String>[];
      final seen = <String?>[];
      final controller = StartupController([
        StartupStep(label: 'One', run: () async => ran.add('one')),
        StartupStep(label: 'Two', run: () async => ran.add('two')),
      ]);
      controller.addListener(() => seen.add(controller.value.currentLabel));

      expect(controller.value.currentLabel, 'One');
      expect(controller.value.fraction, 0);

      await controller.run();

      expect(ran, ['one', 'two']);
      // After step one the report moves to step two, then to "finished".
      expect(seen, ['Two', null]);
      expect(controller.value.finished, isTrue);
      expect(controller.value.hasFailed, isFalse);
      expect(controller.value.fraction, 1);
      expect(controller.value.warnings, isEmpty);
    });

    test('a non-critical failure is recorded and the boot continues', () async {
      final ran = <String>[];
      final controller = StartupController([
        StartupStep(
          label: 'Repairing',
          run: () async => throw StateError('nope'),
        ),
        StartupStep(label: 'Pending tasks', run: () async => ran.add('tasks')),
      ]);

      await controller.run();

      expect(ran, ['tasks'], reason: 'later steps still run');
      expect(controller.value.finished, isTrue);
      expect(controller.value.hasFailed, isFalse);
      expect(controller.value.warnings.single, contains('Repairing'));
      expect(controller.value.warnings.single, contains('nope'));
    });

    test('a critical failure stops the sequence and is fatal', () async {
      final ran = <String>[];
      final controller = StartupController([
        StartupStep(
          label: 'Opening your library',
          critical: true,
          run: () async => throw StateError('disk is gone'),
        ),
        StartupStep(label: 'Recovering', run: () async => ran.add('recover')),
      ]);

      await controller.run();

      expect(ran, isEmpty);
      expect(controller.value.hasFailed, isTrue);
      expect(controller.value.finished, isTrue);
      expect('${controller.value.error}', contains('disk is gone'));
      // The failure screen names the step that failed, so the index must
      // still point at it.
      expect(controller.value.completed, 0);
      expect(
        controller.value.labels[controller.value.completed],
        'Opening your library',
      );
    });

    test('running twice does not repeat the work', () async {
      var runs = 0;
      final controller = StartupController([
        StartupStep(label: 'Once', run: () async => runs++),
      ]);

      await controller.run();
      await controller.run();

      expect(runs, 1);
    });

    test('minStepDuration paces the report without skipping a step', () async {
      final controller = StartupController([
        StartupStep(label: 'One', run: () async {}),
        StartupStep(label: 'Two', run: () async {}),
      ], minStepDuration: const Duration(milliseconds: 40));

      final startedAt = DateTime.now();
      await controller.run();

      expect(
        DateTime.now().difference(startedAt),
        greaterThanOrEqualTo(const Duration(milliseconds: 70)),
      );
      expect(controller.value.finished, isTrue);
    });
  });
}
