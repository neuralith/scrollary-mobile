/// The silent footgun in the single-operation architecture.
///
/// There is one WebView. Everything that drives it — a download run, a
/// Collection check, the library-wide check — goes through [OperationLane], so
/// a second request queues behind the first instead of navigating the page out
/// from under it. Nothing about calling `QueueRunner.start()` or
/// `CheckController.run()` directly fails to compile, fails analysis, or fails
/// a widget test of the feature that does it. It fails on a device, as two
/// operations reading the same page, and the symptom lands on whichever of
/// them noticed first.
///
/// That is exactly how the bug this lane exists for arrived: `CheckController`
/// guarded itself with `browser.isAutomating`, the download path never set it,
/// and each start surface knew only about its own kind of work. So the rule
/// fails here instead. This test finds every place in `lib/` that starts
/// Browser-driving work and refuses any that is not one of the four sites
/// below.
///
/// **If this test fails, do not add an exception.** Route the new start through
/// `OperationLane.submit` — `lib/features/operation_lane.dart` — and then add
/// its file here. The entry in this list is the record that somebody thought
/// about it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How work is started, by the expression that starts it.
///
/// Deliberately shaped around the *names*, not the types: a guard that needed
/// resolved types would need an analyser, and these three receivers are named
/// the same way everywhere in this repository. `\b` before `controller`
/// does not match `_controller`, which is the startup controller in
/// `main.dart` and has nothing to do with the Browser.
const Map<String, String> kStartExpressions = {
  'a download run (QueueRunner.start)': r'[Rr]unner[A-Za-z]*\)?\.start\b',
  'a Collection check (CheckController.run)': r'[Cc]heck[A-Za-z]*\)?\.run\b',
  'the library-wide check (LibraryCheckController.run)':
      r'(?<![A-Za-z0-9_])controller\.run\b',
};

/// Where a start is allowed to be written, and how many there are.
///
/// The count is part of the guard: a second start added to a file that already
/// has one is the same mistake as a start in a new file, and without the count
/// the allow-list would wave it through.
const Map<String, int> kAuthorisedStartSites = {
  // The shell's `_startQueuedDownloads`, inside `lane.submit`. The only place
  // V2 Browser automation is authorised from.
  'lib/app.dart': 1,
  // `startCollectionCheck`, inside `lane.submit`.
  'lib/features/v2_check_flow.dart': 1,
  // `startLibraryCheck`, inside `lane.submit`.
  'lib/features/library_check_button.dart': 1,
  // The library-wide pass driving `CheckController` once per Collection. This
  // one is **inside** a request the lane is already running, so it must not
  // submit again — a nested submit would wait for itself. It is the single
  // documented exception, and the test below pins that it stays single.
  'lib/features/library_check_flow.dart': 1,
};

/// The file whose start is *inside* another request, so it holds the lane
/// rather than joining it.
const String kNestedStartSite = 'lib/features/library_check_flow.dart';

/// Every start expression in [source], as `line number → what it starts`.
///
/// Comment lines are skipped: the prose explaining this rule names the calls it
/// governs, and a guard that fired on its own documentation would be noise.
/// Extracted so it can be pointed at a deliberately broken sample as well as at
/// the real tree — a check that has never been seen to fail is not evidence of
/// anything.
Map<int, String> startsIn(String source) {
  final found = <int, String>{};
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    for (final entry in kStartExpressions.entries) {
      if (RegExp(entry.value).hasMatch(line)) {
        found[i + 1] = entry.key;
        break;
      }
    }
  }
  return found;
}

Iterable<File> _dartFilesUnderLib() sync* {
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) yield file;
  }
}

void main() {
  test('the guard actually catches a start written outside the lane', () {
    // Exactly the mistake a future contributor will make: a new screen with a
    // Start button that reaches for the runner, because that is the shortest
    // thing that works.
    const broken = '''
      Future<void> _onStartPressed() async {
        await ref.read(queueRunnerProvider).start();
      }
''';
    expect(
      startsIn(broken).values,
      contains('a download run (QueueRunner.start)'),
      reason: 'a guard that cannot fail is not a guard',
    );

    // …and the same for a check.
    const brokenCheck = '''
      final outcome = await check.run(collectionId, limits: limits);
''';
    expect(
      startsIn(brokenCheck).values,
      contains('a Collection check (CheckController.run)'),
    );
  });

  test('the guard does not fire on the startup controller', () {
    // `main.dart` runs the startup sequence through a controller of its own.
    // It drives no Browser and must not be caught by the library-check rule.
    expect(startsIn('    unawaited(_finishWhenReady(_controller.run()));'), {});
  });

  test('nothing outside the authorised sites starts Browser work', () {
    final offences = <String>[];
    for (final file in _dartFilesUnderLib()) {
      final path = file.path;
      if (kAuthorisedStartSites.containsKey(path)) continue;
      startsIn(file.readAsStringSync()).forEach((line, what) {
        offences.add('$path:$line — starts $what');
      });
    }

    expect(
      offences,
      isEmpty,
      reason:
          'These start Browser-driving work without going through the one '
          'OperationLane, so they can run beside a download or a check that '
          'is already using the WebView. Submit the work through '
          'OperationLane.submit (lib/features/operation_lane.dart) and add the '
          'file to kAuthorisedStartSites:\n  ${offences.join('\n  ')}',
    );
  });

  test('each authorised site still has exactly the starts it is allowed', () {
    final wrong = <String>[];
    kAuthorisedStartSites.forEach((path, expected) {
      final file = File(path);
      if (!file.existsSync()) {
        wrong.add('$path — no longer exists; update kAuthorisedStartSites');
        return;
      }
      final found = startsIn(file.readAsStringSync());
      if (found.length != expected) {
        wrong.add(
          '$path — expected $expected start(s), found ${found.length} '
          '(lines ${found.keys.join(', ')})',
        );
      }
    });

    expect(
      wrong,
      isEmpty,
      reason:
          'A start added to a file that already had one is the same mistake as '
          'a start in a new file. Route it through OperationLane.submit, then '
          'raise the count here:\n  ${wrong.join('\n  ')}',
    );
  });

  test('every authorised site goes through the lane, except the nested one', () {
    final missing = <String>[];
    for (final path in kAuthorisedStartSites.keys) {
      if (path == kNestedStartSite) continue;
      final source = File(path).readAsStringSync();
      if (!source.contains('operationLaneProvider') ||
          !source.contains('.submit(')) {
        missing.add(path);
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'A file listed as an authorised start site must read the lane and '
          'submit to it; being on the list is not what makes the work '
          'serialised:\n  ${missing.join('\n  ')}',
    );

    // And the nested one must **not** submit, or it would wait for the request
    // it is already running inside.
    final nested = File(kNestedStartSite).readAsStringSync();
    expect(
      nested.contains('.submit('),
      isFalse,
      reason:
          '$kNestedStartSite runs inside a request the lane is already '
          'holding. Submitting again would deadlock the pass against itself.',
    );
  });
}
