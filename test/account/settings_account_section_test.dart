/// The Settings account section: what a person is offered, and when.
///
/// The binding rule this file protects is V2-D3 — the app is the complete
/// product with no account, permanently. Signing in is one row in Settings, it
/// is never asked for, and a build that cannot reach a service does not offer
/// it at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/account/account_api.dart';
import 'package:web_reader/account/account_controller.dart';
import 'package:web_reader/account/firebase_sign_in.dart';
import 'package:web_reader/account/token_store.dart';
import 'package:web_reader/features/account_section.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/ui/theme.dart';

class _MemoryTokens implements TokenStore {
  StoredSession? session;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession s) async => session = s;

  @override
  Future<void> clear() async => session = null;
}

/// Never called: no test here reaches a provider, which is the point — the
/// section must render in every state without starting Firebase.
class _NeverUsedProviders implements ProviderSignIn {
  var used = false;

  @override
  Future<String> idToken(SignInProvider provider) async {
    used = true;
    throw const SignInFailure('not reachable in a widget test');
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  late _NeverUsedProviders providers;

  setUp(() => providers = _NeverUsedProviders());

  AccountController controller({required bool configured}) {
    final c = AccountController(
      tokens: _MemoryTokens(),
      // A base URL that is never actually contacted: every case here asserts
      // on what is rendered, and none of them taps a button that would call.
      api: configured
          ? AccountApi(baseUrl: Uri.parse('http://127.0.0.1:9'))
          : null,
      providers: providers,
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget host(AccountController? account) => ProviderScope(
    overrides: [accountProvider.overrideWithValue(account)],
    child: MaterialApp(
      theme: appTheme(),
      home: const Scaffold(
        body: SingleChildScrollView(child: AccountSection()),
      ),
    ),
  );

  testWidgets('a build with no service address offers no account at all', (
    tester,
  ) async {
    await tester.pumpWidget(host(controller(configured: false)));

    expect(find.byKey(const ValueKey('accountSignedOut')), findsNothing);
    expect(find.byKey(const ValueKey('accountSignInApple')), findsNothing);
    expect(find.byKey(const ValueKey('accountSignInGoogle')), findsNothing);
    expect(
      find.text('ACCOUNT'),
      findsNothing,
      reason: 'an account that could reach nothing is a dead end, not a door',
    );
  });

  testWidgets('a widget test with no account renders nothing and does not '
      'crash', (tester) async {
    await tester.pumpWidget(host(null));
    expect(find.byType(AccountSection), findsOneWidget);
    expect(find.text('ACCOUNT'), findsNothing);
  });

  testWidgets(
    'signed out, both providers are offered and neither is demanded',
    (tester) async {
      await tester.pumpWidget(host(controller(configured: true)));

      expect(find.byKey(const ValueKey('accountSignedOut')), findsOneWidget);
      expect(find.byKey(const ValueKey('accountSignInApple')), findsOneWidget);
      expect(find.byKey(const ValueKey('accountSignInGoogle')), findsOneWidget);

      // The copy has to say the app already works. A sign-in row that implies
      // otherwise is the first step towards an account being required.
      expect(
        find.textContaining('Everything works without an account'),
        findsOneWidget,
      );
    },
  );

  testWidgets('rendering the section never starts a provider', (tester) async {
    await tester.pumpWidget(host(controller(configured: true)));
    await tester.pump();

    expect(
      providers.used,
      isFalse,
      reason: 'Firebase must not be initialized by looking at Settings',
    );
    expect(
      FirebaseInitializer.isInitialized,
      isFalse,
      reason: 'and certainly not by mounting a widget',
    );
  });

  // The signed-in row is asserted on its own, without a session or a socket.
  // What it says is the part that matters: somebody deciding whether to sign
  // out is deciding whether they lose their library (V2-D11), and the copy has
  // to answer that before they tap.
  testWidgets('the signed-in row offers sign-out and promises what it keeps', (
    tester,
  ) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: AccountSignedInTile(busy: false, onSignOut: () => signOuts++),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('accountSignedIn')), findsOneWidget);
    expect(
      find.textContaining('Signing out keeps everything on this device'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sign out'));
    expect(signOuts, 1);
  });

  testWidgets('a sign-out in flight offers no second tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: AccountSignedInTile(busy: true, onSignOut: () {})),
      ),
    );

    expect(find.text('Sign out'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
