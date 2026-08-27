/// "What to save", paired word for word with STORE_PACKAGE.md §6.3 and §6.6.
///
/// Both of those sections are marked **Built — verbatim** and are transcribed
/// from `lib/features/capture_mode_section.dart`. That claim is only worth
/// something if changing a word breaks the build, so every sentence below is
/// written out as a literal rather than read back off the enum that produced
/// it: asserting `mode.description` against itself would pass whatever the
/// widget said.
///
/// Three structural rules are pinned here as well, because they are what the
/// wording depends on: **all three modes are always on screen** — an
/// unavailable one is disabled with its reason beside it, and an available one
/// is its label and its glyph and nothing else — **the heading is the control
/// that closes the block** for a sheet that can reopen it, and **there is no
/// video mode**, which is why §6.6 is a sentence rather than a fourth option.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/capture_mode_section.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/theme.dart';

void main() {
  /// A measured page: what it was classified as, and what the engine could
  /// honestly carry out on it.
  CaptureCapabilities measured(
    ContentKind kind, {
    ShapeConfidence confidence = ShapeConfidence.high,
    Set<CaptureMode> available = const {CaptureMode.textOnly},
    Map<CaptureMode, ModeBlockReason> blocked = const {},
    bool videoDominant = false,
  }) => CaptureCapabilities(
    content: ContentShape(
      kind: kind,
      confidence: confidence,
      basis: 'the fixture said so',
    ),
    available: available,
    blocked: blocked,
    defaultMode: available.isEmpty ? null : available.first,
    videoDominant: videoDominant,
  );

  /// The noun §6.3 gives each detected kind.
  const nouns = <ContentKind, String>{
    ContentKind.imageDominant: 'a page of full-size images',
    ContentKind.article: 'an article',
    ContentKind.datedPost: 'a dated post',
    ContentKind.sequentialText: 'part of a longer text',
    ContentKind.longFormDocument: 'a long document',
    ContentKind.paginatedDocument: 'one page of a document',
    ContentKind.videoDominant: 'a video page',
  };

  /// The two kinds that are a plain "not classified" rather than a noun.
  const unclear = <ContentKind>{
    ContentKind.standalonePage,
    ContentKind.unknownWebContent,
  };

  group('the detection line', () {
    test('names what the page is, one noun per kind', () {
      for (final row in nouns.entries) {
        expect(
          captureDetectionSummary(measured(row.key)),
          'This looks like ${row.value}.',
          reason: '${row.key.name} lost its §6.3 noun',
        );
      }
    });

    test('covers every content kind, either with a noun or as unclear', () {
      // A new ContentKind has to be given a sentence here and in §6.3, rather
      // than falling through to "did not say clearly" unnoticed.
      expect({...nouns.keys, ...unclear}, ContentKind.values.toSet());
    });

    test('says "might" rather than "looks like" when confidence is low', () {
      expect(
        captureDetectionSummary(
          measured(ContentKind.article, confidence: ShapeConfidence.low),
        ),
        'This might be an article — the page did not say clearly.',
      );
      // Medium is a firm answer; only low is hedged.
      expect(
        captureDetectionSummary(
          measured(ContentKind.article, confidence: ShapeConfidence.medium),
        ),
        'This looks like an article.',
      );
    });

    test('gives an unclassified page its own sentence, not a hedged noun', () {
      for (final kind in unclear) {
        expect(
          captureDetectionSummary(measured(kind)),
          'This page did not say clearly what it is. Pick what fits.',
          reason: '${kind.name} was forced through the "looks like" template',
        );
      }
    });

    test('says the page could not be analysed, and offers everything', () {
      const capabilities = CaptureCapabilities.unanalysed();
      expect(
        captureDetectionSummary(capabilities),
        'This page could not be analysed, so every option is offered. '
        'Pick what fits.',
      );
      expect(capabilities.available, CaptureMode.values.toSet());
    });

    test('says plainly when nothing on the page can be saved', () {
      expect(
        captureDetectionSummary(
          measured(
            ContentKind.videoDominant,
            available: const {},
            blocked: const {
              CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
              CaptureMode.textOnly: ModeBlockReason.noReadableText,
              CaptureMode.textAndImages: ModeBlockReason.noReadableText,
            },
            videoDominant: true,
          ),
        ),
        'Nothing on this page can be saved offline.',
      );
    });
  });

  group('the section on screen', () {
    late List<CaptureMode> chosen;

    setUp(() => chosen = <CaptureMode>[]);

    Future<void> pumpSection(
      WidgetTester tester,
      CaptureCapabilities capabilities, {
      CaptureMode? selected,
      VoidCallback? onCollapse,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(palette: AppPalette.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaptureModeSection(
                capabilities: capabilities,
                selected: selected,
                onCollapse: onCollapse,
                onSelect: (mode) => chosen.add(mode),
              ),
            ),
          ),
        ),
      );
    }

    Finder modeOptions() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('captureMode_');
    });

    testWidgets('shows the heading and the detection line it was given', (
      tester,
    ) async {
      await pumpSection(tester, measured(ContentKind.datedPost));

      expect(find.text('What to save'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('captureDetectionSummary')))
            .data,
        'This looks like a dated post.',
      );
    });

    testWidgets('offers all three modes, as a label and a glyph each', (
      tester,
    ) async {
      await pumpSection(
        tester,
        measured(
          ContentKind.article,
          available: const {
            CaptureMode.imageSequence,
            CaptureMode.textOnly,
            CaptureMode.textAndImages,
          },
        ),
      );

      expect(find.text('Images only'), findsOneWidget);
      expect(find.text('Text only'), findsOneWidget);
      expect(find.text('Text and images'), findsOneWidget);
      // One glyph per mode, and the same glyph the collapsed line uses.
      for (final mode in CaptureMode.values) {
        expect(find.byIcon(CaptureModeSection.iconFor(mode)), findsOneWidget);
      }

      // And no sentence under any of them: the block is three single lines,
      // on a sheet that asks three other questions above it. What a mode does
      // is still spelled out where it is a *choice about the work* — the
      // Collection's own capture-mode menu — and the reason an unavailable
      // one gives is not a description and stays (see the next case).
      for (final mode in CaptureMode.values) {
        expect(
          find.text(mode.description),
          findsNothing,
          reason: '${mode.name} still prints its description',
        );
      }
    });

    testWidgets('the heading closes the block only where a caller can reopen '
        'it', (tester) async {
      // The dropdown rule: whatever opened this block closes it, and the
      // heading is that control. A block with no collapsed line behind it —
      // the first save of a work — has nothing to collapse *to*, so it is not
      // offered a way to hide the question.
      var collapsed = 0;
      await pumpSection(tester, measured(ContentKind.article));
      expect(find.byKey(const ValueKey('captureModeCollapse')), findsNothing);

      await pumpSection(
        tester,
        measured(ContentKind.article),
        onCollapse: () => collapsed++,
      );
      expect(find.text('What to save'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('captureModeCollapse')));
      await tester.pump();

      expect(collapsed, 1);
    });

    testWidgets('keeps an unavailable mode on screen with its reason', (
      tester,
    ) async {
      await pumpSection(
        tester,
        measured(
          ContentKind.unknownWebContent,
          available: const {},
          blocked: const {
            CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
            CaptureMode.textOnly: ModeBlockReason.noReadableText,
            CaptureMode.textAndImages: ModeBlockReason.noMeaningfulImages,
          },
        ),
      );

      // Still three rows: a missing option reads as a bug, a disabled one with
      // its reason beside it reads as an answer.
      expect(modeOptions(), findsNWidgets(3));
      expect(
        find.text(
          'This page does not have enough full-size images to save as an '
          'image sequence.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('No readable text was found on this page.'),
        findsOneWidget,
      );
      expect(
        find.text('No images were found inside the readable text.'),
        findsOneWidget,
      );
      // The reason stands *in place of* the description, never beside it.
      expect(
        find.text('Save the readable text. No images are downloaded.'),
        findsNothing,
      );
    });

    testWidgets('lets an available mode be chosen', (tester) async {
      await pumpSection(
        tester,
        measured(ContentKind.article, available: const {CaptureMode.textOnly}),
      );

      await tester.tap(find.byKey(const ValueKey('captureMode_textOnly')));
      await tester.pump();

      expect(chosen, [CaptureMode.textOnly]);
    });

    testWidgets('ignores a tap on a mode this page cannot honour', (
      tester,
    ) async {
      await pumpSection(
        tester,
        measured(
          ContentKind.article,
          available: const {CaptureMode.textOnly},
          blocked: const {
            CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
            CaptureMode.textAndImages: ModeBlockReason.noMeaningfulImages,
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('captureMode_imageSequence')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('captureMode_textAndImages')));
      await tester.pump();

      expect(chosen, isEmpty);
    });

    testWidgets('says video is not saved, and what will be saved instead', (
      tester,
    ) async {
      await pumpSection(
        tester,
        measured(
          ContentKind.videoDominant,
          available: const {CaptureMode.textOnly},
          blocked: const {
            CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
            CaptureMode.textAndImages: ModeBlockReason.noMeaningfulImages,
          },
          videoDominant: true,
        ),
      );

      expect(find.byKey(const ValueKey('videoNotSavedNotice')), findsOneWidget);
      expect(
        find.text(
          'Video is not saved. The readable text on this page can be, and '
          'the entry will link back to the original for anything that plays.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says video is not saved when there is nothing to save '
        'instead', (tester) async {
      await pumpSection(
        tester,
        measured(
          ContentKind.videoDominant,
          available: const {},
          blocked: const {
            CaptureMode.imageSequence: ModeBlockReason.noImageSequence,
            CaptureMode.textOnly: ModeBlockReason.noReadableText,
            CaptureMode.textAndImages: ModeBlockReason.noReadableText,
          },
          videoDominant: true,
        ),
      );

      expect(find.byKey(const ValueKey('videoNotSavedNotice')), findsOneWidget);
      expect(
        find.text(
          'Video is not saved, and this page has no readable text to save '
          'instead. Open it in the Browser when you want to watch it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says nothing about video on a page that is not one', (
      tester,
    ) async {
      await pumpSection(tester, measured(ContentKind.article));

      expect(find.byKey(const ValueKey('videoNotSavedNotice')), findsNothing);
      expect(find.textContaining('Video is not saved'), findsNothing);
    });

    testWidgets('offers exactly three modes, because there is no video one', (
      tester,
    ) async {
      // The sheet is built from the enum, so a fourth value would become a
      // fourth row — an offer the save engine could not carry out.
      expect(CaptureMode.values, hasLength(3));

      await pumpSection(tester, const CaptureCapabilities.unanalysed());

      expect(modeOptions(), findsNWidgets(3));
      for (final mode in CaptureMode.values) {
        expect(
          find.byKey(ValueKey('captureMode_${mode.name}')),
          findsOneWidget,
        );
      }
    });
  });
}
