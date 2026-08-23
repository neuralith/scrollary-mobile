/// A Source that answers from a script instead of a WebView.
///
/// The walk's own rules — which Source it belongs to, what counts toward the
/// number asked for, when it stops — are decided from what a page turned out
/// to say, so they are provable with no browser anywhere near them. That is
/// the whole reason [ForwardPageSource] exists as a seam, and this is the
/// other side of it: pages keyed by address, each naming the next.
library;

import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/recognition/walk.dart';

import 'recognition_harness.dart';

/// A number as a site would print it: `101`, `99.5`.
String plainNumber(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

class FakeForwardPages implements ForwardPageSource {
  FakeForwardPages(this._pages);

  /// A straight chain on one host: `/part-n` links to the next part in
  /// [parts], and the last one links to [tailNextUrl] — nowhere, by default.
  factory FakeForwardPages.chain({
    required String host,
    required List<num> parts,
    String? tailNextUrl,
  }) {
    final pages = <String, WalkedPage>{};
    for (var i = 0; i < parts.length; i++) {
      final number = parts[i];
      final url = partUrl(host, plainNumber(number));
      pages[normalizeUrl(url)] = WalkedPage(
        url: url,
        printedNumber: number.toDouble(),
        title: 'Part ${plainNumber(number)}',
        nextUrl: i + 1 < parts.length
            ? partUrl(host, plainNumber(parts[i + 1]))
            : tailNextUrl,
      );
    }
    return FakeForwardPages(pages);
  }

  final Map<String, WalkedPage> _pages;

  /// Every address this source was asked for, in order.
  final List<String> reads = [];

  /// The walk's visited set as it stood at each read — snapshotted, because
  /// the walk goes on mutating its own.
  final List<Set<String>> visitedAtRead = [];

  /// Replace one page of the script: a reading that fails, a next address
  /// that leaves the Source, a link back to where the walk has been.
  void put(WalkedPage page) => _pages[normalizeUrl(page.url)] = page;

  @override
  Future<WalkedPage> read({
    required String url,
    required SourceRow source,
    required Set<String> visited,
    required bool Function() shouldContinue,
  }) async {
    reads.add(url);
    visitedAtRead.add({...visited});
    return _pages[normalizeUrl(url)] ??
        WalkedPage.unreadable(url: url, stop: WalkStop.unreadable);
  }
}
