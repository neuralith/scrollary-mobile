import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/collection_name_panel.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/ui/theme.dart';

/// The naming panel itself: what it offers, what it refuses, and what it hands
/// back. A pure function of its arguments, so no save, database or WebView is
/// stood up here.
void main() {
  /// The default 800×600 test window is wider and much shorter than any phone.
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  const proposal = NewCollectionProposal(
    suggestedName: 'The Long Guide',
    host: 'x.example',
    entryUrl: 'https://x.example/guide/the-long-guide/part-3',
  );

  Widget host({
    required void Function(String?) onResult,
    NewCollectionProposal offer = proposal,
  }) => MaterialApp(
    theme: appTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: CollectionNamePanel(proposal: offer, onSubmit: onResult),
      ),
    ),
  );

  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('collectionNameField')))
      .controller!
      .text;

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('collectionNameSave')),
          )
          .onPressed !=
      null;

  testWidgets('the field is prefilled with the suggestion', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(host(onResult: (_) {}));
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'The Long Guide');
    expect(find.text('Name this collection'), findsOneWidget);
    expect(find.textContaining('x.example'), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('a page that offered nothing opens with an empty field', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      host(
        onResult: (_) {},
        offer: const NewCollectionProposal(
          suggestedName: '',
          host: 'x.example',
          entryUrl: 'https://x.example/reading/part-24',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester), isEmpty);
    expect(
      saveEnabled(tester),
      isFalse,
      reason: 'there is no name to save yet',
    );
    expect(find.textContaining('did not offer a name'), findsOneWidget);
  });

  testWidgets('a whitespace-only name cannot be saved', (tester) async {
    usePhoneSurface(tester);
    String? result;
    var answered = false;
    await tester.pumpWidget(
      host(
        onResult: (v) {
          answered = true;
          result = v;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('collectionNameField')),
      '   ',
    );
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('collectionNameSave')));
    await tester.pumpAndSettle();
    expect(answered, isFalse);
    expect(result, isNull);
  });

  testWidgets('the suggestion can be replaced outright', (tester) async {
    usePhoneSurface(tester);
    String? result;
    await tester.pumpWidget(host(onResult: (v) => result = v));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('collectionNameField')),
      'My Reading Shelf',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('collectionNameSave')));
    await tester.pumpAndSettle();

    expect(result, 'My Reading Shelf');
  });

  testWidgets('accepting the suggestion hands it back unchanged', (
    tester,
  ) async {
    usePhoneSurface(tester);
    String? result;
    await tester.pumpWidget(host(onResult: (v) => result = v));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('collectionNameSave')));
    await tester.pumpAndSettle();

    expect(result, 'The Long Guide');
  });

  testWidgets('cancel hands back null', (tester) async {
    usePhoneSurface(tester);
    String? result = 'untouched';
    var answered = false;
    await tester.pumpWidget(
      host(
        onResult: (v) {
          answered = true;
          result = v;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('collectionNameCancel')));
    await tester.pumpAndSettle();

    expect(answered, isTrue);
    expect(result, isNull);
  });

  testWidgets('the panel says cancelling costs nothing already held', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(host(onResult: (_) {}));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cancelling stops this save'), findsOneWidget);
    expect(find.textContaining('Nothing has been saved yet'), findsOneWidget);
  });
}
