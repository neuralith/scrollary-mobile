/// The restricted-site capture policy: the one place in the app that names a
/// hostname, and the only place that may.
///
/// **What this is.** A static, manually maintained list of commercial content
/// services — subscription video, hosted commercial video, music, audiobooks,
/// ebook stores and readers, licensed serialised-reading services, and official
/// publisher reading services — that this app will not save from. Browsing them
/// in the Browser is untouched: back, forward, reload, the address bar, sign-in
/// and ordinary navigation all work exactly as they do anywhere else. Only
/// *capture* is withheld.
///
/// **What this is not.** It is not a supported-site catalogue, not site-specific
/// behaviour, and not a claim about any individual page. Nothing here changes
/// how a page is detected, measured, classified or rendered. There is no
/// per-page judgement about whether something is paid, protected, licensed or
/// public — the app cannot know that, and does not try. A host is on the list or
/// it is not, and that is the entire decision.
///
/// **Why a list at all.** The alternative is to guess, and guessing wrong on a
/// commercial content service is the failure mode with the worst consequences
/// for the user and for the app (Apple 5.2.1 / 5.2.2 / 5.2.3, Play's IP policy).
/// Conservative overblocking is the deliberate trade: a marketing page or a
/// support article on one of these hosts is refused along with everything else,
/// and that is accepted.
///
/// **This is risk reduction, not a compliance guarantee.** The list is
/// incomplete by construction, it is not legal advice, and being absent from it
/// says nothing about whether saving a given page is permitted.
///
/// **One authority.** Nothing outside this file may hold these constants or
/// re-implement the matching. Every capture boundary imports [isCaptureRestricted]
/// (or [isRestrictedCaptureHost]) and asks; a hidden button is not enforcement.
///
/// **What counts as a capture source.** This policy is about the *page or
/// document being captured*, and about nothing else:
///
/// | Kind of URL | Policy applies |
/// |---|---|
/// | The Browser's current page | **yes** |
/// | A direct-start, enqueued, resumed or retried task's source URL | **yes** |
/// | A collection's update-check source, and every page that walk opens | **yes** |
/// | A discovered entry's page URL | **yes** |
/// | Top-level navigation and redirects during a run, and the landed URL | **yes** |
/// | The manifest's `sourceUrl`, immediately before commit | **yes** |
/// | An image `src`, a responsive candidate, a CSS background, a document's inline image | **no** |
/// | The CDN or third-party host an asset is delivered from, including an asset request's own redirects | **no** |
///
/// The second half is not an oversight. An asset is a *part of* a page that has
/// already been judged, not a page in its own right, and ordinary sites serve
/// their pictures from CDNs owned by large commercial platforms. Testing an
/// asset host against these lists refuses images on entries the user is
/// perfectly entitled to keep, and marks those entries `partial` for a reason
/// that has nothing to do with them. Capture is decided once, about the page,
/// before a single byte is requested.
///
/// This does not create a way in. An asset URL cannot become an entry's source:
/// `AssetFetcher` accepts image bytes only (verified by magic number), writes
/// them into an already-open staging directory, and returns an `EntryAsset` —
/// there is no path from it to a page, a document or a row. The audio/video
/// refusal is a separate rule that lives there and is untouched by any of this.
library;

import 'stop_conditions.dart';

/// Restricted **domains**: the apex and every subdomain beneath it.
///
/// `amazon.com` matches `amazon.com`, `www.amazon.com`, `read.amazon.com`,
/// `music.amazon.com` and anything else under it. It does not match
/// `fakeamazon.com` or `amazon.com.example.org` — see [isRestrictedCaptureHost]
/// for the exact rule.
const restrictedCaptureDomains = <String>{
  // --- major video and streaming platforms ---------------------------------
  'youtube.com',
  'youtu.be',
  'youtube-nocookie.com',
  'googlevideo.com',
  'netflix.com',
  'primevideo.com',
  'disneyplus.com',
  'hulu.com',
  'max.com',
  'hbomax.com',
  'paramountplus.com',
  'peacocktv.com',
  'discoveryplus.com',
  'crunchyroll.com',
  'funimation.com',
  'mubi.com',
  'tubitv.com',
  'pluto.tv',
  'vimeo.com',
  'dailymotion.com',
  'twitch.tv',
  'kick.com',
  'plex.tv',
  'criterionchannel.com',
  'britbox.com',
  'starz.com',
  'showtime.com',
  'roku.com',

  // --- Turkish video and streaming platforms -------------------------------
  'blutv.com',
  'exxen.com',
  'gain.tv',
  'tabii.com',
  'todtv.com.tr',
  'beinsports.com.tr',
  'puhutv.com',
  'netd.com',
  'trtizle.com',

  // --- music, podcast and audiobook platforms ------------------------------
  'spotify.com',
  'soundcloud.com',
  'tidal.com',
  'deezer.com',
  'pandora.com',
  'audible.com',
  // Beyond the supplied baseline: the same audiobook service under its other
  // country domains. Omitting them would restrict one storefront of one service
  // and leave the rest, which is not a defensible line to draw.
  'audible.co.uk',
  'audible.de',
  'audible.fr',
  'audible.it',
  'audible.es',
  'audible.ca',
  'audible.com.au',
  'audible.in',
  'audible.co.jp',
  'storytel.com',
  'audiobooks.com',
  'libro.fm',
  'fizy.com',
  'muud.com.tr',

  // --- licensed serialised-reading platforms -------------------------------
  'webtoons.com',
  'tapas.io',
  'tappytoon.com',
  'lezhinus.com',
  'lezhin.com',
  'manta.net',
  'pocketcomics.com',
  'viz.com',
  'vizmanga.com',
  'shonenjump.com',
  'azuki.co',
  'comikey.com',
  'inkr.com',
  'mangamo.com',
  'bookwalker.jp',
  'piccoma.com',
  'globalcomix.com',
  'izneo.com',
  'dcuniverseinfinite.com',
  'marvel.com',
  'comixology.com',

  // --- ebook, novel and controlled-reading platforms -----------------------
  'webnovel.com',
  'wattpad.com',
  'radishfiction.com',
  'scribd.com',
  'everand.com',
  'kobo.com',
  'rakutenkobo.com',
  'barnesandnoble.com',

  // --- Amazon retail domains -----------------------------------------------
  //
  // Blocked completely and deliberately. Reading, video, music and audiobook
  // services are served from paths and subdomains of the retail domains, and no
  // static rule can separate a product page from a reader without inspecting the
  // page — which this policy does not do. Ordinary browsing is unaffected.
  'amazon.com',
  'amazon.co.uk',
  'amazon.de',
  'amazon.fr',
  'amazon.it',
  'amazon.es',
  'amazon.co.jp',
  'amazon.ca',
  'amazon.com.au',
  'amazon.in',
  'amazon.com.br',
  'amazon.com.mx',
  'amazon.com.tr',
  'amazon.ae',
  'amazon.sa',
  'amazon.sg',
  'amazon.nl',
  'amazon.pl',
  'amazon.se',
};

/// Restricted **exact hosts**: this host and no other.
///
/// For commercial content services that live beneath a parent domain with a
/// great deal of unrelated content under it. `tv.apple.com` is restricted;
/// `apple.com`, `developer.apple.com` and `support.apple.com` are not. A
/// subdomain of a restricted exact host is *not* covered — if one ever needs to
/// be, it gets its own entry or the parent moves to [restrictedCaptureDomains].
const restrictedCaptureHosts = <String>{
  // --- Apple content services ----------------------------------------------
  // Deliberately not the whole of the parent domain.
  'tv.apple.com',
  'music.apple.com',
  'books.apple.com',
  'podcasts.apple.com',
  // Beyond the supplied baseline: the legacy media-store host, the same family
  // of services as the four above.
  'itunes.apple.com',

  // --- Google content services ---------------------------------------------
  // Deliberately not the whole of the parent domain.
  'play.google.com',
  'books.google.com',
  // Already covered by the `youtube.com` domain rule above; listed here so the
  // category reads completely. The domain rule is what decides at runtime, so
  // this entry changes no behaviour.
  'music.youtube.com',

  // --- official publisher reading services ---------------------------------
  // Their parent domains carry corporate, editorial and unrelated content, so
  // only the reading service itself is named.
  'mangaplus.shueisha.co.jp',
  'kmanga.kodansha.com',
  'comic.naver.com',
  'series.naver.com',
  'page.kakao.com',
  'webtoon.kakao.com',
};

/// The one sentence the user sees. Neutral and factual: it states what the app
/// does, never what the user was trying to do.
const kCaptureRestrictedMessage = 'Saving isn’t available on this site.';

/// The normalised host of [url], or null when there is no web host to judge.
///
/// Normalisation is exactly: parse as a URI, require an `http`/`https` scheme,
/// lowercase, strip trailing dots. Ports never appear in `Uri.host`, so
/// `example.com:8443` and `example.com` normalise identically. A URL that is
/// unparseable, scheme-less, hostless or on another scheme returns null.
String? captureHostOf(String? url) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return _normaliseHost(uri.host);
}

String? _normaliseHost(String host) {
  var normalised = host.trim().toLowerCase();
  while (normalised.endsWith('.')) {
    normalised = normalised.substring(0, normalised.length - 1);
  }
  return normalised.isEmpty ? null : normalised;
}

/// Is capture restricted for this already-parsed [host]?
///
/// A domain rule matches only when `host == domain` or `host` ends with
/// `'.' + domain`. That second test is what stops `notyoutube.com` and
/// `youtube.com.example.org` from matching `youtube.com`: the first has no dot
/// boundary before the domain, and the second has the domain in the *middle* of
/// its name rather than as its suffix. There is no substring matching anywhere
/// in this file, and a restricted name appearing inside a path or a query
/// parameter is never seen at all — only [Uri.host] is examined.
bool isRestrictedCaptureHost(String? host) {
  final normalised = host == null ? null : _normaliseHost(host);
  if (normalised == null) return false;
  if (restrictedCaptureHosts.contains(normalised)) return true;
  for (final domain in restrictedCaptureDomains) {
    if (normalised == domain || normalised.endsWith('.$domain')) return true;
  }
  return false;
}

/// Is capture restricted for [url]?
///
/// Hostless, malformed and non-web URLs answer **false**: they are not on the
/// list, and every capture path already refuses them for its own reasons. This
/// function's job is the host policy and nothing else.
bool isCaptureRestricted(String? url) =>
    isRestrictedCaptureHost(captureHostOf(url));

/// The same question in the shape the save run's other gates take, so a
/// continuation or a redirect check reads like every stopping condition beside
/// it.
///
/// [StopReason.captureRestrictedForSite] lives in `stop_conditions.dart` with
/// the rest of the outcome vocabulary; the *matching* stays here, so that file
/// keeps its property of containing no hostname.
GateCheck checkCaptureSite(String? url) {
  final host = captureHostOf(url);
  if (!isRestrictedCaptureHost(host)) return const GateCheck.clear();
  return GateCheck(
    reason: StopReason.captureRestrictedForSite,
    evidence: 'saving is not available on $host',
  );
}
