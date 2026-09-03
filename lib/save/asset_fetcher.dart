import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../browser/browser_controller.dart';
import '../core/config.dart';
import '../core/image_dimensions.dart';
import '../storage/file_store.dart';
import '../storage/manifest.dart';

/// Sniff an image format from its leading bytes.
///
/// Content-Type is not trusted: servers routinely return an HTML error page
/// with a 200 and an image content type. Returns null for anything not
/// recognised, which the caller reports as an explicit per-asset failure.
String? detectImageMime(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
    return 'image/jpeg';
  }
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'image/gif';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4d) return 'image/bmp';

  // ISO base media format: a 4-byte box length, then 'ftyp', then a brand.
  // AVIF lives here, and real image CDNs serve it — omitting this rejected
  // every panel on such a site as "not a usable image".
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
    switch (brand) {
      case 'avif':
      case 'avis':
        return 'image/avif';
      case 'heic':
      case 'heix':
      case 'hevc':
      case 'heim':
      case 'heis':
        return 'image/heic';
      case 'mif1':
      case 'msf1':
        return 'image/heif';
    }
  }
  return null;
}

/// First bytes as hex + printable ASCII, so an unrecognised format is
/// identifiable from the log instead of being an anonymous failure.
String _magicPreview(Uint8List b) {
  final n = b.length < 12 ? b.length : 12;
  final head = b.sublist(0, n);
  final hex = head.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
  final ascii = head
      .map((x) => x >= 0x20 && x < 0x7f ? String.fromCharCode(x) : '.')
      .join();
  return '$hex  "$ascii"';
}

/// What happened when a host did not hand over an image.
///
/// The distinction that matters is **settled or not**. A refusal is the host's
/// answer, and it will be the same answer next time; anything else might not
/// be. Asking again after a refusal is the "retry with different headers"
/// this app does not do, one step removed — and on a page of a hundred and
/// thirty panels it is a hundred and thirty repetitions of a question already
/// answered.
enum AssetFailure {
  /// The host answered, and the answer was no: it refused the request outright
  /// (401, 402, 403, 407, 429, 451), or it served a **web page** where an
  /// image was asked for, which is what a human-verification interstitial is.
  refused,

  /// Inconclusive — a timeout, a reset, a server error. Worth another go.
  transient,

  /// Bytes arrived and are not an image this app stores. A fact about the
  /// file, not about access.
  notAnImage,
}

/// Statuses that are the host declining, rather than the host failing.
///
/// 429 is here and not in [AssetFailure.transient] on purpose: waiting out a
/// rate limit is named in this project's rules as something the app does not
/// do, so "asked for fewer requests" is a stop like any other refusal.
const Set<int> _refusalStatuses = {401, 402, 403, 407, 429, 451};

/// Does this response body begin a web page?
///
/// A host that answers an image request with HTML has substituted something
/// for the file — an interstitial, a verification challenge, an error page.
/// Structural, and deliberately naming no vendor and no product: what is
/// recognised is "a document where a picture was asked for", which is the same
/// fact whoever served it.
bool looksLikeMarkup(Uint8List bytes) {
  var i = 0;
  // Skip a UTF-8 BOM and any leading whitespace.
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    i = 3;
  }
  while (i < bytes.length &&
      (bytes[i] == 0x20 || (bytes[i] >= 0x09 && bytes[i] <= 0x0d))) {
    i++;
  }
  final head = String.fromCharCodes(
    bytes.sublist(i, i + 15 > bytes.length ? bytes.length : i + 15),
  ).toLowerCase();
  return head.startsWith('<!doctype') ||
      head.startsWith('<html') ||
      head.startsWith('<?xml') ||
      head.startsWith('<head');
}

/// One asset's outcome, with the *kind* of failure kept beside it.
///
/// The kind lives here and not on [EntryAsset] deliberately: `manifest.json`
/// is durable user data on devices today, and how a download failed during one
/// run is a fact about that run, not about the package.
class AssetDownload {
  const AssetDownload(this.asset, {this.failure});

  final EntryAsset asset;

  /// Null when the asset was stored.
  final AssetFailure? failure;

  bool get isRefusal => failure == AssetFailure.refused;
}

/// Downloads the actual image bytes.
///
/// ## Where the bytes can come from, and where they cannot
///
/// Two paths exist, and between them they are the whole of what is reachable
/// without doing something this app does not do.
///
/// 1. **A direct request** carrying the Browser's cookies, its User-Agent and
///    the page as `Referer`. Those are not a disguise: they are the true facts
///    about the context this image was found in, and sending them is what
///    makes the request honest rather than what makes it sneak through.
/// 2. **The page itself** (`fetchAsBase64`), which runs inside the browsing
///    context the user is reading in. It has whatever session the user
///    established by browsing there, so it is the path that can succeed where
///    a separate client is refused.
///
/// **The hard limit, measured rather than assumed.** Path 2 is bounded by the
/// browser's own cross-origin rules: a host that serves images without
/// `Access-Control-Allow-Origin` allows an `<img>` to render them and allows
/// script to read nothing. On a real reading site the panels display at full
/// size in the WebView while `fetch` on the same address throws and a
/// `no-cors` fetch yields an opaque, zero-length body. Path 1 on that same
/// site is answered with a human-verification interstitial, because it is a
/// second client that has not been through the check the browser passed.
///
/// So a site that is **cross-origin, CORS-closed and challenge-protected** has
/// no path, and that is a boundary rather than a bug to fix. Getting past it
/// would mean either completing a human-verification check on the user's
/// behalf or defeating the browser's cross-origin rules — the first is
/// explicitly not something this app does, and the second is the browser
/// protecting every other site the user visits. Reading the rendered pixels
/// back out of the page is not an escape either: it re-encodes, and stored
/// bytes are byte-for-byte originals.
///
/// What the app does instead is **stop and say so**:
/// `StopReason.assetsRefusedBySource` carries one sentence about what the site
/// does. A refusal is never retried and never becomes a partial entry, because
/// the answer will not change and a fragment is not a copy of the reading.
///
/// **The restricted-site capture policy is deliberately not applied here**, and
/// this is a boundary worth stating rather than leaving implicit. That policy
/// answers "may this app capture this *page*"; an image `src` is not a page and
/// its delivery host is not a capture source. Ordinary sites serve their
/// pictures from CDNs owned by large commercial platforms, so testing an asset
/// host against the list marked perfectly permitted entries `partial` and put
/// "this image was not saved" placeholders through them — a false refusal on
/// content the user was entitled to keep, from a rule aimed at something else.
///
/// The page this entry *is* was established and validated upstream: `SaveEngine`
/// asks the policy about `browser.currentUrl` before it probes, about the landed
/// page URL before it scrolls, and about the manifest's `sourceUrl` before it
/// commits — all of which happen before any staging directory exists, let alone
/// a download. This class is not, and must not become, the authoritative
/// enforcement boundary: it verifies *bytes*, and it is the audio/video refusal
/// (an image-only allow-list, checked by magic number in [_verify]) that lives
/// here, independently and unchanged.
class AssetFetcher {
  AssetFetcher({required this.browser, required this.config, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              responseType: ResponseType.bytes,
              followRedirects: true,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (s) => s != null && s >= 200 && s < 400,
            ),
          );

  final BrowserController browser;
  final SaveConfig config;
  final Dio _dio;

  /// Download [entry] into [staging]. Always returns an explicit result — a
  /// failed asset is recorded as `failed` with a reason, never dropped, and
  /// [AssetDownload.failure] names *what kind* of failure it was so the engine
  /// can tell "this host said no" from "this one moment went wrong".
  ///
  /// Two paths, in this order:
  ///
  /// 1. **A direct request**, carrying the Browser's own cookies, its
  ///    User-Agent and the page as `Referer` — not to disguise anything, but
  ///    because those are the true facts about where this image was found.
  /// 2. **The page itself**, which is the same browsing context the user is
  ///    reading in and has already satisfied whatever the site asked of it.
  ///
  /// A refusal skips straight from 1 to 2: the retries exist for a moment that
  /// might go differently, and a refusal is not one of those.
  Future<AssetDownload> download({
    required EntryAsset entry,
    required StagingHandle staging,
    required String refererUrl,
    String? userAgent,
    String? cookieHeader,
  }) async {
    Object? lastError;
    AssetFailure kind = AssetFailure.transient;

    for (var attempt = 0; attempt <= config.downloadRetries; attempt++) {
      try {
        final bytes = await _fetchDirect(
          entry.sourceUrl,
          refererUrl: refererUrl,
          userAgent: userAgent,
          cookieHeader: cookieHeader,
        );
        final verified = _verify(bytes);
        if (verified != null) {
          return AssetDownload(await _write(entry, staging, verified, bytes));
        }
        // A page where a picture was asked for is the host declining, not a
        // corrupt file, and the difference decides whether asking again could
        // ever help.
        if (looksLikeMarkup(bytes)) {
          kind = AssetFailure.refused;
          lastError = 'the host served a web page instead of an image';
          break;
        }
        kind = AssetFailure.notAnImage;
        lastError =
            'not a recognised image format '
            '(${bytes.length} bytes, starts with ${_magicPreview(bytes)})';
      } catch (e) {
        lastError = e;
        kind = _failureKindOf(e);
        if (kind == AssetFailure.refused) break;
      }
      if (attempt < config.downloadRetries) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    // The page's own context. It holds the session the user established, so
    // this is the one path that can succeed where a separate client was
    // refused — and it is bounded by the browser's own cross-origin rules,
    // which the app does not attempt to get around.
    try {
      final inPage = await browser.fetchAsBase64(entry.sourceUrl);
      if (inPage != null && inPage.base64Data.isNotEmpty) {
        final bytes = base64Decode(inPage.base64Data);
        final verified = _verify(bytes);
        if (verified != null) {
          // The sniffed type wins even here: a server's Content-Type is a
          // claim, the magic bytes are a fact.
          return AssetDownload(await _write(entry, staging, verified, bytes));
        }
        if (looksLikeMarkup(bytes)) kind = AssetFailure.refused;
        lastError = 'in-page fetch returned unusable bytes';
      }
    } catch (e) {
      lastError = 'in-page fallback failed: $e';
    }

    return AssetDownload(
      entry.copyWith(status: AssetStatus.failed, error: _describe(lastError)),
      failure: kind,
    );
  }

  /// Which kind of failure an exception from the direct path represents.
  static AssetFailure _failureKindOf(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null && _refusalStatuses.contains(status)) {
        return AssetFailure.refused;
      }
    }
    return AssetFailure.transient;
  }

  /// Name the file from what the bytes ARE, then write it. URL extensions
  /// lie — a real CDN serves `image/jpeg` under `.webp` names — and the
  /// stored extension is the one thing a future export/share reads.
  Future<EntryAsset> _write(
    EntryAsset entry,
    StagingHandle staging,
    String mimeType,
    Uint8List bytes,
  ) async {
    final fileName = fileNameFor(entry.index, mimeType, entry.sourceUrl);
    final target = staging.assetFile(fileName);
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return _stored(entry, fileName, mimeType, bytes);
  }

  /// A stored asset's dimensions come from its own bytes, not from the DOM.
  ///
  /// The DOM values move to `domWidth`/`domHeight` as diagnostics: on real
  /// sites (observed panels run 800×13850..800×16000 with no HTML
  /// size attributes) the probe-time report is a snapshot of whatever the
  /// WebView had at that moment, and treating it as intrinsic is how panels
  /// end up laid out at the wrong aspect ratio.
  EntryAsset _stored(
    EntryAsset entry,
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) {
    final decoded = readImageDimensions(bytes);
    return entry.copyWith(
      status: AssetStatus.stored,
      relativePath: StagingHandle.assetRelativePath(fileName),
      mimeType: mimeType,
      byteSize: bytes.length,
      domWidth: entry.width,
      domHeight: entry.height,
      width: decoded?.width ?? entry.width,
      height: decoded?.height ?? entry.height,
      dimensionsVerified: decoded != null,
    );
  }

  Future<Uint8List> _fetchDirect(
    String url, {
    required String refererUrl,
    String? userAgent,
    String? cookieHeader,
  }) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'Referer': refererUrl,
          'User-Agent': ?userAgent,
          if (cookieHeader case final c? when c.isNotEmpty) 'Cookie': c,
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },
      ),
    );
    final data = response.data;
    if (data == null) throw const FormatException('empty response');
    return Uint8List.fromList(data);
  }

  /// Verify by magic number rather than by Content-Type: servers routinely
  /// return an HTML error page with a 200 and an image content type.
  String? _verify(Uint8List bytes) {
    if (bytes.length < config.minAssetBytes) return null;
    return detectImageMime(bytes);
  }

  static String _describe(Object? error) {
    if (error == null) return 'unknown download failure';
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) return 'HTTP $status';
      return error.type.name;
    }
    if (error is SocketException) return 'network unreachable';
    return error.toString();
  }

  /// `001.jpg` — zero-padded sequence (reading order, not a source filename),
  /// extension from the **verified MIME type**. The URL's extension is only a
  /// fallback for MIME types outside the table, and `.img` the last resort.
  static String fileNameFor(int index, String mimeType, String url) {
    final ext = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/avif' => 'avif',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'image/bmp' => 'bmp',
      _ => _urlExtension(url) ?? 'img',
    };
    return '${index.toString().padLeft(3, '0')}.$ext';
  }

  static String? _urlExtension(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot != -1 && dot < path.length - 1) {
      final raw = path.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(raw)) return raw;
    }
    return null;
  }
}
