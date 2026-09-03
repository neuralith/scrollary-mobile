import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/bridge_script.dart';

/// A guard on the browser half of the prose measurement, which no test in this
/// suite can execute.
///
/// The behaviour is proved on a live WebView by
/// `integration_test/text_capture_test.dart` ("a page whose only words are
/// furniture is not an article"). What is proved *here* is that the two
/// readings which caused the failure have not quietly come back — because both
/// of them looked entirely reasonable, and the page they broke gave no sign
/// that anything had been measured wrongly. It failed saying it had no
/// readable text, which was true, and said nothing about the 132 images it
/// had just decided not to look at.
///
/// Same technique, and the same limits, as `bridge_element_text_test.dart`.
void main() {
  test('prose is measured with page furniture excluded', () {
    expect(
      kBridgePreamble,
      contains('function proseSignals(root)'),
      reason:
          'textLength and paragraphCount are one measurement over the blocks '
          'document_extraction keeps, so the signals and the extraction '
          'cannot disagree about whether a page has anything to read',
    );
    expect(
      kBridgePreamble,
      contains('textLength: prose.length'),
      reason:
          'textLength was the whole readable region — which is document.body '
          'on any page that declares no <article>, no <main> and no dense '
          'paragraph container, so it counted the site menus as prose',
    );
    expect(
      kBridgePreamble,
      contains('paragraphCount: prose.paragraphs'),
      reason: 'paragraphCount is the <p> elements behind that measurement',
    );
    expect(
      kBridgePreamble,
      isNot(contains("'article p, main p, [role=main] p, p'")),
      reason:
          'that selector ends in a bare `p`, so the union it looks like is '
          'really every paragraph in the document, furniture and all — a '
          'page whose only paragraphs are its own login form counted 23 of '
          'them and read as an article',
    );
  });

  test('a negated state class does not declare page furniture', () {
    expect(
      kBridgePreamble,
      contains('CHROME_DENIED'),
      reason:
          '`sidebar-hidden` is the class a theme puts on the column that is '
          'left when the sidebar is gone — on the MAIN column. Matched as a '
          'declaration it makes the readable half of the page furniture, and '
          'with it every block, every prose character and every '
          'content-region image on the page',
    );
    expect(
      kBridgePreamble,
      contains('function tokenIsChrome(token)'),
      reason:
          'the denial is judged per class token, against what surrounds the '
          'matched word inside that one token — `visually-hidden`, where '
          '"hidden" IS the vocabulary word, has to keep matching',
    );
    expect(
      kBridgePreamble,
      contains(
        "if (el.tagName === 'BODY' || el.tagName === 'HTML') "
        'return false;',
      ),
      reason:
          'the document root holds the page and cannot be furniture inside '
          'it — themes park options like `header-style-1` on <body>, which '
          'would otherwise make every element on the page furniture at once',
    );
  });
}
