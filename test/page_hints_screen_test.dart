/// Settings' list of saved rules, over the V2 library.
///
/// Two properties: **the app ships none** — a clean install lists nothing and
/// nothing seeds the table — and **what the capture path writes is what this
/// screen reads**, which is the V2 `page_hints` table and no other.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/features/page_hints_screen.dart';
import 'package:web_reader/save/page_hint_repository.dart';

import 'library_ui/support/ui_harness.dart';

const _readerContainer = SelectedElement(
  mode: 'reader',
  tag: 'div',
  classes: 'reading-content',
  selector: 'div.reading-content',
  imageCount: 12,
  minImageEdge: 800,
  imageSelector: 'img',
);

const _pageUrl = 'https://reading.example.com/serial-alpha/part-101';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  screenTest('a clean library lists no rules at all', (tester) async {
    await tester.pumpWidget(h.app(const PageHintsScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('No saved rules'), findsOneWidget);
  });

  screenTest('a rule taught by a tap is listed', (tester) async {
    await PageHintRepository.forLibrary(
      h.db,
    ).createReaderAreaHint(element: _readerContainer, sourceUrl: _pageUrl);

    await tester.pumpWidget(h.app(const PageHintsScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('No saved rules'), findsNothing);
    expect(find.text('reading.example.com'), findsOneWidget);
    expect(find.textContaining('Reader area'), findsOneWidget);
    expect(
      find.textContaining('this collection'),
      findsOneWidget,
      reason: 'the scope the rule was taught at is shown, not inferred',
    );
  });

  screenTest('forgetting a rule takes it off the list', (tester) async {
    final repo = PageHintRepository.forLibrary(h.db);
    final rule = await repo.createReaderAreaHint(
      element: _readerContainer,
      sourceUrl: _pageUrl,
    );

    await tester.pumpWidget(h.app(const PageHintsScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('reading.example.com'), findsOneWidget);

    await repo.delete(rule.id);
    await tester.pump();
    await tester.pump();

    expect(find.text('No saved rules'), findsOneWidget);
  });
}
