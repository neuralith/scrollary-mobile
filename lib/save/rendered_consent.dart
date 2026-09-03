/// Whether this Source may be kept as a rendering of its pages.
///
/// **Asked once per Source, and never assumed.** A rendering is not the site's
/// own files and never will be, so whether a shorter, re-encoded copy is worth
/// having is a judgement about what the person wants — not one the app can
/// make for them. Until they have answered, the capture stops with its named
/// reason exactly as it did before the fallback existed; silence is not
/// consent.
///
/// Once, not per Entry: a Collection saved an Entry at a time would otherwise
/// ask the same question on every one of them, and the answer is about the
/// site rather than about the page in front of the user.
///
/// **Device-local, in the settings table**, for the reason
/// `capture_preference.dart` gives at length: the schema is frozen at version
/// one with no migration path, and a setting is a string under a key its owner
/// names. It is also genuinely device-local — a rendering is a decision about
/// bytes on *this* device, like the keep-or-remove answer in
/// `forward_transition.dart`.
library;

import '../core/url_utils.dart';
import '../data/local_settings.dart';
import '../data/recognition_index.dart';

/// The settings key a Source's answer lives under.
///
/// Namespaced by the Source's own key, so there is one row per Source and
/// forgetting one cannot touch another. Exposed for the test that pins the
/// spelling: a key that changes silently is an answer that silently vanishes,
/// and the user would be asked again on a site they had already decided about.
String renderedFallbackKeyFor(String sourceKey) =>
    'rendered_fallback.$sourceKey';

/// What the user said about keeping this Source as renderings.
enum RenderedFallbackChoice {
  allowed,
  declined;

  static RenderedFallbackChoice? fromName(String? name) {
    for (final choice in RenderedFallbackChoice.values) {
      if (choice.name == name) return choice;
    }
    // An unrecognised stored value is not a decision. Falling back to a value
    // would be answering on the user's behalf, which is the one thing this
    // file exists to prevent.
    return null;
  }
}

/// Reads and writes the per-Source answer.
class RenderedFallbackConsentStore {
  const RenderedFallbackConsentStore(this._settings);

  final LocalSettingsStore _settings;

  /// What the user said, or null when they have never been asked.
  Future<RenderedFallbackChoice?> of(String sourceKey) async {
    if (sourceKey.isEmpty) return null;
    return RenderedFallbackChoice.fromName(
      await _settings.get(renderedFallbackKeyFor(sourceKey)),
    );
  }

  /// True when this Source may be kept as renderings. **False for undecided**,
  /// which is the whole point: the caller cannot tell the two apart by
  /// accident.
  Future<bool> allows(String sourceKey) async =>
      await of(sourceKey) == RenderedFallbackChoice.allowed;

  Future<void> record(String sourceKey, RenderedFallbackChoice choice) {
    if (sourceKey.isEmpty) return Future<void>.value();
    return _settings.set(renderedFallbackKeyFor(sourceKey), choice.name);
  }

  /// Forget the answer, so the next refused reading asks again.
  Future<void> forget(String sourceKey) =>
      _settings.remove(renderedFallbackKeyFor(sourceKey)).then((_) {});
}

/// The key a Source's answer is stored under, resolved from a page address.
///
/// The Source when the page's Location has one, because that is the thing the
/// question is about — a site, as the library understands it. A page nobody
/// has adopted into a Source yet still deserves *one* answer rather than one
/// per Entry, and its host is the most specific thing there is to hang that
/// on; the two are namespaced apart so an adopted page never inherits an
/// answer given about a bare host, or the reverse.
Future<String> renderedFallbackSourceKey(
  String pageUrl,
  RecognitionIndex index,
) async {
  final hit = await index.lookupUrl(normalizeUrl(pageUrl));
  final sourceId = hit?.location.sourceId;
  if (sourceId != null && sourceId.isNotEmpty) return 'source:$sourceId';
  final host = hostOf(pageUrl);
  return host.isEmpty ? '' : 'host:$host';
}

/// Answers "may this Source be kept as renderings", asking once and
/// remembering.
///
/// The engine holds one of these behind `SaveEngine.renderedConsent`. It is
/// the whole of the consent rule in one place: a stored answer is obeyed, no
/// stored answer means the user is asked, and **no way to ask means no**.
class RenderedFallbackGate {
  const RenderedFallbackGate({
    required this.index,
    required this.store,
    required this.ask,
  });

  final RecognitionIndex index;
  final RenderedFallbackConsentStore store;

  /// Puts the question to the user, or null when there is no surface to put it
  /// on — a suite that wired no shell, a drain with nobody watching. Null
  /// answers *no*, which leaves the capture stopping with its named reason
  /// rather than deciding on the user's behalf while they are not looking.
  final Future<bool> Function(String pageUrl)? ask;

  Future<bool> call(String pageUrl) async {
    final key = await renderedFallbackSourceKey(pageUrl, index);
    if (key.isEmpty) return false;
    final stored = await store.of(key);
    if (stored != null) return stored == RenderedFallbackChoice.allowed;

    final prompt = ask;
    if (prompt == null) return false;
    final answer = await prompt(pageUrl);
    // Recorded either way. "No" is an answer, and a Source the user declined
    // must not be asked again on its next Entry.
    await store.record(
      key,
      answer ? RenderedFallbackChoice.allowed : RenderedFallbackChoice.declined,
    );
    return answer;
  }
}
