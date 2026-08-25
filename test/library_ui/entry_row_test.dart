/// The Entry row's two lines, and the trailing block that replaced its third
/// (V2-D63).
///
/// The row used to write its state: `Unread · On this device`, a line of prose
/// for two booleans under an identity that inside a Collection is often a
/// single number. It draws them now — a ring that is always present and one
/// glyph that appears when this device holds bytes — so what has to be pinned
/// is different from what a screen test can see:
///
/// * the words are **gone from the screen** and **still spoken**;
/// * the two facts stay independent, in all six combinations;
/// * the trailing block cannot be clipped, which is the bug the old line had
///   at a large text scale on a narrow phone;
/// * a state that is *happening* still gets a word.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/library_ui/collection_models.dart';
import 'package:web_reader/library_ui/library_widgets.dart';
import 'package:web_reader/ui/palette.dart';
import 'package:web_reader/ui/status_style.dart';
import 'package:web_reader/ui/theme.dart';

void main() {
  EntryRow row(String id, {double? ordinal = 1, String title = ''}) => EntryRow(
    id: id,
    collectionId: 'collection',
    ordinal: ordinal,
    placement: 'placed',
    title: title,
    sortKey: 0,
    revision: 1,
    updatedAt: DateTime(2020),
  );

  /// One row, in the state the case is about. `label` is what a Collection
  /// row leads with — the position — and `subtitle` is the Entry's own name
  /// where it has one that is not just that position again.
  EntryRowView view({
    String id = 'e1',
    ReadStatus status = ReadStatus.unread,
    bool availableOffline = false,
    double progress = 0,
    String label = '101',
    String? subtitle,
  }) => EntryRowView(
    row: row(id, title: subtitle ?? ''),
    status: status,
    availableOffline: availableOffline,
    progress: progress,
    label: label,
    subtitle: subtitle,
  );

  Widget host(
    Widget child, {
    AppPalette palette = AppPalette.light,
    TextScaler textScaler = TextScaler.noScaling,
  }) => MaterialApp(
    theme: appTheme(palette: palette),
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Column(children: [child]),
        ),
      ),
    ),
  );

  Widget tile(EntryRowView v, {List<Widget> badges = const []}) =>
      EntryRowTile(view: v, onTap: () {}, onMenu: () {}, badges: badges);

  /// A phone, not the 800×600 default: the row's whole subject is how much
  /// vertical space it takes on one.
  void phone(WidgetTester tester, {double width = 430}) {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  EntryProgressRing ringIn(WidgetTester tester, String id) => tester.widget(
    find.descendant(
      of: find.byKey(ValueKey('entryProgress-$id')),
      matching: find.byType(EntryProgressRing),
    ),
  );

  Finder offlineGlyph(String id) => find.byKey(ValueKey('entryOffline-$id'));

  group('the row writes no state', () {
    testWidgets('neither read state nor availability is prose', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          tile(
            view(
              status: ReadStatus.reading,
              availableOffline: true,
              progress: 0.42,
              subtitle: 'The Quiet Night',
            ),
          ),
        ),
      );

      // The identity and the Entry's own name, and nothing else in words.
      expect(find.text('101'), findsOneWidget);
      expect(find.text('The Quiet Night'), findsOneWidget);
      for (final gone in const [
        'Unread',
        'Reading',
        'Read',
        'On this device',
      ]) {
        expect(find.text(gone), findsNothing, reason: '"$gone" is drawn now');
      }
    });

    testWidgets('a state that is happening still gets its word', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          tile(
            view(subtitle: 'The Quiet Night'),
            badges: const [
              StatusChip(
                icon: Icons.schedule,
                label: 'Waiting to start',
                bg: Color(0xFFEFEBE4),
                fg: Color(0xFF5D584F),
                border: Color(0xFFDDD8CF),
              ),
            ],
          ),
        ),
      );

      // The division the trailing block depends on: permanent facts are
      // glyphs, and anything in flight is a sentence.
      expect(find.text('Waiting to start'), findsOneWidget);
    });
  });

  group('the state matrix', () {
    // Six combinations of two independent facts (PRODUCT.md §2.3). Each cell
    // differs from every other by shape — a glyph present or absent, a ring
    // empty, wedged or filled — never by tint alone.
    for (final (name, status, progress, offline, fraction, completed)
        in <(String, ReadStatus, double, bool, double, bool)>[
          ('unread, not downloaded', ReadStatus.unread, 0, false, 0, false),
          ('unread, downloaded', ReadStatus.unread, 0, true, 0, false),
          (
            'reading, not downloaded',
            ReadStatus.reading,
            0.42,
            false,
            0.42,
            false,
          ),
          ('reading, downloaded', ReadStatus.reading, 0.42, true, 0.42, false),
          ('read, not downloaded', ReadStatus.completed, 0.3, false, 1, true),
          ('read, downloaded', ReadStatus.completed, 0.3, true, 1, true),
        ]) {
      testWidgets(name, (tester) async {
        phone(tester);
        await tester.pumpWidget(
          host(
            tile(
              view(
                status: status,
                progress: progress,
                availableOffline: offline,
              ),
            ),
          ),
        );

        // The ring is on every row, empty included.
        expect(find.byKey(const ValueKey('entryProgress-e1')), findsOneWidget);
        final ring = ringIn(tester, 'e1');
        expect(ring.fraction, closeTo(fraction, 0.0001));
        expect(ring.completed, completed);

        expect(
          offlineGlyph('e1'),
          offline ? findsOneWidget : findsNothing,
          reason: 'the device fact is drawn exactly when it is true',
        );
      });
    }

    for (final (appearance, palette) in [
      ('light', AppPalette.light),
      ('dark', AppPalette.dark),
    ]) {
      testWidgets('the offline glyph is the theme primary in $appearance', (
        tester,
      ) async {
        phone(tester);
        await tester.pumpWidget(
          host(tile(view(availableOffline: true)), palette: palette),
        );

        final icon = tester.widget<Icon>(offlineGlyph('e1'));
        expect(icon.icon, Icons.download_for_offline);
        expect(
          icon.color,
          palette.primary,
          reason: 'no literal colour, and no green invented for downloads',
        );
      });
    }
  });

  group('what a screen reader is told', () {
    testWidgets('the words the row stopped drawing are all on its node', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      phone(tester);

      await tester.pumpWidget(
        host(
          tile(
            view(
              status: ReadStatus.reading,
              availableOffline: true,
              progress: 0.42,
              subtitle: 'The Quiet Night',
            ),
          ),
        ),
      );

      // More than the visible line ever carried: it never said the
      // percentage.
      expect(
        find.bySemanticsLabel(
          '101. The Quiet Night. Reading · 42%. On this device',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('an unread row with no copy says both, and no percentage', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      phone(tester);

      await tester.pumpWidget(host(tile(view())));

      expect(find.bySemanticsLabel('101. Unread'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a finished row reads as Read, not as 100%', (tester) async {
      final semantics = tester.ensureSemantics();
      phone(tester);

      await tester.pumpWidget(
        host(tile(view(status: ReadStatus.completed, progress: 0.3))),
      );

      expect(find.bySemanticsLabel('101. Read'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the ring and the glyph do not speak a second time', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      phone(tester);

      await tester.pumpWidget(host(tile(view(availableOffline: true))));

      // The ring carries its own label wherever else it is used; on a row it
      // is one clause of the row's label and must not be a node of its own.
      expect(find.bySemanticsLabel('Unread · 0%'), findsNothing);
      semantics.dispose();
    });

    testWidgets('the actions control stays a separate target', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(tile(view())));

      expect(find.byTooltip('Entry actions'), findsOneWidget);
      final size = tester.getSize(find.byKey(const ValueKey('entryMenu-e1')));
      expect(
        size.height,
        greaterThanOrEqualTo(48),
        reason: 'the row got shorter; its one control did not',
      );
      expect(size.width, greaterThanOrEqualTo(48));
    });
  });

  group('height', () {
    testWidgets('a row with a name and a row without are the same height', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(tile(view())));
      final bare = tester.getSize(find.byType(EntryRowTile)).height;

      await tester.pumpWidget(
        host(tile(view(subtitle: 'The Quiet Night', availableOffline: true))),
      );
      final named = tester.getSize(find.byType(EntryRowTile)).height;

      expect(bare, kEntryRowMinHeight);
      expect(
        named,
        kEntryRowMinHeight,
        reason: 'a list of these scans as a column, not as alternating blocks',
      );
    });

    testWidgets('holding a copy costs a row nothing', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(tile(view(subtitle: 'The Quiet Night'))));
      final plain = tester.getSize(find.byType(EntryRowTile)).height;

      await tester.pumpWidget(
        host(tile(view(subtitle: 'The Quiet Night', availableOffline: true))),
      );

      expect(
        tester.getSize(find.byType(EntryRowTile)).height,
        plain,
        reason: 'a downloaded Entry is an ordinary row (PRODUCT.md §2.3)',
      );
    });

    testWidgets('a badge is worth its line, and only while it is there', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(host(tile(view(subtitle: 'The Quiet Night'))));
      final steady = tester.getSize(find.byType(EntryRowTile)).height;

      await tester.pumpWidget(
        host(
          tile(
            view(subtitle: 'The Quiet Night'),
            badges: const [
              StatusChip(
                icon: Icons.downloading,
                label: 'Downloading',
                bg: Color(0xFFE7EFF3),
                fg: Color(0xFF123642),
                border: Color(0xFFCCDFE6),
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(EntryRowTile)).height,
        greaterThan(steady),
      );
    });
  });

  group('a narrow phone at a large text scale', () {
    // The bug the old layout had: `Unread · ⤓ On this device` was an
    // unbounded `Row`, so at 1.3× on a 320pt screen it overflowed by 115px
    // and hard-clipped — invisible content, in the configuration where being
    // able to read it matters most.
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('nothing is clipped at ${scale}x', (tester) async {
        phone(tester, width: 320);
        await tester.pumpWidget(
          host(
            tile(
              view(
                status: ReadStatus.reading,
                availableOffline: true,
                progress: 0.42,
                label: 'Prologue, and a title long enough to need the room',
                subtitle: 'An entry that also has a name of its own',
              ),
              badges: const [
                StatusChip(
                  icon: Icons.schedule,
                  label: 'Waiting to start',
                  bg: Color(0xFFEFEBE4),
                  fg: Color(0xFF5D584F),
                  border: Color(0xFFDDD8CF),
                ),
              ],
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );

        expect(tester.takeException(), isNull);
        // Still drawn, not squeezed out: the trailing block is fixed-size and
        // the text beside it is what gives way.
        expect(offlineGlyph('e1'), findsOneWidget);
        expect(find.byKey(const ValueKey('entryProgress-e1')), findsOneWidget);
      });
    }

    testWidgets('a taller row is what a large text scale buys', (tester) async {
      phone(tester, width: 320);
      final v = view(subtitle: 'An entry that also has a name of its own');

      await tester.pumpWidget(host(tile(v)));
      final normal = tester.getSize(find.byType(EntryRowTile)).height;

      await tester.pumpWidget(
        host(tile(v), textScaler: const TextScaler.linear(2)),
      );

      expect(
        tester.getSize(find.byType(EntryRowTile)).height,
        greaterThan(normal),
        reason: 'the row grows for the text rather than clipping it',
      );
    });
  });
}
