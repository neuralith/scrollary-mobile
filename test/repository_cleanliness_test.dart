import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The guard that stops the old product model from growing back.
///
/// This test scans the repository — production code, generated code, tests,
/// documentation, platform metadata and asset filenames — for the vocabulary of
/// the app this one replaced. It exists because a rename is only durable if
/// reintroducing the old word is a build failure rather than a code-review
/// opinion.
///
/// **Adding an allowance is a deliberate act.** Every entry in [_allowed] needs a
/// reason recorded next to it, and the reason has to be that the word has a
/// genuinely unrelated technical meaning — never "this one is fine for now".
void main() {
  /// Words that described the previous product: a downloader for one genre of
  /// serialised third-party content.
  const forbidden = <String>[
    // the old domain model
    'chapter',
    'chapters',
    'chapterid',
    'chapter_id',
    'chapterindex',
    'chapterorder',
    'seriesid',
    'series_id',
    'seriesdetail',
    'libraryitem',
    'library_item',
    'capture_jobs',
    'site_rule',
    'siterule',
    'episode',
    'episodes',
    // genre-specific positioning
    'manga',
    'webtoon',
    'comic',
    'scanlation',
    'doujin',
    // downloader / crawler positioning
    'scraper',
    'scraping',
    'crawler',
    'crawling',
    'bulk download',
    'download all',
    'grab chapter',
    'capture chapter',
    'download chapter',
    'download series',
    'novel downloader',
    // access circumvention
    'bypass paywall',
    'bypass login',
    'bypass captcha',
    'supported site',
    'supportedsites',
  ];

  /// Lines exempt wherever they appear, because the line is *about* the display
  /// vocabulary rather than using the old model.
  ///
  /// Line-level rather than file-level on purpose: exempting a whole file would
  /// stop the check for everything else in it, and the two files that legitimately
  /// exercise `EntryLabelStyle.chapter` also contain plenty that must stay clean.
  bool isLabelVocabulary(String line) =>
      line.contains('EntryLabelStyle.') ||
      line.contains('EntryLabels(') ||
      line.contains('labelsFromNames(') ||
      line.contains('labelsFor(');

  /// Allowed occurrences, each with the reason it is not the old model.
  ///
  /// Keyed by the path the match may appear in; the value is why.
  const allowed = <String, String>{
    // The user-facing label vocabulary. "Chapter" and "Episode" are two of eight
    // *display* labels chosen from measured structure, behind a confidence gate.
    // They are not the canonical model — `Entry` is — and this file is the only
    // place they exist.
    'lib/library/entry_labels.dart':
        'contextual display labels; the canonical model is Entry',
    'lib/library/content_shape.dart':
        'doc comment explaining that a number in a URL is not a chapter',
    // The entry-number parser's word list. These are words **other people's
    // websites print in their titles and URLs**, fed in as parser input so a
    // number can be read out of them — not names this product uses for its own
    // model, which is still Entry. The distinction is the same one that lets
    // `entry_labels.dart` hold the display vocabulary: recognising a word is
    // not adopting it. The list is also why `"Chapter 12"` parses at all; it
    // held only `chap|ch` once, and the commonest entry title in English came
    // out as no number.
    'lib/library/collection_identity.dart':
        'parser input — words a source may print, not this app\'s model',
    'test/entry_number_test.dart':
        'exercises that parser against the titles and URLs sites really use',
    // This file names the words in order to forbid them.
    'test/repository_cleanliness_test.dart': 'the forbidden list itself',
    'test/schema_v1_test.dart':
        'names the old tables and columns in order to assert their absence',
    // These two exercise the Chapter *display* style — one of eight, reached
    // only by a confident detection — including the rule that a low-confidence
    // shape must never be given it. Testing that rule means naming the word.
    'test/entry_sort_test.dart': 'exercises the Chapter display style',
    'test/collection_identity_test.dart': 'exercises the Chapter display style',
    // The restricted-site capture policy. It names commercial content services
    // in order to **refuse** them, which is the opposite of a supported-site
    // catalogue: nothing here makes any site work, and no page is detected,
    // measured or handled differently because of it. Two of the hosts on the
    // list happen to contain a word this file forbids, and recognising a word
    // in somebody else's hostname is not adopting it as this product's model —
    // the same distinction that lets `collection_identity.dart` hold parser
    // input. See `lib/save/capture_policy.dart` for the reasoning, and the
    // duplication guard at the bottom of this file for what keeps it the only
    // copy.
    'lib/save/capture_policy.dart':
        'the restricted-site refusal list; a refusal is not a catalogue',
    'test/capture_policy_test.dart':
        'exercises that list, including the lookalikes it must not match',
    // The store and policy documents have to name what the app is *not*, and
    // the rename inventory has to name what was renamed.
    'docs/TERMINOLOGY.md': 'the old → new rename inventory',
  };

  /// Directories with no bearing on the shipped product or its docs.
  bool isSkipped(String path) {
    const skip = [
      '.git/',
      'build/',
      '.dart_tool/',
      'ios/Pods/',
      'ios/build/',
      'android/.gradle/',
      'android/build/',
      '.idea/',
      'ios/.symlinks/', // pub cache symlinks into other packages
      'ios/Flutter/AppFrameworkInfo.plist',
      'ios/RunnerTests/',
      'assets/fonts/', // upstream OFL licence texts
      'pubspec.lock',
      '.flutter-plugins-dependencies',
      'ios/Flutter/ephemeral/',
      'ios/Runner.xcworkspace/',
      'ios/Runner.xcodeproj/xcuserdata/',
    ];
    return skip.any(path.contains);
  }

  /// Text files whose content is part of the product or its documentation.
  bool isScanned(String path) {
    const extensions = [
      '.dart',
      '.md',
      '.yaml',
      '.yml',
      '.json',
      '.plist',
      '.xml',
      '.kt',
      '.java',
      '.swift',
      '.kts',
      '.gradle',
      '.pbxproj',
      '.storyboard',
      '.entitlements',
      '.sh',
      '.txt',
    ];
    return extensions.any(path.endsWith);
  }

  late List<File> files;

  setUpAll(() {
    files = Directory.current.listSync(recursive: true).whereType<File>().where(
      (f) {
        final path = f.path.replaceFirst('${Directory.current.path}/', '');
        return !isSkipped(path) && isScanned(path);
      },
    ).toList();
  });

  test('the repository is scanning a plausible number of files', () {
    // A guard on the guard: a glob that silently matches nothing would make
    // every assertion below pass for the wrong reason.
    expect(
      files.length,
      greaterThan(80),
      reason: 'the cleanliness scan found almost nothing — check the filters',
    );
  });

  test('no file reintroduces the previous product vocabulary', () {
    final offences = <String>[];

    for (final file in files) {
      final path = file.path.replaceFirst('${Directory.current.path}/', '');
      if (allowed.containsKey(path)) continue;

      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (isLabelVocabulary(lines[i])) continue;
        final lower = lines[i].toLowerCase();
        for (final word in forbidden) {
          if (!lower.contains(word)) continue;
          // Whole-word-ish: `entries` must not trip on nothing, and a longer
          // legitimate word must not trip on a shorter forbidden one.
          final pattern = RegExp(
            '(^|[^a-z0-9_])${RegExp.escape(word)}([^a-z0-9_]|\$)',
          );
          if (!pattern.hasMatch(lower)) continue;
          offences.add('$path:${i + 1}  "$word"  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason:
          'The previous product model is back in ${offences.length} place(s). '
          'Use Collection / Entry / Page, and Save rather than Capture or '
          'Download. If a word genuinely has an unrelated technical meaning, '
          'add it to `allowed` in this file with the reason.\n\n'
          '${offences.take(40).join('\n')}',
    );
  });

  test('no file names a third-party website', () {
    // A provider catalogue is a catalogue however it is spelled. The app must
    // ship no hostname, in code, tests, docs, fixtures or platform metadata,
    // beyond the reserved example domains and the developer's own.
    const allowedHosts = [
      // RFC 2606 / RFC 6761 reserved names, plus the loopback the in-process
      // fixture server binds to. None of these is a real website.
      'example',
      'example.com',
      'example.test',
      'example.org',
      'invalid',
      'localhost',
      '127.0.0.1',
      'flutter.dev',
      'dart.dev',
      'pub.dev',
      'github.com',
      'developer.apple.com',
      'support.google.com',
      'play.google.com',
      'schema.org',
      'apache.org',
      'opensource.org',
      'scripts.sil.org',
      'drift.simonbinder.eu',
      'gradle.org',
      'maven.apache.org',
      'kotlinlang.org',
      'w3.org',
      'json-schema.org',
      'openssl.org',
      'sqlite.org',
      // Platform boilerplate Flutter and the toolchains generate.
      'apple.com',
      'android.com',
      'chromium.org',
      // The URL bar's default search provider. A *search engine* is not a
      // content provider and not a "supported site": it is where prose typed
      // into an address bar goes, exactly as in any browser, and it is never a
      // source the app saves from. Flagged for review all the same — making the
      // provider user-selectable would remove the only third-party name in the
      // build. See docs/STORE_POLICY_MAP.md R8.
      'google.com',
    ];
    // Markdown links in the docs to the official policy pages are references,
    // not site support — they are matched and then allowed by host below.
    final hostPattern = RegExp(
      r'https?://([a-z0-9-]+(?:\.[a-z0-9-]+)+)',
      caseSensitive: false,
    );

    // Files that name restricted hosts in order to refuse them. The policy
    // itself holds bare domains with no scheme, so it never matches the
    // pattern below; its test writes whole addresses, because matching has to
    // be exercised against the shape a real URL takes.
    const restrictionPolicyFiles = [
      'test/repository_cleanliness_test.dart',
      'lib/save/capture_policy.dart',
      'test/capture_policy_test.dart',
      'test/capture_restriction_test.dart',
      // Proves the policy stops at the page boundary: an asset served from a
      // restricted host is still fetched. Naming such a host is the only way to
      // assert that, and every request in it is answered by a fake adapter.
      'test/asset_host_policy_test.dart',
    ];

    final offences = <String>[];
    for (final file in files) {
      final path = file.path.replaceFirst('${Directory.current.path}/', '');
      if (restrictionPolicyFiles.contains(path)) continue;
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in hostPattern.allMatches(lines[i])) {
          final host = m.group(1)!.toLowerCase();
          final bare = host.startsWith('www.') ? host.substring(4) : host;
          if (allowedHosts.any((a) => bare == a || bare.endsWith('.$a'))) {
            continue;
          }
          offences.add('$path:${i + 1}  $host');
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason:
          'A third-party hostname is referenced in ${offences.length} '
          'place(s). The app has no supported-site list, no provider catalogue '
          'and no site-specific behaviour; fixtures and docs use the reserved '
          'example domains.\n\n${offences.take(40).join('\n')}',
    );
  });

  test('no production file names a hostname-specific condition', () {
    // Stronger than the scan above, and scoped to shipped code: a comparison
    // against a literal host is the shape a site catalogue takes when it is not
    // called one.
    // A *literal* host on either side of a comparison. `a.host == b.host` is
    // ordinary code; `host == 'somewhere.example'` is a site catalogue with one row.
    final suspicious = RegExp(
      "host\\s*==\\s*['\"][a-z0-9-]+\\.[a-z]{2,}|"
      "['\"][a-z0-9-]+\\.[a-z]{2,}['\"]\\s*==\\s*[a-z]*host|"
      "hostAllow|hostDeny|knownHosts|supportedHosts|siteRules",
      caseSensitive: false,
    );
    final offences = <String>[];
    for (final file in files) {
      final path = file.path.replaceFirst('${Directory.current.path}/', '');
      if (!path.startsWith('lib/')) continue;
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (suspicious.hasMatch(lines[i])) {
          offences.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });

  test('the restricted-site policy exists in exactly one place', () {
    // The one allowance above is worth exactly as much as this guard. A second
    // copy of the list — in the Browser, the queue, a screen or a document —
    // is how the two drift apart until the UI hides a control the engine still
    // honours, or the reverse. Every capture boundary must import the policy
    // and ask it; none may hold its own.
    const home = 'lib/save/capture_policy.dart';
    const constants = ['restrictedCaptureDomains', 'restrictedCaptureHosts'];

    for (final name in constants) {
      final declaring = <String>[];
      for (final file in files) {
        final path = file.path.replaceFirst('${Directory.current.path}/', '');
        if (!path.startsWith('lib/')) continue;
        // The declaration, not a use: `const <name> = <String>{`.
        if (RegExp('const\\s+$name\\s*=').hasMatch(file.readAsStringSync())) {
          declaring.add(path);
        }
      }
      expect(
        declaring,
        [home],
        reason:
            '`$name` must be declared in $home and nowhere else. A capture '
            'boundary enforces the policy by importing it, never by keeping '
            'its own copy.',
      );
    }
  });
}
