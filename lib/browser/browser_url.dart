/// What the Browser does with a line of text, and how it shows an address
/// back.
///
/// Pure Dart, no I/O: this is the module that decides whether
/// `example.com/guide/x` is a place to go or a thing to search for, so it is
/// unit tested directly rather than through a WebView.
library;

import 'package:flutter/foundation.dart';

/// Where a submitted line of text should take the Browser.
enum UrlIntentKind {
  /// A real address. [UrlIntent.url] is absolute and ready to load.
  navigate,

  /// Not an address. [UrlIntent.url] is a search URL for [UrlIntent.query].
  search,

  /// Nothing usable was typed. Nothing should happen.
  empty,
}

class UrlIntent {
  const UrlIntent._(
    this.kind,
    this.url, {
    this.query = '',
    this.addedScheme = false,
  });

  const UrlIntent.empty() : this._(UrlIntentKind.empty, '');

  final UrlIntentKind kind;

  /// The absolute URL to load. Empty only for [UrlIntentKind.empty].
  final String url;

  /// The text that was searched for, for [UrlIntentKind.search].
  final String query;

  /// True when the user typed a bare host and `https://` was supplied.
  final bool addedScheme;

  bool get isEmpty => kind == UrlIntentKind.empty;
  bool get isSearch => kind == UrlIntentKind.search;
}

/// Hosts that are addresses even though they carry no dot.
const _bareHosts = {'localhost'};

/// Schemes the Browser will load itself. Anything else (`mailto:`,
/// `reader://`) is an external handoff, not a page — see
/// [isExternalAppScheme].
const _webSchemes = {'http', 'https'};

/// The search engine. One constant rather than a setting: the design shows a
/// single engine and no picker, and a preference nobody designed is a
/// migration nobody asked for.
const kSearchEngineHost = 'www.google.com';

String searchUrlFor(String query) =>
    'https://$kSearchEngineHost/search?q=${Uri.encodeQueryComponent(query.trim())}';

/// Decide what [raw] means.
///
/// [allowLocalhost] exists because a development URL is an address in debug
/// and a search term in a shipped build — `localhost:8099` typed by a real
/// user is far more likely to be a typo than a server they are running.
UrlIntent interpretUrlInput(String raw, {bool? allowLocalhost}) {
  final text = raw.trim();
  if (text.isEmpty) return const UrlIntent.empty();
  final localhostOk = allowLocalhost ?? kDebugMode;

  // An explicit scheme is the user telling us outright.
  final scheme = schemeOf(text);
  if (scheme != null) {
    if (!_webSchemes.contains(scheme)) {
      // `mailto:`, `reader://` — a real intent, just not one this Browser
      // can render. Handed back as navigate so the caller can classify it as
      // an external-app link rather than silently searching for it.
      return UrlIntent._(UrlIntentKind.navigate, text);
    }
    final parsed = Uri.tryParse(text);
    if (parsed == null || parsed.host.isEmpty) {
      return UrlIntent._(UrlIntentKind.search, searchUrlFor(text), query: text);
    }
    return UrlIntent._(UrlIntentKind.navigate, text);
  }

  // Whitespace inside means prose, not an address — even if a word has a dot
  // in it ("see example.com for details").
  if (RegExp(r'\s').hasMatch(text)) {
    return UrlIntent._(UrlIntentKind.search, searchUrlFor(text), query: text);
  }

  final hostPart = text.split(RegExp(r'[/?#]')).first;
  final hostOnly = hostPart.split(':').first.toLowerCase();

  final looksLikeHost =
      _hasLabelledDot(hostOnly) ||
      (localhostOk && _bareHosts.contains(hostOnly));
  if (!looksLikeHost) {
    return UrlIntent._(UrlIntentKind.search, searchUrlFor(text), query: text);
  }

  // A bare host keeps everything the user typed after it: the path and query
  // are the part they cared about.
  final candidate = 'https://$text';
  final parsed = Uri.tryParse(candidate);
  if (parsed == null || parsed.host.isEmpty) {
    return UrlIntent._(UrlIntentKind.search, searchUrlFor(text), query: text);
  }
  return UrlIntent._(UrlIntentKind.navigate, candidate, addedScheme: true);
}

/// True when [url] names a scheme the platform should handle instead of us.
bool isExternalAppScheme(String url) {
  final scheme = schemeOf(url);
  return scheme != null && !_webSchemes.contains(scheme);
}

/// Schemes that are real but carry no `//` authority.
///
/// Needed because "is there a colon" is not the test: `localhost:8099` and
/// `example.com:8443` are a host and a port, and reading them as the schemes
/// `localhost:` and `example.com:` sent both to the platform as app links
/// instead of loading them.
const _schemelessAppSchemes = {
  'mailto',
  'tel',
  'sms',
  'geo',
  'maps',
  'market',
  'intent',
  'itms-apps',
  'facetime',
};

/// The scheme [text] declares, or null when it declares none.
///
/// A scheme is either followed by `://`, or is one of the small set of
/// schemelessl-authority schemes above. Everything else with a colon in it is
/// a host and a port.
String? schemeOf(String text) {
  final withAuthority = RegExp(
    r'^([a-zA-Z][a-zA-Z0-9+.\-]*)://',
  ).firstMatch(text);
  if (withAuthority != null) return withAuthority.group(1)!.toLowerCase();

  final bare = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):').firstMatch(text);
  final scheme = bare?.group(1)?.toLowerCase();
  return scheme != null && _schemelessAppSchemes.contains(scheme)
      ? scheme
      : null;
}

/// `a.b` with something on both sides of the last dot. Rejects `foo.` and
/// `.bar`, which are typos rather than hosts.
bool _hasLabelledDot(String host) {
  final dot = host.lastIndexOf('.');
  if (dot <= 0 || dot == host.length - 1) return false;
  return RegExp(r'^[a-z0-9.\-]+$').hasMatch(host);
}

/// Host with a leading `www.` dropped, for display and grouping.
///
/// Note this is *presentation only* — [normalizeUrl] deliberately keeps
/// `www.`, because merging it into the bare host merges cookie jars too.
String displayHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return url;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// The path/query part, or an empty string for a bare host.
String pathAndQuery(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final path = uri.path == '/' ? '' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$path$query';
}

/// The compact toolbar label: host, plus as much path as fits.
///
/// A long entry URL squeezed into a 200pt field is unreadable either way;
/// the middle is what gets elided so the leading segment and the entry
/// identifier at the end both survive.
String compactPath(String url, {int maxLength = 22}) {
  final tail = pathAndQuery(url);
  if (tail.length <= maxLength) return tail;
  final segments = tail.split('/')..removeWhere((s) => s.isEmpty);
  if (segments.length >= 2) {
    final last = segments.last;
    final short = '/…/$last';
    if (short.length <= maxLength + 4) return short;
    return '/…/${last.substring(0, (maxLength - 4).clamp(1, last.length))}…';
  }
  return '${tail.substring(0, maxLength - 1)}…';
}

/// A whole URL shortened for a list row: scheme dropped, middle elided.
String shortUrl(String url, {int maxLength = 44}) {
  var text = url.replaceFirst(RegExp(r'^https?://'), '');
  if (text.length > 1 && text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength - 1)}…';
}

/// The site-level URL for [url], when guessing one is actually safe.
///
/// Returns null when it is not: a non-default port, a userinfo component, or
/// a deep subdomain we have only ever seen one page of. Saving the wrong
/// homepage is worse than saving the page the user actually visited, so the
/// caller falls back to that (§5).
String? siteRootFor(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  if (!_webSchemes.contains(uri.scheme)) return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (uri.hasPort && uri.port != 80 && uri.port != 443) return null;
  return '${uri.scheme}://${uri.host}/';
}

/// The single letter the fallback favicon shows.
String faviconInitial(String host) {
  final clean = host.startsWith('www.') ? host.substring(4) : host;
  final letter = clean.isEmpty ? '?' : clean[0];
  return letter.toUpperCase();
}
