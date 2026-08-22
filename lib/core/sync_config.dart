/// Where the development sync service lives, if anywhere.
///
/// **Compile-time only, and deliberately.** There is no sign-in yet and no
/// production endpoint, so the address of a service is a property of the build
/// a developer made rather than a setting a user typed. Passing nothing — which
/// is what a Store build does — folds [kSyncBaseUrl] to the empty string, and
/// every sync affordance then reports the honest `neverConfigured` state
/// instead of reaching for a host that is not there.
///
/// ```sh
/// flutter run --dart-define=SCROLLARY_SYNC_BASE_URL=http://127.0.0.1:8080
/// ```
///
/// **Which address, on which target.** The define carries whichever of these
/// the developer needs; nothing in the app guesses, and no machine address is
/// ever compiled in:
///
///  * **iOS Simulator** — shares the host's network stack, so the loopback
///    address 127.0.0.1 reaches a service running on the Mac.
///  * **Android emulator** — is its own virtual device, and reaches the host
///    machine at the alias 10.0.2.2 (its own 127.0.0.1 is the emulator).
///  * **A physical device** — has neither, and needs the host's address on the
///    LAN the phone is joined to.
///
/// The library name rides the development-only `X-Scrollary-Library` header
/// (V2-D28); production authentication replaces the header without changing a
/// payload.
library;

/// The service's base URL, or the empty string when this build has none.
const String kSyncBaseUrl = String.fromEnvironment('SCROLLARY_SYNC_BASE_URL');

/// Which library on that service this build talks to.
const String kSyncLibraryName = String.fromEnvironment(
  'SCROLLARY_SYNC_LIBRARY',
  defaultValue: 'development',
);

/// The configured endpoint, or null when this build has none.
///
/// Null is the ordinary state, not a failure: an unparseable or relative value
/// is treated exactly like an absent one, because a half-usable address would
/// turn a missing define into a runtime error somewhere far away from it.
Uri? get syncBaseUri {
  final raw = kSyncBaseUrl.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return uri;
}
