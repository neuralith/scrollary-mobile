// Text-shaped fixture pages, for exercising the capture modes deterministically.
//
// Reserved example domains only, generic markup only. The point is to exercise
// the detector's *rules* against structures the whole web shares — an article
// landmark, a nav, an aside, a comments section — not to imitate any website.
//
// Kept beside the image-sequence fixture rather than inside it: these describe
// a different shape of page and the file was already long.

/// Enough prose to clear the readable floor, with real structure around it.
String _proseBody(int n) {
  const sentence =
      'The quick brown fox jumps over the lazy dog, and then it does so '
      'again, because that is what the sentence is for. ';
  final paragraphs = <String>[];
  for (var i = 1; i <= 6; i++) {
    paragraphs.add('<p>Paragraph $i of entry $n. ${sentence * 3}</p>');
  }
  return paragraphs.join('\n  ');
}

/// A prose page, optionally with inline figures inside the readable region.
///
/// Every shape the extractor is supposed to drop is present on purpose: a
/// header, a nav, a footer, an aside of recommendations, a comments section, a
/// display:none note and a tracking-pixel-sized image. A save of this page
/// that keeps any of them is a bug the fixture can prove.
String textEntryPage(
  int n, {
  required int entryCount,
  required bool withImages,
}) {
  final route = withImages ? 'textimages' : 'text';
  final next = n < entryCount
      ? '<link rel="next" href="/$route/${n + 1}">'
      : '';
  final prev = n > 1 ? '<link rel="prev" href="/$route/${n - 1}">' : '';
  final nextAnchor = n < entryCount
      ? '<a rel="next" href="/$route/${n + 1}">Next</a>'
      : '';

  final figures = withImages
      ? '<figure>'
            '<img src="/figure/$n/1.png?w=640&amp;h=420" width="640" height="420" '
            'alt="The first figure">'
            '<figcaption>A caption for the first figure.</figcaption>'
            '</figure>'
            '<p>Text between the figures. The quick brown fox jumps over '
            'the lazy dog once more, at length.</p>'
            '<figure>'
            '<img src="/figure/$n/2.png?w=640&amp;h=420" width="640" height="420" '
            'alt="The second figure">'
            '</figure>'
      : '';

  return '<!doctype html><html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '$next$prev'
      '<title>Fixture text entry $n</title></head>'
      '<body>'
      '<header class="site-header"><p>A site header that must not be '
      'saved.</p></header>'
      '<nav aria-label="Main"><a href="/">Home</a> '
      '<a href="/$route/1">First</a></nav>'
      '<main><article>'
      '<h1>Fixture text entry $n</h1>'
      '<p class="byline">By a fixture</p>'
      '${_proseBody(n)}'
      '<h2>A subheading</h2>'
      '<blockquote>Something a fixture said, at some length, so that the '
      'quote block has a body worth keeping.</blockquote>'
      '<ul><li>An unordered point</li><li>Another unordered point</li></ul>'
      '<ol><li>An ordered point</li></ol>'
      '<hr>'
      '<p>A closing paragraph with <strong>bold</strong> and <em>italic</em> '
      'text in it.</p>'
      '$figures'
      '<img src="/figure/$n/9.png?w=1&amp;h=1" width="1" height="1" '
      'alt="A tracking pixel">'
      '<p class="visually-hidden" style="display:none">A hidden note that '
      'must not be saved.</p>'
      '</article></main>'
      '<aside class="related"><h3>Recommended</h3>'
      '<img src="/figure/$n/8.png?w=300&amp;h=300" width="300" height="300" '
      'alt="A recommendation"></aside>'
      '<section class="comments"><h3>Comments</h3>'
      '<p>A comment that must not be saved.</p></section>'
      '<footer><p>A footer that must not be saved.</p></footer>'
      '$nextAnchor'
      '</body></html>';
}

/// A page that **is** its video: one player filling most of the viewport, with
/// no readable article around it.
///
/// The `<video>` element deliberately carries no source. Nothing in the app
/// reads a media URL, so the fixture does not provide one to read — what is
/// under test is the geometry that makes this page classify as video, and the
/// refusal that follows.
String videoPage() =>
    '<!doctype html><html lang="en"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<title>Fixture video page</title>'
    '<style>body{margin:0}'
    'video{display:block;width:100vw;height:60vh;background:#222}</style>'
    '</head><body><main>'
    '<video controls></video>'
    '<h1>Fixture video page</h1>'
    '<p>A short caption. Not an article.</p>'
    '</main>'
    '<aside class="related">'
    '<img src="/figure/1/1.png?w=300&amp;h=300" width="300" height="300" '
    'alt="A thumbnail">'
    '<img src="/figure/1/2.png?w=300&amp;h=300" width="300" height="300" '
    'alt="Another thumbnail">'
    '</aside></body></html>';

/// Short text and two mid-sized images: not enough of either to be confident.
/// The save sheet must offer the alternatives without claiming an answer.
String ambiguousPage() =>
    '<!doctype html><html lang="en"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<title>Fixture ambiguous page</title></head><body>'
    '<div class="wrap">'
    '<h1>Fixture ambiguous page</h1>'
    '<p>One short paragraph, which is not enough prose to be an article.</p>'
    '<img src="/figure/1/1.png?w=420&amp;h=320" width="420" height="320" '
    'alt="One">'
    '<img src="/figure/1/2.png?w=420&amp;h=320" width="420" height="320" '
    'alt="Two">'
    '</div></body></html>';
