/// Obtaining a provider ID token on the device.
///
/// This is the only file that touches Firebase, and it exists to keep that
/// true: everything above it deals in "a token, or a refusal", so the account
/// layer never learns which provider produced one and the sync engine never
/// learns that Firebase exists at all.
///
/// **Firebase is initialized lazily and never on launch.** A user who never
/// signs in never starts the SDK, never opens its network connections and
/// never has it read its configuration. That is not an optimisation: it is what
/// keeps the signed-out product genuinely the same product it was before
/// accounts existed, and what keeps `PRIVACY.md`'s claims about anonymous use
/// true rather than nearly true.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_options.dart';

/// Which provider a sign-in went through.
enum SignInProvider { google, apple }

/// A sign-in that did not produce a token.
///
/// [cancelled] is separated from every other failure because it is not an
/// error: the person changed their mind, and showing them a failure message
/// for that is telling them they did something wrong.
class SignInFailure implements Exception {
  const SignInFailure(this.message, {this.cancelled = false});

  const SignInFailure.cancelled()
    : message = 'Sign-in was cancelled.',
      cancelled = true;

  final String message;
  final bool cancelled;

  @override
  String toString() => 'SignInFailure: $message';
}

/// Lazy, idempotent Firebase initialization.
///
/// Ported in shape from the old Astrolith app, which learned the same lesson:
/// concurrent callers must wait on one initialization rather than racing to
/// start several.
class FirebaseInitializer {
  FirebaseInitializer._();

  static bool _ready = false;
  static Future<void>? _inFlight;

  /// Whether Firebase has been started in this process.
  static bool get isInitialized => _ready;

  static Future<void> ensureInitialized() {
    if (_ready) return Future<void>.value();
    return _inFlight ??=
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
            .then((_) {
              _ready = true;
              _inFlight = null;
            })
            .onError((Object error, StackTrace stack) {
              // A failed start must not be cached as "in flight" forever: the next
              // attempt has to be able to try again.
              _inFlight = null;
              throw SignInFailure(
                'Sign-in is unavailable on this device: $error',
              );
            });
  }

  /// Test seam: forget that initialization happened.
  static void resetForTests() {
    _ready = false;
    _inFlight = null;
  }
}

/// Produces a provider ID token, or throws [SignInFailure].
abstract class ProviderSignIn {
  Future<String> idToken(SignInProvider provider);

  /// Ends the provider-side session, so the next sign-in asks again which
  /// account to use rather than silently reusing the last one.
  Future<void> signOut();
}

/// The real implementation: Firebase Authentication with Google and Apple.
class FirebaseProviderSignIn implements ProviderSignIn {
  FirebaseProviderSignIn();

  bool _googleReady = false;

  @override
  Future<String> idToken(SignInProvider provider) async {
    await FirebaseInitializer.ensureInitialized();
    final credential = switch (provider) {
      SignInProvider.google => await _googleCredential(),
      SignInProvider.apple => await _appleCredential(),
    };

    final UserCredential result;
    try {
      result = await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw SignInFailure(_firebaseMessage(e));
    }

    final token = await result.user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const SignInFailure('Sign-in completed without a usable token.');
    }
    return token;
  }

  Future<AuthCredential> _googleCredential() async {
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize();
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      // Signing out first is what makes the account chooser appear. Without it
      // a device with one Google account silently reuses it, which is wrong
      // when somebody is deliberately switching accounts.
      await GoogleSignIn.instance.signOut();
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SignInFailure.cancelled();
      }
      throw SignInFailure('Google sign-in failed: ${e.code.name}.');
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SignInFailure('Google did not return an identity token.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  Future<AuthCredential> _appleCredential() async {
    if (!await SignInWithApple.isAvailable()) {
      throw const SignInFailure(
        'Sign in with Apple is not available on this device.',
      );
    }
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SignInFailure.cancelled();
      }
      throw SignInFailure('Apple sign-in failed: ${e.message}');
    }

    final identity = apple.identityToken;
    if (identity == null || identity.isEmpty) {
      throw const SignInFailure('Apple did not return an identity token.');
    }
    return OAuthProvider(
      'apple.com',
    ).credential(idToken: identity, accessToken: apple.authorizationCode);
  }

  @override
  Future<void> signOut() async {
    // Only if Firebase was ever started: a signed-out user who never signed in
    // must not cause the SDK to initialize on their way out.
    if (!FirebaseInitializer.isInitialized) return;
    try {
      await FirebaseAuth.instance.signOut();
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } on Object {
      // The local session is cleared by the caller regardless. A provider that
      // will not let go is not a reason to keep somebody signed in.
    }
  }

  String _firebaseMessage(FirebaseAuthException e) => switch (e.code) {
    'account-exists-with-different-credential' =>
      'That email is already used by a different sign-in method.',
    'invalid-credential' => 'The sign-in could not be verified. Try again.',
    'user-disabled' => 'This account has been disabled.',
    'network-request-failed' =>
      'Sign-in needs a connection, and there was none.',
    _ => 'Sign-in failed (${e.code}).',
  };
}
