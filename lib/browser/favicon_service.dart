import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/database.dart';

/// Favicons are decoration (§12, D55).
///
/// Nothing waits on one: history rows, saved sites and suggestions are all
/// written and rendered whether or not an icon ever arrives, and a list shows
/// the hostname-initial fallback in a box of exactly the same size, so an
/// icon landing later never moves a row.
///
/// Cached per host in SQLite, including *failures* — a site with no icon
/// would otherwise be re-requested on every rebuild of every list.
class FaviconService extends ChangeNotifier {
  FaviconService({required this.db, Dio? client, this.allowNetwork = true})
    : _client =
          client ?? Dio(BaseOptions(followRedirects: true, maxRedirects: 3));

  final AppDatabase db;
  final Dio _client;

  /// Whether a cache miss may go to the network.
  ///
  /// False in widget tests, which are network-free by construction — and
  /// where an in-flight HTTP request outlives the widget tree and fails the
  /// pending-timer invariant. A miss then simply renders the fallback, which
  /// is a state the UI has to handle correctly anyway.
  final bool allowNetwork;

  /// An icon larger than this is not worth storing to draw at 30pt.
  static const int maxBytes = 24 * 1024;

  /// How long a negative result stands before another attempt is allowed.
  static const Duration retryAfterFailure = Duration(days: 7);

  /// host -> bytes (null = known-missing). Mirrors the table so a list build
  /// is synchronous; populated by [warmUp] and by each fetch.
  final Map<String, Uint8List?> _memory = {};
  final Set<String> _inFlight = {};
  bool _disposed = false;

  /// Load the cache into memory once, at boot.
  Future<void> warmUp() async {
    for (final row in await db.allFavicons()) {
      _memory[row.host] = row.bytes;
    }
    _safeNotify();
  }

  /// The icon for [host] if it is already known. Never triggers I/O — callers
  /// in a `build` want an answer now, and [request] is how they ask for one.
  Uint8List? cached(String host) => _memory[_key(host)];

  bool isKnown(String host) => _memory.containsKey(_key(host));

  /// Ask for [host]'s icon, at most once.
  ///
  /// Returns immediately; listeners are notified if bytes arrive. [pageIcon]
  /// is the URL the page itself declared (`<link rel="icon">` or the
  /// WebView's own callback) — a much better source than the guessed
  /// `/favicon.ico`, which is only ever a low-confidence fallback.
  void request(String host, {String? pageIcon, String? scheme}) {
    final key = _key(host);
    if (key.isEmpty || _inFlight.contains(key)) return;
    if (_memory.containsKey(key) && pageIcon == null) return;
    _inFlight.add(key);
    unawaited(
      _fetch(
        key,
        pageIcon: pageIcon,
        scheme: scheme ?? 'https',
      ).whenComplete(() => _inFlight.remove(key)),
    );
  }

  /// Store bytes the WebView handed us directly.
  Future<void> put(String host, Uint8List bytes, {String? sourceUrl}) async {
    final key = _key(host);
    if (key.isEmpty || bytes.isEmpty || bytes.length > maxBytes) return;
    _memory[key] = bytes;
    await db.putFavicon(
      FaviconCacheData(
        host: key,
        bytes: bytes,
        sourceUrl: sourceUrl,
        fetchedAt: DateTime.now(),
      ),
    );
    _safeNotify();
  }

  Future<void> _fetch(
    String host, {
    String? pageIcon,
    required String scheme,
  }) async {
    final existing = await db.favicon(host);
    if (existing != null) {
      _memory[host] = existing.bytes;
      // A previous miss is honoured for a while; a previous hit stands until
      // the page hands us something better.
      final stale =
          DateTime.now().difference(existing.fetchedAt) > retryAfterFailure;
      if (existing.bytes != null || (!stale && pageIcon == null)) {
        _safeNotify();
        return;
      }
    }

    if (!allowNetwork) {
      // Deliberately no negative-cache write: nothing was attempted, so a
      // later run with the network on must still be free to try.
      return;
    }

    final candidates = <String>[
      if (pageIcon != null && pageIcon.trim().isNotEmpty) pageIcon.trim(),
      '$scheme://$host/favicon.ico',
    ];

    for (final candidate in candidates) {
      final bytes = await _download(candidate);
      if (bytes == null) continue;
      _memory[host] = bytes;
      await db.putFavicon(
        FaviconCacheData(
          host: host,
          bytes: bytes,
          sourceUrl: candidate,
          fetchedAt: DateTime.now(),
        ),
      );
      _safeNotify();
      return;
    }

    // Remember the miss so the next twenty list builds do not retry it.
    _memory[host] = null;
    await db.putFavicon(
      FaviconCacheData(host: host, fetchedAt: DateTime.now()),
    );
    _safeNotify();
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final response = await _client.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // A favicon is never worth a long wait; the fallback is already on
          // screen.
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 6),
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty || data.length > maxBytes) return null;
      final bytes = Uint8List.fromList(data);
      // An HTML error page served with a 200 is the common "no favicon"
      // answer; it is not an image and must not be cached as one.
      return _looksLikeImage(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Magic-number sniff. The same principle as stored entry assets (D31):
  /// trust the bytes, not the extension or the Content-Type.
  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // ICO / CUR
    if (bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        (bytes[2] == 0x01 || bytes[2] == 0x02)) {
      return true;
    }
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return true;
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // WebP ("RIFF")
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // SVG — text, so only a cheap prefix check.
    final head = String.fromCharCodes(bytes.take(64)).trimLeft();
    return head.startsWith('<svg') || head.startsWith('<?xml');
  }

  /// Website data was cleared: the icons came from those sites too.
  Future<void> clear() async {
    _memory.clear();
    await db.clearFavicons();
    _safeNotify();
  }

  static String _key(String host) {
    final clean = host.trim().toLowerCase();
    return clean.startsWith('www.') ? clean.substring(4) : clean;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
