import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one silent footgun in the foreground-multitasking architecture.
///
/// A screen pushed above the shell must be an `AppPage`, because that is the
/// route type whose opacity follows the capability. A `GoRoute` written with
/// `builder:` instead of `pageBuilder:` gets go_router's default page, which is
/// opaque, which stops Flutter painting the shell beneath it, which stops the
/// WebView — and a running save then holds forever.
///
/// Nothing about that fails to compile, fails analysis, or fails a widget test.
/// It fails on a device, minutes into a real save, as a hang. So it fails here
/// instead: this test reads the router and refuses any route above the shell
/// that does not go through the central page helper.
///
/// **If this test fails, do not add an exception.** Route the new screen
/// through `_page()` in `lib/app.dart`. That is the whole fix, and it is one
/// word at the call site.
/// The shell route is the bottom of the stack: nothing is ever painted beneath
/// it, so it is deliberately an ordinary page.
const String kShellRoute = '/';

/// Routes above the shell that are **not** built through the page helper.
///
/// Extracted so the guard can be pointed at a deliberately broken sample as
/// well as at the real router — a check that has never been seen to fail is not
/// evidence of anything.
List<String> routesBypassingThePageHelper(String source) {
  final routerStart = source.indexOf('GoRouter(');
  if (routerStart < 0) return ['<no GoRouter found>'];
  final routerEnd = source.indexOf('\n  );', routerStart);
  final router = source.substring(
    routerStart,
    routerEnd > routerStart ? routerEnd : source.length,
  );

  final matches = RegExp(
    r"GoRoute\(\s*path:\s*'([^']+)'",
  ).allMatches(router).toList();
  if (matches.isEmpty) return ['<no routes found>'];

  final offenders = <String>[];
  for (var i = 0; i < matches.length; i++) {
    final path = matches[i].group(1)!;
    if (path == kShellRoute) continue;
    final from = matches[i].end;
    final to = i + 1 < matches.length ? matches[i + 1].start : router.length;
    final body = router.substring(from, to);
    final usesHelper = body.contains('_page(');
    // `\b` before a lowercase `builder` deliberately does not match
    // `pageBuilder`, which is the correct form.
    final usesBuilder = RegExp(r'\bbuilder\s*:').hasMatch(body);
    if (!usesHelper || usesBuilder) {
      offenders.add(
        '$path — '
        '${usesHelper ? '' : 'does not use _page(); '}'
        '${usesBuilder ? 'uses builder: instead of pageBuilder:' : ''}',
      );
    }
  }
  return offenders;
}

void main() {
  test('the guard actually catches a bypassing route', () {
    // A route written the ordinary go_router way — which is exactly the mistake
    // a future contributor will make, because it is what every example shows.
    const broken = '''
      GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (c, s) => const _Shell()),
          GoRoute(
            path: '/somewhere-new',
            builder: (context, state) => const SomeScreen(),
          ),
        ],
  );
''';
    expect(
      routesBypassingThePageHelper(broken),
      contains(startsWith('/somewhere-new')),
      reason: 'a guard that cannot fail is not a guard',
    );
  });

  test('every route above the shell is built through the page helper', () {
    final source = File('lib/app.dart').readAsStringSync();
    final offenders = routesBypassingThePageHelper(source);

    expect(
      offenders,
      isEmpty,
      reason:
          'These routes sit above the shell but are not built through _page(), '
          'so they will be opaque routes. An opaque route stops Flutter '
          'painting the shell underneath it, which stops the one WebView, '
          'which makes a running save or check hold until the user goes back. '
          'Route them through _page() in lib/app.dart:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('the page helper is the only place AppPage is constructed', () {
    // One construction site means one place to reason about, and it is the
    // place the test above checks.
    final source = File('lib/app.dart').readAsStringSync();
    final constructions = RegExp(r'AppPage<').allMatches(source).length;
    expect(
      constructions,
      1,
      reason:
          'AppPage should be constructed once, inside _page(). More than one '
          'construction site means more than one thing to keep right.',
    );
  });

  test('the shell keeps the Browser laid out at full size', () {
    // `Offstage` lays its child out with the constraints it is given. In a
    // `Stack` those are loose unless the fit says otherwise, and a WebView laid
    // out loose comes back at a different viewport than it was working at —
    // which is exactly the divergence the whole architecture exists to prevent.
    final source = File('lib/app.dart').readAsStringSync();
    final body = source.substring(source.indexOf('body: Stack('));
    expect(
      body.substring(0, 200),
      contains('fit: StackFit.expand'),
      reason:
          'the shell Stack must lay its children out at full size, or the '
          'offstage WebView is relaid out at a different viewport',
    );
  });
}
