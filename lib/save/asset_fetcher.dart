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

/// Downloads the actual image bytes.
///
/// Primary path: Dio, carrying the WebView's cookies, User-Agent and a Referer
/// so hotlink checks pass. Fallback: pull the bytes through the page itself.
///
/// Known hard limit (documented, not worked around): on iOS there is no
/// resource interception, and an in-page `fetch` to a cross-origin CDN without
/// CORS headers is unreadable. A site that is both Referer-gated *and*
/// cross-origin *and* CORS-closed has no working path — such a site is
/// recorded as unsupported.
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
  /// failed asset is recorded as `failed` with a reason, never dropped.
  Future<EntryAsset> download({
    required EntryAsset entry,
    required StagingHandle staging,
    required String refererUrl,
    String? userAgent,
    String? cookieHeader,
  }) async {
    Object? lastError;

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
          return _write(entry, staging, verified, bytes);
        }
        lastError =
            'not a recognised image format '
            '(${bytes.length} bytes, starts with ${_magicPreview(bytes)})';
      } catch (e) {
        lastError = e;
      }
      if (attempt < config.downloadRetries) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    // Fallback: read it through the page, inheriting its credential context.
    try {
      final inPage = await browser.fetchAsBase64(entry.sourceUrl);
      if (inPage != null && inPage.base64Data.isNotEmpty) {
        final bytes = base64Decode(inPage.base64Data);
        final verified = _verify(bytes);
        if (verified != null) {
          return _write(
            entry,
            staging,
            // The sniffed type wins even here: a server's Content-Type is a
            // claim, the magic bytes are a fact.
            verified,
            bytes,
          );
        }
        lastError = 'in-page fetch returned unusable bytes';
      }
    } catch (e) {
      lastError = 'in-page fallback failed: $e';
    }

    return entry.copyWith(
      status: AssetStatus.failed,
      error: _describe(lastError),
    );
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
