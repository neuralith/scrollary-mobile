import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/page_hint_repository.dart';
import 'package:web_reader/save/page_hint.dart';
import 'package:web_reader/storage/database.dart';

void main() {
  late AppDatabase db;
  late PageHintRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PageHintRepository(db);
  });
  tearDown(() => db.close());

  /// What the JS picker reports for a Turkish "Sonraki part" control.
  const turkishNextButton = SelectedElement(
    mode: 'link',
    tag: 'a',
    text: 'Sonraki part',
    href: 'https://a.example/guide/efsanevi-buyu/884-part-oku',
    rel: 'next',
    classes: 'nav-next entry-nav',
    selector: 'a.nav-next',
    containerSelector: 'nav',
  );

  const germanNextButton = SelectedElement(
    mode: 'link',
    tag: 'a',
    text: 'Nächstes Kapitel',
    href: 'https://lesen.example/guide/held/kapitel-43',
    classes: 'weiter-link',
    selector: 'a.weiter-link',
  );

  const readerContainer = SelectedElement(
    mode: 'reader',
    tag: 'div',
    classes: 'reading-content',
    selector: 'div.reading-content',
    imageCount: 12,
    minImageEdge: 800,
    imageSelector: 'img',
  );

  group('saving and reusing a next-button rule', () {
    test(
      'a saved rule is found again for the next entry of that collection',
      () async {
        const source = 'https://a.example/guide/efsanevi-buyu/883-part-oku';
        final created = await repo.createNextLinkHint(
          element: turkishNextButton,
          sourceUrl: source,
        );

        expect(created.kind, HintKind.nextLink);
        expect(created.scope, HintScope.collection);
        expect(created.hintPath, '/guide/efsanevi-buyu');
        expect(created.locator.rel, 'next');
        expect(created.locator.linkText, 'Sonraki part');
        expect(created.locator.cssSelector, 'a.nav-next');
        expect(created.locator.hrefPattern, isNotNull);
        expect(
          created.locator.isWeak,
          isFalse,
          reason: 'rel + selector + text + pattern is not a one-signal rule',
        );

        // The very next entry of the same collection reuses it.
        final found = await repo.findFor(
          'https://a.example/guide/efsanevi-buyu/884-part-oku',
          HintKind.nextLink,
        );
        expect(found, isNotNull);
        expect(found!.id, created.id);
      },
    );

    test('the stored href pattern generalises across entry numbers', () async {
      final rule = await repo.createNextLinkHint(
        element: turkishNextButton,
        sourceUrl: 'https://a.example/guide/efsanevi-buyu/883-part-oku',
      );
      final pattern = RegExp(rule.locator.hrefPattern!);

      expect(pattern.hasMatch('/guide/efsanevi-buyu/885-part-oku'), isTrue);
      expect(
        pattern.hasMatch('/guide/another-collection/885-part-oku'),
        isFalse,
      );
    });

    test('a rule survives a round-trip through the database intact', () async {
      final created = await repo.createNextLinkHint(
        element: germanNextButton,
        sourceUrl: 'https://lesen.example/guide/held/kapitel-42',
      );

      final reloaded = (await repo.all()).single;
      expect(reloaded.id, created.id);
      expect(reloaded.host, 'lesen.example');
      expect(reloaded.hintPath, '/guide/held');
      expect(reloaded.locator.linkText, 'Nächstes Kapitel');
      expect(reloaded.locator.cssSelector, 'a.weiter-link');
    });
  });

  group('rules do not leak between collection', () {
    test(
      'a collection rule is not offered for an unrelated collection',
      () async {
        await repo.createNextLinkHint(
          element: turkishNextButton,
          sourceUrl: 'https://a.example/guide/efsanevi-buyu/883-part-oku',
        );

        final other = await repo.findFor(
          'https://a.example/guide/completely-different/5-part-oku',
          HintKind.nextLink,
        );
        expect(
          other,
          isNull,
          reason: 'a rule learned on one collection must not drive another',
        );
      },
    );

    test(
      'a host-scoped rule is offered across collection, by explicit choice',
      () async {
        await repo.createNextLinkHint(
          element: turkishNextButton,
          sourceUrl: 'https://a.example/guide/efsanevi-buyu/883-part-oku',
          scope: HintScope.host,
        );

        final other = await repo.findFor(
          'https://a.example/guide/completely-different/5-part-oku',
          HintKind.nextLink,
        );
        expect(other, isNotNull);
        expect(other!.scope, HintScope.host);
      },
    );

    test('a rule never applies to a different host', () async {
      await repo.createNextLinkHint(
        element: turkishNextButton,
        sourceUrl: 'https://a.example/guide/foo/1',
        scope: HintScope.host,
      );
      expect(
        await repo.findFor('https://b.example/guide/foo/1', HintKind.nextLink),
        isNull,
      );
    });

    test('a next-link rule is not used as a reader-area rule', () async {
      await repo.createNextLinkHint(
        element: turkishNextButton,
        sourceUrl: 'https://a.example/guide/foo/1',
        scope: HintScope.host,
      );
      expect(
        await repo.findFor(
          'https://a.example/guide/foo/1',
          HintKind.readerArea,
        ),
        isNull,
      );
    });
  });

  group('reader-area rules', () {
    test('derives a container, image selector and size floor', () async {
      final rule = await repo.createReaderAreaHint(
        element: readerContainer,
        sourceUrl: 'https://b.example/comics/genius/entry/101',
      );

      expect(rule.kind, HintKind.readerArea);
      expect(rule.locator.containerSelector, 'div.reading-content');
      expect(rule.locator.imageSelector, 'img');
      expect(rule.locator.minImageEdge, 640, reason: '80% of the 800px floor');
      expect(rule.hintPath, '/comics/genius');
    });

    test(
      'falls back to a sane floor when the container reports nothing',
      () async {
        final rule = await repo.createReaderAreaHint(
          element: const SelectedElement(
            mode: 'reader',
            tag: 'div',
            selector: 'div.reader',
          ),
          sourceUrl: 'https://x.example/c/1',
        );
        expect(rule.locator.minImageEdge, 300);
      },
    );
  });

  group('invalidating a broken rule', () {
    test('failures are recorded without destroying the rule', () async {
      final rule = await repo.createNextLinkHint(
        element: turkishNextButton,
        sourceUrl: 'https://a.example/guide/foo/1',
      );

      await repo.recordUse(rule.id, success: false);
      await repo.recordUse(rule.id, success: false);
      var reloaded = (await repo.all()).single;
      expect(reloaded.failureCount, 2);
      expect(reloaded.successCount, 0);
      expect(reloaded.lastUsedAt, isNull);

      await repo.recordUse(rule.id, success: true);
      reloaded = (await repo.all()).single;
      expect(reloaded.successCount, 1);
      expect(reloaded.lastUsedAt, isNotNull);
    });

    test('deleting a rule stops it being offered', () async {
      final rule = await repo.createNextLinkHint(
        element: turkishNextButton,
        sourceUrl: 'https://a.example/guide/foo/1',
      );
      expect(
        await repo.findFor('https://a.example/guide/foo/2', HintKind.nextLink),
        isNotNull,
      );

      await repo.delete(rule.id);
      expect(
        await repo.findFor('https://a.example/guide/foo/2', HintKind.nextLink),
        isNull,
      );
      expect(await repo.all(), isEmpty);
    });

    test('a replacement rule wins over the one it replaced', () async {
      const url = 'https://a.example/guide/foo/1';
      final old = await repo.createNextLinkHint(
        element: turkishNextButton,
        sourceUrl: url,
      );
      await repo.recordUse(old.id, success: true);

      final replacement = await repo.createNextLinkHint(
        element: germanNextButton,
        sourceUrl: url,
      );
      await repo.recordUse(replacement.id, success: true);

      final found = await repo.findFor(url, HintKind.nextLink);
      expect(found!.id, replacement.id);
    });
  });
}
