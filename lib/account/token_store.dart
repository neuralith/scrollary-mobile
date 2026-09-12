/// Where the session lives on the device.
///
/// Platform secure storage — Keychain on iOS, EncryptedSharedPreferences on
/// Android — and never the settings table. A refresh token is a bearer
/// credential valid for months; putting one in the app database would put it in
/// every backup and every debug dump of that table.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One stored session.
class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
  });

  final String accessToken;
  final String refreshToken;

  /// The account this session belongs to.
  ///
  /// Kept because it is the question the app must ask before it decides what to
  /// do with the library already on the device: signing in again as the same
  /// account is an ordinary resume, and signing in as a different one is not.
  final String userId;
}

/// Reads and writes the session.
///
/// Every method tolerates storage being unavailable. Secure storage genuinely
/// fails in the field — a device restored from a backup that could not restore
/// the Keychain, an Android keystore invalidated by a credential change — and
/// the honest outcome of that is "signed out", which the app already handles
/// completely. Throwing instead would take a working local library down with a
/// failure that has nothing to do with it.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android's defaults in flutter_secure_storage 11 are already the
            // strong ones — AES-GCM data with an RSA-OAEP-wrapped key in the
            // Keystore. The `encryptedSharedPreferences` flag earlier versions
            // needed is gone because it is no longer optional.
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              // The session is useless without the device unlocked, and this
              // keeps it out of iCloud Keychain sync: a session is per-device
              // by design, because each device has its own refresh token and
              // its own revocation.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'scrollary.access_token';
  static const _refreshKey = 'scrollary.refresh_token';
  static const _userKey = 'scrollary.user_id';

  /// The stored session, or null when there is none to read.
  Future<StoredSession?> read() async {
    try {
      final access = await _storage.read(key: _accessKey);
      final refresh = await _storage.read(key: _refreshKey);
      final user = await _storage.read(key: _userKey);
      if (access == null || refresh == null || user == null) return null;
      if (access.isEmpty || refresh.isEmpty) return null;
      return StoredSession(
        accessToken: access,
        refreshToken: refresh,
        userId: user,
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(StoredSession session) async {
    try {
      await _storage.write(key: _accessKey, value: session.accessToken);
      await _storage.write(key: _refreshKey, value: session.refreshToken);
      await _storage.write(key: _userKey, value: session.userId);
    } on Object {
      // Nothing to tell the user: they are signed in for this run, and will be
      // asked again next launch. Failing the sign-in they just completed would
      // be worse than a session that does not survive a restart.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
      await _storage.delete(key: _userKey);
    } on Object {
      // A clear that cannot be written still clears the in-memory session.
    }
  }
}
