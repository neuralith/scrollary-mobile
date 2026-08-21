import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/next_page.dart';
import 'package:web_reader/core/url_utils.dart';

PageProbe probe({
  String url = 'https://x.example/entry/1',
  String? headNext,
  List<PageLink> links = const [],
}) =>
    PageProbe(url: url, title: 'Entry 1', headNextHref: headNext, links: links);

void main() {
  group('strategy ordering', () {
    test('link[rel=next] outranks a labelled control', () {
      final result = resolveNextPage(
        probe(
          headNext: 'https://x.example/entry/2',
          links: const [
            PageLink(href: 'https://x.example/entry/99', text: 'Next entry'),
          ],
        ),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
      );

      expect(result.chosen!.href, 'https://x.example/entry/2');
      expect(result.chosen!.strategy, NextStrategy.headRelNext);
    });

    test('a[rel=next] outranks link text', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(href: 'https://x.example/entry/50', text: 'Continue'),
            PageLink(href: 'https://x.example/entry/2', rel: 'next', text: '→'),
          ],
        ),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
      );

      expect(result.chosen!.strategy, NextStrategy.anchorRelNext);
      expect(result.chosen!.href, 'https://x.example/entry/2');
    });

    test('a site override outranks everything', () {
      final result = resolveNextPage(
        probe(headNext: 'https://x.example/wrong'),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
        hintHref: 'https://x.example/right',
      );
      expect(result.chosen!.strategy, NextStrategy.savedHint);
      expect(result.chosen!.href, 'https://x.example/right');
    });
  });

  group('text matching', () {
    test('matches common next labels across languages', () {
      for (final label in [
        'Next',
        'Next Entry',
        'Next entry',
        'Sonraki part',
        'Siguiente',
        '다음화',
      ]) {
        final result = resolveNextPage(
          probe(
            links: [PageLink(href: 'https://x.example/entry/2', text: label)],
          ),
          currentUrl: 'https://x.example/entry/1',
          visitedNormalized: {},
        );
        expect(result.hasNext, isTrue, reason: label);
      }
    });

    test('matches aria-label and title when the text is an icon', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(
              href: 'https://x.example/entry/2',
              text: '›',
              ariaLabel: 'Next entry',
            ),
          ],
        ),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
      );
      expect(result.hasNext, isTrue);
      expect(result.chosen!.evidence, contains('aria-label'));
    });

    test('ignores deny-listed near-misses', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(
              href: 'https://x.example/collection/2',
              text: 'Next collection',
            ),
            PageLink(
              href: 'https://x.example/comments?p=2',
              text: 'Next comments',
            ),
          ],
        ),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
      );
      expect(result.hasNext, isFalse);
    });

    test('ignores a long paragraph that merely contains the word', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(
              href: 'https://x.example/blog',
              text: 'Read what happens next in our weekly newsletter roundup',
            ),
          ],
        ),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
      );
      expect(result.hasNext, isFalse);
    });
  });

  group('validation inside the chain', () {
    test('skips a visited candidate and takes the next viable one', () {
      final result = resolveNextPage(
        probe(
          headNext: 'https://x.example/entry/1', // already visited
          links: const [
            PageLink(href: 'https://x.example/entry/2', text: 'Next'),
          ],
        ),
        currentUrl: 'https://x.example/entry/9',
        visitedNormalized: {'https://x.example/entry/1'},
      );

      expect(result.chosen!.href, 'https://x.example/entry/2');
    });

    test('reports no next when every candidate is rejected', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(href: 'https://other.example/c/2', text: 'Next'),
          ],
        ),
        currentUrl: 'https://x.example/entry/1',
        visitedNormalized: {},
      );

      expect(result.hasNext, isFalse);
      expect(result.rejection, NextUrlRejection.differentHost);
      expect(result.considered, hasLength(1));
    });

    test('no candidates at all is end-of-chain, not an error', () {
      final result = resolveNextPage(
        probe(
          links: const [PageLink(href: 'https://x.example/', text: 'Home')],
        ),
        currentUrl: 'https://x.example/entry/3',
        visitedNormalized: {},
      );
      expect(result.hasNext, isFalse);
      expect(result.considered, isEmpty);
      expect(result.rejection, isNull);
    });

    test(
      'the chosen href is returned normalised, ready for the visited set',
      () {
        final result = resolveNextPage(
          probe(
            links: const [
              PageLink(
                href: 'https://x.example/entry/2?utm_source=rss#top',
                rel: 'next',
              ),
            ],
          ),
          currentUrl: 'https://x.example/entry/1',
          visitedNormalized: {},
        );
        expect(result.chosen!.href, 'https://x.example/entry/2');
      },
    );
  });
}
