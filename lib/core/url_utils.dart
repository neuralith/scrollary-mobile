/// URL normalisation and next-page validation. Pure Dart, no I/O — this is the
/// module that stops navigation loops and duplicate entries, so it is unit
/// tested directly.
library;

const _trackingParams = <String>{
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'fbclid',
  'gclid',
  'igshid',
  'ref',
  'source',
  '_ga',
};

/// Deny-listed path fragments that a "next entry" link must never point at.
const _denyPathPatterns = <String>[
  '/login',
  '/signin',
  '/sign-in',
  '/logout',
  '/signout',
  '/register',
  '/signup',
  '/sign-up',
  '/account',
  '/subscribe',
];

/// Stable identity for a page: the normalised URL string.
///
/// Deliberately does NOT strip `www.` or unify http/https — both can merge
/// genuinely distinct origins, and cookies are scheme-scoped.
String normalizeUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme) return raw.trim();

  final query = Map<String, List<String>>.from(uri.queryParametersAll)
    ..removeWhere((k, _) => _trackingParams.contains(k.toLowerCase()));
  final sortedKeys = query.keys.toList()..sort();

  var path = uri.path.replaceAll(RegExp(r'/{2,}'), '/');
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  final buffer = StringBuffer()
    ..write(uri.scheme.toLowerCase())
    ..write('://')
    ..write(uri.host.toLowerCase());
  if (uri.hasPort && !_isDefaultPort(uri.scheme, uri.port)) {
    buffer.write(':${uri.port}');
  }
  buffer.write(path.isEmpty ? '/' : path);
  if (sortedKeys.isNotEmpty) {
    final parts = <String>[];
    for (final k in sortedKeys) {
      for (final v in query[k]!) {
        parts.add(v.isEmpty ? k : '$k=$v');
      }
    }
    buffer.write('?${parts.join('&')}');
  }
  return buffer.toString();
}

bool _isDefaultPort(String scheme, int port) =>
    (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443);

/// Identity of a *page as presented*, for matching UI state to what is on
/// screen (D58). The normalised URL with the fragment removed: `#comments` is
/// the same page, so a hash-only jump is not a new page.
///
/// Empty for anything that is not a renderable web page — `about:blank`, app
/// schemes, junk. Empty means "no page", which is why nothing can match it.
String pageIdentityKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
  if (uri.scheme != 'http' && uri.scheme != 'https') return '';
  return normalizeUrl(uri.removeFragment().toString());
}

/// Resolve [href] (possibly relative) against [base].
String? resolveUrl(String base, String href) {
  if (href.trim().isEmpty) return null;
  final baseUri = Uri.tryParse(base);
  if (baseUri == null) return null;
  try {
    return baseUri.resolve(href.trim()).toString();
  } catch (_) {
    return null;
  }
}

enum NextUrlRejection {
  unparseable,
  unsupportedScheme,
  sameAsCurrent,
  alreadyVisited,
  differentHost,
  denyListed,
}

class NextUrlCheck {
  const NextUrlCheck.accepted(this.normalized)
    : rejection = null,
      crossHost = false;
  const NextUrlCheck.rejected(this.rejection, {this.crossHost = false})
    : normalized = null;

  final String? normalized;
  final NextUrlRejection? rejection;
  final bool crossHost;

  bool get isAccepted => rejection == null;
}

/// Validate a next-page candidate before navigating to it.
///
/// [visited] holds already-normalised URLs from this run, which is what
/// prevents A -> B -> A loops.
NextUrlCheck validateNextUrl({
  required String candidate,
  required String currentUrl,
  required Set<String> visited,
  bool allowCrossHost = false,
}) {
  final resolved = resolveUrl(currentUrl, candidate);
  if (resolved == null) {
    return const NextUrlCheck.rejected(NextUrlRejection.unparseable);
  }

  final uri = Uri.tryParse(resolved);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return const NextUrlCheck.rejected(NextUrlRejection.unparseable);
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return const NextUrlCheck.rejected(NextUrlRejection.unsupportedScheme);
  }

  final lowerPath = uri.path.toLowerCase();
  if (_denyPathPatterns.any(lowerPath.contains)) {
    return const NextUrlCheck.rejected(NextUrlRejection.denyListed);
  }

  // Fragments are normalised away: #comments is the same page.
  final normalized = normalizeUrl(uri.removeFragment().toString());
  final currentNormalized = normalizeUrl(
    (Uri.tryParse(currentUrl)?.removeFragment() ?? Uri()).toString(),
  );

  if (normalized == currentNormalized) {
    return const NextUrlCheck.rejected(NextUrlRejection.sameAsCurrent);
  }
  if (visited.contains(normalized)) {
    return const NextUrlCheck.rejected(NextUrlRejection.alreadyVisited);
  }

  final currentHost = Uri.tryParse(currentUrl)?.host.toLowerCase();
  final crossHost =
      currentHost != null && currentHost != uri.host.toLowerCase();
  if (crossHost && !allowCrossHost) {
    return const NextUrlCheck.rejected(
      NextUrlRejection.differentHost,
      crossHost: true,
    );
  }

  return NextUrlCheck.accepted(normalized);
}

String hostOf(String url) => Uri.tryParse(url)?.host ?? url;
