import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/next_page.dart';

/// Controlled multilingual fixtures. Three languages, not an attempt at
/// coverage — the point is that detection must not *depend* on the hint list.
PageProbe probe({
  String url = 'https://x.example/guide/foo/10',
  String? headNext,
  List<PageLink> links = const [],
  List<PageLink> controls = const [],
}) => PageProbe(
  url: url,
  title: 'Entry 10',
  headNextHref: headNext,
  links: links,
  controls: controls,
);

void main() {
  const current = 'https://x.example/guide/foo/10';

  group('automatic detection succeeds without user input', () {
    test('link[rel=next] proceeds on its own', () {
      final result = resolveNextPage(
        probe(headNext: 'https://x.example/guide/foo/11'),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.proceed);
      expect(result.chosen!.href, 'https://x.example/guide/foo/11');
      expect(result.chosen!.confidence, NextConfidence.high);
      expect(result.needsUserSelection, isFalse);
    });

    test('an uncontested English label proceeds', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(
              href: 'https://x.example/guide/foo/11',
              text: 'Next Entry',
            ),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );
      expect(result.decision, NextDecision.proceed);
    });

    test('an uncontested Turkish label proceeds', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(
              href: 'https://x.example/guide/foo/11',
              text: 'Sonraki part',
            ),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );
      expect(result.decision, NextDecision.proceed);
      expect(result.chosen!.evidence, contains('sonraki'));
    });

    test('an uncontested German label proceeds', () {
      for (final label in ['Weiter', 'Nächstes Kapitel']) {
        final result = resolveNextPage(
          probe(
            links: [
              PageLink(href: 'https://x.example/guide/foo/11', text: label),
            ],
          ),
          currentUrl: current,
          visitedNormalized: {},
        );
        expect(result.decision, NextDecision.proceed, reason: label);
      }
    });

    test('an unlisted language still works via rel — no dictionary needed', () {
      // Nothing here is in the hint list; `rel` alone carries it.
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(
              href: 'https://x.example/guide/foo/11',
              rel: 'next',
              text: 'Volgende',
            ),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );
      expect(result.decision, NextDecision.proceed);
      expect(result.chosen!.strategy, NextStrategy.anchorRelNext);
    });

    test('corroboration lifts a medium signal to high', () {
      // A label AND a same-collection entry+1 link, both pointing at /11.
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(href: 'https://x.example/guide/foo/11', text: 'Next'),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );
      expect(result.chosen!.confidence, NextConfidence.high);
      expect(result.decision, NextDecision.proceed);
    });
  });

  group('low confidence asks the user', () {
    test('two labelled controls pointing at different pages', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(href: 'https://x.example/guide/foo/11', text: 'Next'),
            PageLink(href: 'https://x.example/guide/foo/99', text: 'Continue'),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.askUser);
      expect(result.needsUserSelection, isTrue);
      expect(result.reason, contains('disagree'));
      expect(result.considered.length, greaterThanOrEqualTo(2));
    });

    test('only an entry-progression link is not enough on its own', () {
      final result = resolveNextPage(
        probe(
          links: const [
            // No label, no rel — just a link that happens to be entry 11.
            PageLink(href: 'https://x.example/guide/foo/11'),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.askUser);
      expect(result.chosen!.strategy, NextStrategy.numberProgression);
      expect(result.chosen!.confidence, NextConfidence.low);
    });

    test('nothing plausible at all is end-of-chain, not a prompt', () {
      final result = resolveNextPage(
        probe(
          links: const [PageLink(href: 'https://x.example/', text: 'Home')],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );
      expect(result.decision, NextDecision.endOfChain);
      expect(result.needsUserSelection, isFalse);
    });

    test('allowUserAssist:false falls back to best effort', () {
      final result = resolveNextPage(
        probe(links: const [PageLink(href: 'https://x.example/guide/foo/11')]),
        currentUrl: current,
        visitedNormalized: {},
        allowUserAssist: false,
      );
      expect(result.decision, NextDecision.proceed);
    });
  });

  group('saved rules', () {
    test('a rule href outranks everything and proceeds', () {
      final result = resolveNextPage(
        probe(
          headNext: 'https://x.example/guide/foo/999',
          links: const [
            PageLink(href: 'https://x.example/guide/foo/888', text: 'Next'),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
        hintHref: 'https://x.example/guide/foo/11',
      );

      expect(result.decision, NextDecision.proceed);
      expect(result.chosen!.strategy, NextStrategy.savedHint);
      expect(result.chosen!.href, 'https://x.example/guide/foo/11');
    });

    test('a rule pointing off-host is rejected, not followed', () {
      final result = resolveNextPage(
        probe(),
        currentUrl: current,
        visitedNormalized: {},
        hintHref: 'https://evil.example/guide/foo/11',
      );
      expect(result.decision, NextDecision.endOfChain);
    });

    test('a rule pointing at an already-visited page is rejected', () {
      final result = resolveNextPage(
        probe(),
        currentUrl: current,
        visitedNormalized: {'https://x.example/guide/foo/9'},
        hintHref: 'https://x.example/guide/foo/9',
      );
      expect(result.decision, NextDecision.endOfChain);
    });
  });

  group('starting from the middle of a collection', () {
    test('entry 883 finds 884 without needing entry 1', () {
      const mid = 'https://a.example/guide/foo/883-part-oku';
      final result = resolveNextPage(
        probe(
          url: mid,
          links: const [
            PageLink(
              href: 'https://a.example/guide/foo/884-part-oku',
              text: 'Sonraki part',
            ),
          ],
        ),
        currentUrl: mid,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.proceed);
      expect(result.chosen!.href, contains('884-part-oku'));
    });

    test('entryNumberIn reads the number from varied layouts', () {
      expect(entryNumberIn('https://x.example/guide/foo/883-part-oku'), 883);
      expect(entryNumberIn('https://x.example/comics/bar/entry/101'), 101);
      expect(entryNumberIn('https://x.example/collection/baz'), isNull);
    });

    test('a progression link from a different collection is not offered', () {
      final result = resolveNextPage(
        probe(
          links: const [PageLink(href: 'https://x.example/guide/OTHER/11')],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );
      expect(result.decision, NextDecision.endOfChain);
    });
  });

  group('deny hints', () {
    test('"next collection" and its translations are not entry navigation', () {
      for (final label in [
        'Next collection',
        'Sonraki seri',
        'Nächste Serie',
      ]) {
        final result = resolveNextPage(
          probe(
            links: [
              PageLink(href: 'https://x.example/guide/other', text: label),
            ],
          ),
          currentUrl: current,
          visitedNormalized: {},
        );
        expect(result.decision, NextDecision.endOfChain, reason: label);
      }
    });
  });

  group('short hints must not match inside longer words', () {
    // Regression from a real page: the Turkish hint "ileri" matched inside
    // "anime onerileri" (recommendations), offering three unrelated sites as
    // next-entry candidates. Only same-host validation caught them.
    test('"ileri" does not match inside "anime onerileri"', () {
      const link = PageLink(
        href: 'https://x.example/guide/foo/11',
        text: 'anime onerileri',
      );
      expect(matchNextText(link), isNull);
    });

    test('"ileri" still matches as its own word', () {
      expect(
        matchNextText(
          const PageLink(href: 'https://x.example/guide/foo/11', text: 'Ileri'),
        ),
        isNotNull,
      );
      expect(
        matchNextText(
          const PageLink(
            href: 'https://x.example/guide/foo/11',
            text: 'ileri >',
          ),
        ),
        isNotNull,
      );
    });

    test('short English hints are bounded too', () {
      expect(
        matchNextText(
          const PageLink(
            href: 'https://x.example/a',
            text: 'nextdoor neighbours',
          ),
        ),
        isNull,
      );
      expect(
        matchNextText(
          const PageLink(href: 'https://x.example/a', text: 'Next'),
        ),
        isNotNull,
      );
    });

    test('distinctive multi-word hints still match as substrings', () {
      expect(
        matchNextText(
          const PageLink(
            href: 'https://x.example/a',
            text: 'Go to next entry now',
          ),
        ),
        isNotNull,
      );
    });
  });

  // ─── the sequence continues, but nothing on it is followable ───────────
  //
  // A reader that routes itself in script publishes no `href` for its Next.
  // To a resolver that can only read links that is indistinguishable from the
  // end of the collection, and the two are opposite answers: one is finished,
  // the other is a page plainly offering a next entry the app cannot follow by
  // reading it. Getting this wrong stops a run at entry 41 of 43 and reports it
  // as everything the site publishes.

  group('a next control that carries no address', () {
    const nextButton = PageLink(
      href: '',
      ariaLabel: 'Next entry',
      className: 'reader-nav__btn',
    );

    test('a page with no links but a next-labelled control asks rather than '
        'declaring the end', () {
      final result = resolveNextPage(
        probe(controls: const [nextButton]),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.askUser);
      expect(result.hasNext, isFalse);
      expect(
        result.reason,
        contains('not a link'),
        reason:
            'the prompt has to say what it could not do, or "point at the '
            'control" is a request with no explanation attached',
      );
    });

    test('a page with neither a link nor such a control is the end', () {
      final result = resolveNextPage(
        probe(
          links: const [
            PageLink(href: 'https://x.example/guide/foo', text: 'All entries'),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(
        result.decision,
        NextDecision.endOfChain,
        reason:
            'prompting at the genuine end of a finished collection is a '
            'worse failure than the one this discriminator fixes',
      );
    });

    test('a control that is not next-ish is not a reason to ask', () {
      final result = resolveNextPage(
        probe(
          controls: const [
            PageLink(href: '', ariaLabel: 'Share'),
            PageLink(href: '', text: 'Report a problem'),
          ],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.endOfChain);
    });

    test('a followable link is still followed, control or no control', () {
      final result = resolveNextPage(
        probe(
          headNext: 'https://x.example/guide/foo/11',
          controls: const [nextButton],
        ),
        currentUrl: current,
        visitedNormalized: {},
      );

      expect(result.decision, NextDecision.proceed);
      expect(result.chosen!.href, 'https://x.example/guide/foo/11');
    });

    test('a run that may not ask is not made to ask by one', () {
      final result = resolveNextPage(
        probe(controls: const [nextButton]),
        currentUrl: current,
        visitedNormalized: {},
        allowUserAssist: false,
      );

      expect(result.decision, NextDecision.endOfChain);
    });
  });

  group('following an address, or pressing a control', () {
    test('a control with no address is pressed', () {
      expect(nextControlMustBePressed(href: '', currentUrl: current), isTrue);
    });

    test('an anchor going nowhere is pressed, not followed', () {
      expect(
        nextControlMustBePressed(href: '#', currentUrl: current),
        isTrue,
        reason:
            'a client-routed reader writes href="#" and handles the click '
            'itself; loading it would reload the page it is on',
      );
      expect(
        nextControlMustBePressed(
          href: 'javascript:void(0)',
          currentUrl: current,
        ),
        isTrue,
      );
    });

    test('a real address is followed', () {
      expect(
        nextControlMustBePressed(
          href: 'https://x.example/guide/foo/11',
          currentUrl: current,
        ),
        isFalse,
      );
      expect(
        nextControlMustBePressed(href: '/guide/foo/11', currentUrl: current),
        isFalse,
      );
    });

    test('an address that is wrong for another reason is still an address', () {
      expect(
        nextControlMustBePressed(
          href: 'https://elsewhere.example/guide/foo/11',
          currentUrl: current,
        ),
        isFalse,
        reason:
            'leaving the site is a refusal, not a reason to start pressing '
            'the control instead',
      );
    });
  });
}
