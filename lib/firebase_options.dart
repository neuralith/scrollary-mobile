// Firebase project configuration for Scrollary.
//
// Written by hand from the two console-provided files already in the tree —
// `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
// — rather than by `flutterfire configure`, which would have rewritten them.
// Every value below is copied from one of those two files; nothing here is
// invented, and the three must be kept in agreement.
//
// **None of this is a secret.** A Firebase web API key identifies the project,
// it does not authorise anything: access is decided by the provider sign-in the
// user completes and by the ID token the backend verifies. The credential that
// *is* secret is the service-account JSON, which lives only on the server and
// never in a repository (see docs/FIREBASE_SETUP.md).
//
// Project: scrollary-4de0f · number 1066587397858.
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// The platform's Firebase configuration.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// Options for the platform this build is running on.
  ///
  /// Throws for a platform the console has no app registered for, rather than
  /// falling back to another platform's configuration — a wrong project is a
  /// worse failure than a missing one, because it fails later and further away.
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Scrollary has no web build. The browser extension is a separate '
        'client with its own Firebase web app.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Scrollary ships on iOS and Android. No Firebase app is registered '
          'for $defaultTargetPlatform.',
        );
    }
  }

  /// From `android/app/google-services.json`.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDYpymaSnE3mMgkQTeDPjkM8gSCRHC1lVU',
    appId: '1:1066587397858:android:d4c711fcc58c71c8b408bb',
    messagingSenderId: '1066587397858',
    projectId: 'scrollary-4de0f',
    storageBucket: 'scrollary-4de0f.firebasestorage.app',
  );

  /// From `ios/Runner/GoogleService-Info.plist`.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBpKipzUBxrzxK5scGRBRVfSsyvQAcyy90',
    appId: '1:1066587397858:ios:c52cb90f3bfd9843b408bb',
    messagingSenderId: '1066587397858',
    projectId: 'scrollary-4de0f',
    storageBucket: 'scrollary-4de0f.firebasestorage.app',
    iosClientId:
        '1066587397858-8o7quau53lb0g6t98pu6picj2ehkddqi.apps.googleusercontent.com',
    iosBundleId: 'com.mcagricaliskan.scrollary',
  );
}
