import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/bridge_script.dart';

/// A guard on the browser half, which no test in this suite can execute.
///
/// The entry-number corruption did not start in Dart. It started with
/// `a.textContent`, which concatenates a row's elements with no separator, so
/// `<span>Entry 101</span><span>2 weeks ago</span>` arrived as
/// `"Entry 1012 weeks ago"` — two visible strings welded into one number that
/// was never on the page. Every Dart test downstream was given a plausible
/// string and had no way to know it was wrong.
///
/// There is no JavaScript runtime here, so behaviour cannot be asserted. What
/// can be asserted is that the reading has not quietly reverted: `textContent`
/// is allowed only where it is not being used to *name* something, and every
/// remaining use is listed below with the reason it is not a label.
void main() {
  /// Uses of `textContent` that are not an element's visible label.
  ///
  /// Keyed by the fragment that must appear on the line; the value is why it
  /// is not the defect. A new use that is not on this list fails the test —
  /// which is the point, because the next one will look just as harmless.
  const allowed = <String, String>{
    "return el.textContent || '';":
        'the fallback inside joinTextNodes, when a TreeWalker cannot be made',
    'score += (kids[k].textContent':
        'a length-only density score; no label is read out of it',
    'JSON.parse(lds[li].textContent':
        'JSON-LD source text — inserting separators would corrupt the JSON',
    'style.textContent =': 'a write, not a read',
    'var legacy = (a.textContent':
        'the deliberate second comparison that keeps hints taught before '
        'elementText existed matching',
    '// `Node.textContent` concatenates':
        'the comment explaining why the rest of this list is short',
  };

  test('the boundary-preserving reader exists', () {
    expect(kBridgePreamble, contains('function elementText(el)'));
    expect(kBridgePreamble, contains('function joinTextNodes(el)'));
    expect(
      kBridgePreamble,
      contains('el.innerText'),
      reason:
          'innerText is the reading that separates block siblings while '
          'keeping inline formatting welded — the distinction no tag list can '
          'make, because the same <span> does both jobs',
    );
  });

  test('nothing reads an element label with raw textContent', () {
    final offences = <String>[];
    final lines = kBridgePreamble.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('textContent')) continue;
      if (allowed.keys.any(lines[i].contains)) continue;
      offences.add('line ${i + 1}: ${lines[i].trim()}');
    }

    expect(
      offences,
      isEmpty,
      reason:
          'A new raw `textContent` read is in the bridge. If it names '
          'something a person sees — a link, a heading, a breadcrumb — use '
          '`elementText`, or two adjacent elements will weld into one number '
          'again. If it genuinely is not a label, add it to `allowed` in this '
          'file with the reason.\n\n${offences.join('\n')}',
    );
  });

  test('the paths that name things go through elementText', () {
    // Named individually rather than counted: a count passes for the wrong
    // reason the moment one of these is deleted.
    for (final site in [
      'text: elementText(a).slice(0, 120)', // link labels — the reported bug
      'text: elementText(crumbNodes[j])', // breadcrumb trail
      'h1: elementText(h1)', // the page's own heading
      'headingText: elementText(document.querySelector', // content signals
      'text: elementText(el).slice(0, 120)', // a user-taught element
      'parseInt(elementText(pageLinks[pi])', // pager numbers
      'title: elementText(h1)', // a saved document's title
    ]) {
      expect(
        kBridgePreamble,
        contains(site),
        reason: 'this reading names something and must preserve boundaries',
      );
    }
  });

  test('visibleText walks nodes rather than trusting innerText', () {
    // It reads a detached clone with the furniture removed, and a detached
    // element is not rendered — so innerText there degrades to exactly the
    // glued reading this whole change exists to remove.
    expect(kBridgePreamble, contains('return joinTextNodes(clone)'));
  });
}
