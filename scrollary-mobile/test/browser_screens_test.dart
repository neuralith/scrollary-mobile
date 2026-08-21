import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/browser/favicon_service.dart';
import 'package:web_reader/browser/history_repository.dart';
import 'package:web_reader/browser/saved_sites_repository.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/features/browser_data_dialogs.dart';
import 'package:web_reader/features/browser_history_screen.dart';
import 'package:web_reader/features/saved_site_sheets.dart';
import 'package:web_reader/features/settings_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

/// The History screen, the Add-site flow, and the two clearing dialogs.
void browserWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

void main() {
  late AppDatabase db;
  late Directory root;
  late HistoryRepository history;
  late SavedSitesRepository saved;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_browser_screens');
    history = HistoryRepository(db);
    saved = SavedSitesRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget host(Widget child) {
    final store = FileStore(root);
    final browser = BrowserController();
    addTearDown(browser.dispose);
    final run = SaveRunController(browser: browser, db: db, fileStore: store);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        saveRunProvider.overrideWithValue(run),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        // Settings quotes the queue's history limit, so it needs a real one.
        taskQueueProvider.overrideWithValue(
          TaskQueueController(
            db: db,
            browser: browser,
            saveRun: run,
            checker: UpdateChecker(browser: browser, db: db),
          ),
        ),
        faviconServiceProvider.overrideWithValue(
          FaviconService(db: db, allowNetwork: false),
        ),
      ],
      child: MaterialApp(theme: appTheme(), home: child),
    );
  }

  Future<void> seedVisits({DateTime? now}) async {
    final at = now ?? DateTime.now();
    await history.recordVisit(
      url: 'https://a.example/guide/long-guide/885',
      title: 'The Long Guide',
      source: NavigationSource.manual,
      now: at.subtract(const Duration(minutes: 4)),
    );
    await history.recordVisit(
      url: 'https://a.example/guide/long-guide',
      title: 'Contents',
      source: NavigationSource.manual,
      now: at.subtract(const Duration(minutes: 12)),
    );
    await history.recordVisit(
      url: 'https://b.example/notes/field/137',
      title: 'Field Notes 137',
      source: NavigationSource.manual,
      now: at.subtract(const Duration(days: 1, hours: 3)),
    );
  }

  group('History screen', () {
    browserWidgetTest('groups by day and lists real visits', (tester) async {
      await seedVisits();
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('The Long Guide'), findsOneWidget);
      expect(find.text('Field Notes 137'), findsOneWidget);
    });

    browserWidgetTest('shows nothing from save automation', (tester) async {
      await history.recordVisit(
        url: 'https://a.example/guide/long-guide/886',
        title: 'Saved entry',
        source: NavigationSource.saveAutomation,
      );
      await history.recordVisit(
        url: 'https://a.example/guide/long-guide',
        title: 'Checked list',
        source: NavigationSource.updateCheck,
      );
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      expect(find.text('Saved entry'), findsNothing);
      expect(find.text('Checked list'), findsNothing);
      expect(find.text('No history yet'), findsOneWidget);
    });

    browserWidgetTest('search filters, and says so when nothing matches', (
      tester,
    ) async {
      await seedVisits();
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('historySearchField')),
        'field',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Field Notes 137'), findsOneWidget);
      expect(find.text('The Long Guide'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('historySearchField')),
        'zzzzz',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No matches'), findsOneWidget);
    });

    browserWidgetTest('the Sites tab groups by hostname with counts', (
      tester,
    ) async {
      await seedVisits();
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      await tester.tap(find.text('Sites'));
      await tester.pump();

      // Two hosts, two rows, and the counts belong to the right ones.
      expect(find.text('a.example'), findsOneWidget);
      expect(find.textContaining('2 visits'), findsOneWidget);
      expect(find.text('b.example'), findsOneWidget);
      expect(find.textContaining('1 visit ·'), findsOneWidget);
    });

    browserWidgetTest('a hostname expands to its pages', (tester) async {
      await seedVisits();
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();
      await tester.tap(find.text('Sites'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('historyHost-a.example')));
      await tester.pumpAndSettle();

      expect(find.text('Contents'), findsOneWidget);
      expect(find.text('Add to Saved Sites'), findsOneWidget);
      expect(find.text('Remove site history'), findsOneWidget);
    });

    browserWidgetTest('a row menu can remove that single visit', (
      tester,
    ) async {
      await seedVisits();
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      await tester.tap(find.text('Field Notes 137'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('historyRemoveVisit')));
      await tester.pumpAndSettle();

      expect(await db.visits(), hasLength(2));
    });

    browserWidgetTest('the empty state explains where history comes from', (
      tester,
    ) async {
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();
      expect(find.text('No history yet'), findsOneWidget);
      expect(find.textContaining('Nothing is sent anywhere'), findsOneWidget);
    });
  });

  group('clear history', () {
    browserWidgetTest('shows a count per range and clears the chosen one', (
      tester,
    ) async {
      final now = DateTime.now();
      await seedVisits(now: now);
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('historyClearButton')));
      await tester.pumpAndSettle();

      expect(find.text('Clear browsing history'), findsOneWidget);
      // The promise the sheet makes about what it will not touch.
      expect(find.text('This does not touch'), findsOneWidget);
      expect(find.textContaining('Saved sites · your library'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clearRange-lastHour')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmClearHistory')));
      await tester.pumpAndSettle();

      final left = await db.visits();
      expect(left, hasLength(1), reason: 'only yesterday survives');
      // Yesterday's visit is the one on the second host.
      expect(left.single.host, 'b.example');
    });

    browserWidgetTest('clearing all time keeps saved sites', (tester) async {
      await seedVisits();
      await SavedSitesRepository(
        db,
      ).save(url: 'https://kept.example/', title: 'Kept');
      await tester.pumpWidget(host(const BrowserHistoryScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('historyClearButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clearRange-allTime')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmClearHistory')));
      await tester.pumpAndSettle();

      expect(await db.visits(), isEmpty);
      // The saved site the test put there is untouched. Nothing is seeded, so
      // the row has to be created for the assertion to mean anything.
      expect(
        (await db.allSavedSites()).map((s) => s.title),
        ['Kept'],
        reason: 'clearing history must not reach the saved-sites list',
      );
    });
  });

  group('clear website data', () {
    browserWidgetTest(
      'the destructive button is gated on the acknowledgement',
      (tester) async {
        await tester.pumpWidget(
          host(
            Scaffold(
              body: Builder(
                builder: (context) => Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => showClearWebsiteDataDialog(context, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Clear website data?'), findsOneWidget);
        expect(
          find.textContaining('signs you out of every site'),
          findsOneWidget,
        );
        // It also says what it keeps, because that is the fear.
        expect(
          find.textContaining('library, saved entries, saved sites'),
          findsOneWidget,
        );

        final before = tester.widget<FilledButton>(
          find.byKey(const ValueKey('confirmClearWebsiteData')),
        );
        expect(before.onPressed, isNull, reason: 'gated until acknowledged');

        await tester.tap(find.byKey(const ValueKey('clearDataAcknowledge')));
        await tester.pumpAndSettle();

        final after = tester.widget<FilledButton>(
          find.byKey(const ValueKey('confirmClearWebsiteData')),
        );
        expect(after.onPressed, isNotNull);
      },
    );
  });

  group('Add saved site', () {
    browserWidgetTest('recent pages are offered, and saving one works', (
      tester,
    ) async {
      await seedVisits();
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddSavedSiteSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Add a saved site'), findsOneWidget);
      expect(find.text('Recent pages'), findsOneWidget);
      expect(find.text('Visited sites'), findsOneWidget);
      expect(find.byKey(const ValueKey('addSavedSiteManual')), findsOneWidget);

      await tester.tap(find.text('The Long Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Save site'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('savedSiteSaveButton')));
      await tester.pumpAndSettle();

      final sites = await db.allSavedSites();
      expect(sites, hasLength(1));
      expect(sites.single.url, 'https://a.example/guide/long-guide/885');
    });

    browserWidgetTest('a hostname with no reliable root says so', (
      tester,
    ) async {
      // Only ever seen one deep page on this host, on a non-default port —
      // so no homepage can be derived and the flow must not invent one.
      await history.recordVisit(
        url: 'https://oldmirror.example:8443/steel-peony/28',
        title: 'Steel Peony 28',
        source: NavigationSource.manual,
      );
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddSavedSiteSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visited sites'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No reliable home page seen'), findsOneWidget);
    });

    browserWidgetTest('manual entry validates the address', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddSavedSiteSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('addSavedSiteManual')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('savedSiteTitleField')),
        'My site',
      );
      await tester.enterText(
        find.byKey(const ValueKey('savedSiteUrlField')),
        'not an address',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter a full address'), findsOneWidget);
      final blocked = tester.widget<FilledButton>(
        find.byKey(const ValueKey('savedSiteSaveButton')),
      );
      expect(blocked.onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('savedSiteUrlField')),
        'https://mysite.example/',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('savedSiteSaveButton')));
      await tester.pumpAndSettle();

      expect(await db.allSavedSites(), hasLength(1));
    });

    browserWidgetTest('a duplicate is explained and offers to update', (
      tester,
    ) async {
      await saved.save(url: 'https://mysite.example/', title: 'Original');
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSaveSiteSheet(
                  context,
                  url: 'https://mysite.example/',
                  title: 'Second attempt',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('This address is already saved.'), findsOneWidget);
      expect(
        find.textContaining('instead of adding a duplicate'),
        findsOneWidget,
      );
      expect(find.text('Update tile'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('savedSiteSaveButton')));
      await tester.pumpAndSettle();

      final sites = await db.allSavedSites();
      expect(sites, hasLength(1), reason: 'never a second row');
      expect(savedSiteDisplayTitle(sites.single), 'Second attempt');
    });
  });

  group('Settings', () {
    browserWidgetTest('has a Browser section with the three doors', (
      tester,
    ) async {
      await seedVisits();
      await tester.pumpWidget(host(const SettingsScreen()));
      await tester.pump();

      expect(find.text('BROWSER'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settingsBrowsingHistory')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settingsSavedSites')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settingsClearWebsiteData')),
        findsOneWidget,
      );
      // The privacy and retention note the design asks for.
      expect(find.textContaining('never leave this device'), findsOneWidget);
      expect(find.textContaining('90 days'), findsOneWidget);
    });

    browserWidgetTest('has the appearance control', (tester) async {
      await tester.pumpWidget(host(const SettingsScreen()));
      await tester.pump();
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.byKey(const ValueKey('appearanceSelector')), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    browserWidgetTest('choosing an appearance persists it', (tester) async {
      await tester.pumpWidget(host(const SettingsScreen()));
      await tester.pump();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(await db.setting(kAppearanceSettingKey), 'dark');
    });
  });
}
