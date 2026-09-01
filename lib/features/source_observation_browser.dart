import '../browser/browser_controller.dart';
import '../browser/page_data.dart';
import '../core/url_utils.dart';
import '../data/schema.dart';
import '../recognition/check.dart';
import '../recognition/discovery.dart';
import '../recognition/relocation.dart' show landedListingPath;
import '../save/capture_policy.dart';

/// Reads one page of one Source's listing through the real Browser.
///
/// The one thing in the check path that touches a WebView. It mirrors the
/// protocol the V1 checker validated on hardware: the navigation is announced
/// with [BrowserController.allowNextNavigation], the load is awaited, and the
/// judgement is taken from the settled page's probe — never from the address
/// the reading aimed at. The landed-URL policy boundary is owned here, because
/// only the thing that navigates can know where it ended up.
///
/// The claims this implementation makes are deliberately modest. It reads one
/// page per observation and reports no continuation ([SourceObservation]'s
/// `nextPageUrl` stays null), so a check's ceiling of pages is honoured by
/// construction. Ordering confidence is claimed only when the page's own
/// printed numbers run one way without contradiction — anything less and the
/// reading refuses the claim rather than guessing, which discovery then treats
/// as "coexist, never retract".
class BrowserSourceObservationSource implements SourceObservationSource {
  BrowserSourceObservationSource(this._browser);

  final BrowserController _browser;

  @override
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  }) async {
    final target = pageUrl ?? 'https://${source.host}${source.pathKey}';
    if (!shouldContinue()) {
      return SourceObservation.unreadable(
        url: target,
        stop: SourceCheckStop.cancelledByUser,
      );
    }

    _browser.allowNextNavigation(target);
    await _browser.loadAndWait(target);
    final landed = _browser.currentUrl.isEmpty ? target : _browser.currentUrl;

    // The boundary only the navigator can own: where the reading LANDED.
    if (isCaptureRestricted(landed)) {
      return SourceObservation.unreadable(
        url: landed,
        stop: SourceCheckStop.captureRestrictedForSite,
      );
    }
    if (!shouldContinue()) {
      return SourceObservation.unreadable(
        url: landed,
        stop: SourceCheckStop.cancelledByUser,
      );
    }

    final probe = await _browser.probe(withLinks: true);
    if (probe.readyState != 'complete' && probe.links.isEmpty) {
      return SourceObservation.unreadable(
        url: landed,
        stop: SourceCheckStop.listingUnreadable,
      );
    }

    // Where this Source's listing actually turned out to live. A provider that
    // rewrites part of its URL structure redirects the address we asked for to
    // the one it now uses; filtering that page's links against the key we
    // stored would reject every one of them and report the site's own
    // successful answer as "not this Source's listing". Asked only of the
    // listing **root** — a later page of a listing is inside it already, and
    // its address is not the Source's path.
    final listingPath = pageUrl == null
        ? landedListingPath(
            sourceHost: source.host,
            sourcePathKey: source.pathKey,
            landedUrl: landed,
          )
        : source.pathKey;

    final listings = _listingsOf(probe, source, landed, listingPath);
    return SourceObservation.read(
      url: landed,
      listings: listings,
      listRecognised: listings.isNotEmpty,
      orderingConfident: _orderingConfident(listings),
      newestFirst: _newestFirst(listings),
      // Only a reading that worked as a listing says anything about where the
      // listing is. An empty one is a failed reading, not a relocation.
      landedPathKey: listings.isEmpty ? null : listingPath,
    );
  }

  /// Addresses of this Source the page linked to, in the page's own order.
  ///
  /// [listingPath] is the path the reading is filtering against — the stored
  /// `path_key` ordinarily, and the one the site redirected the reading to
  /// where it moved the listing. The host is **never** relaxed: a link that
  /// leaves the host is not this Source's, whatever the path says.
  List<ObservedEntryListing> _listingsOf(
    PageProbe probe,
    SourceRow source,
    String landedUrl,
    String listingPath,
  ) {
    final landedKey = normalizeUrl(landedUrl);
    final prefix = listingPath.toLowerCase();
    final seen = <String>{};
    final listings = <ObservedEntryListing>[];
    for (final link in probe.links) {
      if (link.inNav) continue;
      final uri = Uri.tryParse(link.href);
      if (uri == null || !uri.hasScheme || uri.host != source.host) continue;
      if (!uri.path.toLowerCase().startsWith(prefix)) {
        continue;
      }
      final listing = ObservedEntryListing.read(
        url: link.href,
        label: _labelOf(link),
      );
      // The listing page itself, and repeats of one address, say nothing new.
      if (listing.urlKey == landedKey) continue;
      if (!seen.add(listing.urlKey)) continue;
      listings.add(listing);
    }
    return listings;
  }

  String _labelOf(PageLink link) {
    for (final candidate in [link.text, link.ariaLabel, link.title]) {
      final t = candidate.trim();
      if (t.isNotEmpty) return t;
    }
    return link.imgAlt.trim();
  }

  /// True only when the printed numbers that exist run strictly one way.
  bool _orderingConfident(List<ObservedEntryListing> listings) {
    final numbers = [
      for (final l in listings)
        if (l.printedNumber != null) l.printedNumber!,
    ];
    if (numbers.length < 2) return false;
    var ascending = true;
    var descending = true;
    for (var i = 1; i < numbers.length; i++) {
      if (numbers[i] <= numbers[i - 1]) ascending = false;
      if (numbers[i] >= numbers[i - 1]) descending = false;
    }
    return ascending || descending;
  }

  bool _newestFirst(List<ObservedEntryListing> listings) {
    final numbers = [
      for (final l in listings)
        if (l.printedNumber != null) l.printedNumber!,
    ];
    if (numbers.length < 2) return false;
    return numbers.first > numbers.last;
  }
}
