import '../browser/page_data.dart';
import '../core/url_utils.dart';
import 'page_hint.dart';

/// Ordered by trust. The chain takes the first strategy that yields a
/// candidate surviving validation; every candidate considered is reported so a
/// wrong pick is diagnosable rather than mysterious.
enum NextStrategy {
  /// A rule the user created by pointing at the control.
  savedHint,
  headRelNext,
  anchorRelNext,

  /// A next-ish label inside an entry-navigation container.
  navContainer,

  /// A next-ish label anywhere on the page.
  labelledControl,

  /// Same collection path, entry number one higher. Corroboration only.
  numberProgression,
}

extension NextStrategyInfo on NextStrategy {
  int get rank => index;

  NextConfidence get baseConfidence => switch (this) {
    NextStrategy.savedHint => NextConfidence.high,
    NextStrategy.headRelNext => NextConfidence.high,
    NextStrategy.anchorRelNext => NextConfidence.high,
    NextStrategy.navContainer => NextConfidence.medium,
    NextStrategy.labelledControl => NextConfidence.medium,
    NextStrategy.numberProgression => NextConfidence.low,
  };

  String get label => switch (this) {
    NextStrategy.savedHint => 'saved rule',
    NextStrategy.headRelNext => 'link[rel=next]',
    NextStrategy.anchorRelNext => 'a[rel=next]',
    NextStrategy.navContainer => 'nav container',
    NextStrategy.labelledControl => 'labelled control',
    NextStrategy.numberProgression => 'entry progression',
  };
}

enum NextConfidence { high, medium, low }

/// Text signals for a "next" control.
///
/// Hints, not a dictionary. Detection must work on a page in a language that
/// is not listed here — that is what `rel`, nav containers, href shape and the
/// user-assisted fallback are for. Extend freely; do not try to be complete.
const List<String> kNextTextHints = [
  // English
  'next entry', 'next entry', 'next page', 'next part', 'next', 'continue',
  // Turkish
  'sonraki bölüm', 'sonraki bolum', 'sonraki', 'ileri', 'devam',
  // German
  'nächstes kapitel', 'naechstes kapitel', 'nächste seite', 'nächste',
  'naechste', 'weiter',
  // A few more, as hints only
  'siguiente', 'próximo', 'proximo', 'suivant', '次へ', '다음화', '다음', '下一章',
];

/// Look like "next" but are not entry navigation.
const List<String> kNextTextDenyHints = [
  'next collection',
  'next season',
  'next comment',
  'next post',
  'next video',
  'next week',
  'sonraki seri',
  'nächste serie',
];

class NextCandidate {
  const NextCandidate({
    required this.href,
    required this.strategy,
    required this.evidence,
    this.confidence,
  });

  final String href;
  final NextStrategy strategy;

  /// What matched, for the diagnostics log and for the selection UI.
  final String evidence;

  /// Set once the whole candidate set has been weighed.
  final NextConfidence? confidence;

  NextCandidate withConfidence(NextConfidence c) => NextCandidate(
    href: href,
    strategy: strategy,
    evidence: evidence,
    confidence: c,
  );
}

/// What the save loop should do next.
enum NextDecision {
  /// Confident enough to navigate without asking.
  proceed,

  /// Something was found, but not confidently — ask the user to point at the
  /// real control rather than guessing.
  askUser,

  /// Nothing plausible at all: end of chain.
  endOfChain,
}

class NextPageResult {
  const NextPageResult({
    required this.decision,
    required this.considered,
    this.chosen,
    this.rejection,
    this.reason = '',
  });

  final NextDecision decision;
  final List<NextCandidate> considered;
  final NextCandidate? chosen;
  final NextUrlRejection? rejection;
  final String reason;

  bool get hasNext => chosen != null && decision == NextDecision.proceed;
  bool get needsUserSelection => decision == NextDecision.askUser;
}

/// Collect next-page candidates, best strategy first.
///
/// URL-number incrementing is present only as [NextStrategy.numberProgression]
/// and is never trusted on its own: fabricating a URL the page never asserted
/// produces phantom entries, which corrupt the library rather than merely
/// failing. It can only corroborate a link that actually exists.
List<NextCandidate> collectNextCandidates(
  PageProbe probe, {
  String? hintHref,
  String? currentUrl,
}) {
  final candidates = <NextCandidate>[];

  if (hintHref != null && hintHref.trim().isNotEmpty) {
    candidates.add(
      NextCandidate(
        href: hintHref,
        strategy: NextStrategy.savedHint,
        evidence: 'saved site rule',
      ),
    );
  }

  final headNext = probe.headNextHref;
  if (headNext != null && headNext.trim().isNotEmpty) {
    candidates.add(
      NextCandidate(
        href: headNext,
        strategy: NextStrategy.headRelNext,
        evidence: 'link[rel=next]',
      ),
    );
  }

  for (final link in probe.links) {
    if (link.href.trim().isEmpty) continue;

    if (link.rel.split(RegExp(r'\s+')).contains('next')) {
      candidates.add(
        NextCandidate(
          href: link.href,
          strategy: NextStrategy.anchorRelNext,
          evidence: 'a[rel=next]',
        ),
      );
      continue;
    }

    final match = matchNextText(link);
    if (match != null) {
      candidates.add(
        NextCandidate(
          href: link.href,
          strategy: link.inNav
              ? NextStrategy.navContainer
              : NextStrategy.labelledControl,
          evidence: match,
        ),
      );
    }
  }

  // Entry progression: a link on the page whose path matches this collection and
  // whose number is exactly one higher. Corroboration for an existing link,
  // never a fabricated URL.
  if (currentUrl != null) {
    final progression = _entryProgressionCandidates(probe, currentUrl);
    candidates.addAll(progression);
  }

  candidates.sort((a, b) => a.strategy.rank.compareTo(b.strategy.rank));
  return candidates;
}

/// Links that sit in the same collection and carry the next entry number.
List<NextCandidate> _entryProgressionCandidates(
  PageProbe probe,
  String currentUrl,
) {
  final currentNumber = entryNumberIn(currentUrl);
  if (currentNumber == null) return const [];
  final collection = collectionFingerprint(currentUrl);

  final out = <NextCandidate>[];
  for (final link in probe.links) {
    if (link.href.trim().isEmpty) continue;
    if (collectionFingerprint(link.href) != collection) continue;
    final n = entryNumberIn(link.href);
    if (n == null || n != currentNumber + 1) continue;
    out.add(
      NextCandidate(
        href: link.href,
        strategy: NextStrategy.numberProgression,
        evidence: 'same collection, entry ${currentNumber + 1}',
      ),
    );
  }
  return out;
}

/// Last number in the final path segment, which is where entry numbers live
/// on every layout seen so far (`/883-part`, `/entry/101`, `/c/12.5`).
int? entryNumberIn(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.pathSegments.isEmpty) return null;
  for (final segment in uri.pathSegments.reversed) {
    final match = RegExp(r'(\d+)').firstMatch(segment);
    if (match != null) return int.tryParse(match.group(1)!);
  }
  return null;
}

/// Short hints must match as whole words.
///
/// Observed on a real page: the Turkish hint `ileri` matched inside
/// "anime oner**ileri**" ("anime recommendations"), offering three unrelated
/// links as next-entry candidates. Only same-host validation stopped them.
/// Substring matching is fine for a distinctive multi-word hint and dangerous
/// for a short one.
bool _hintMatches(String value, String hint) {
  if (hint.length >= 6 || hint.contains(' ')) return value.contains(hint);
  final escaped = RegExp.escape(hint);
  // Unicode-aware-ish boundary: not preceded/followed by a letter or digit.
  return RegExp(
    '(^|[^\\p{L}\\p{N}])$escaped(\$|[^\\p{L}\\p{N}])',
    unicode: true,
  ).hasMatch(value);
}

String? matchNextText(PageLink link) {
  final haystacks = <String, String>{
    'text': link.text,
    'aria-label': link.ariaLabel,
    'title': link.title,
    'img-alt': link.imgAlt,
    'class': link.className,
    'id': link.id,
  };

  for (final entry in haystacks.entries) {
    final value = entry.value.toLowerCase().trim();
    if (value.isEmpty) continue;
    if (kNextTextDenyHints.any(value.contains)) continue;

    for (final hint in kNextTextHints) {
      if (!_hintMatches(value, hint)) continue;
      // A paragraph that merely contains the word is not a control.
      if (entry.key == 'text' && value.length > hint.length + 24) continue;
      return '${entry.key}="${entry.value}" ~ "$hint"';
    }
  }
  return null;
}

/// Run the chain, validate, and decide whether to proceed or ask the user.
///
/// The rule: proceed on a high-confidence candidate, or on a medium-confidence
/// one that no other candidate contradicts. Ask the user when the best signal
/// is weak or when two plausible candidates point at different pages — a wrong
/// automatic pick walks the run into the wrong collection, which is worse than a
/// prompt.
NextPageResult resolveNextPage(
  PageProbe probe, {
  required String currentUrl,
  required Set<String> visitedNormalized,
  String? hintHref,
  bool allowCrossHost = false,
  bool allowUserAssist = true,
}) {
  final considered = collectNextCandidates(
    probe,
    hintHref: hintHref,
    currentUrl: currentUrl,
  );

  // Validate first: an invalid candidate should not create ambiguity.
  final viable = <NextCandidate>[];
  NextUrlRejection? firstRejection;
  for (final candidate in considered) {
    final check = validateNextUrl(
      candidate: candidate.href,
      currentUrl: currentUrl,
      visited: visitedNormalized,
      allowCrossHost: allowCrossHost,
    );
    if (check.isAccepted) {
      viable.add(
        NextCandidate(
          href: check.normalized!,
          strategy: candidate.strategy,
          evidence: candidate.evidence,
        ),
      );
    } else {
      firstRejection ??= check.rejection;
    }
  }

  if (viable.isEmpty) {
    return NextPageResult(
      decision: NextDecision.endOfChain,
      considered: considered,
      rejection: firstRejection,
      reason: considered.isEmpty
          ? 'no candidates on the page'
          : 'every candidate was rejected (${firstRejection?.name})',
    );
  }

  final best = viable.first;
  var confidence = best.strategy.baseConfidence;

  // Corroboration: a distinct strategy agreeing on the same URL raises a
  // medium signal to high.
  final agreeing = viable.where((c) => c.href == best.href).length;
  if (confidence == NextConfidence.medium && agreeing > 1) {
    confidence = NextConfidence.high;
  }

  // Contradiction: any other plausible candidate pointing somewhere else means
  // we do not actually know. Compared against the *base* confidence, not the
  // corroborated one — otherwise lifting the winner to high would silence a
  // medium-confidence rival and we would walk into the wrong page confidently.
  // Compared against the winner's *base* confidence, not the corroborated one:
  // lifting the winner to high must not silence a medium-confidence rival that
  // points somewhere else. A weaker candidate disagreeing is not ambiguity.
  final competing = viable
      .where(
        (c) =>
            c.href != best.href &&
            c.strategy.baseConfidence.index <=
                best.strategy.baseConfidence.index,
      )
      .toList();

  final decided = best.withConfidence(confidence);

  // A saved rule is authoritative. The user pointed at this control; competing
  // page heuristics do not get to re-open the question, or saving a rule would
  // not actually stop the prompts.
  if (best.strategy == NextStrategy.savedHint) {
    return NextPageResult(
      decision: NextDecision.proceed,
      considered: considered,
      chosen: decided,
      reason: 'saved rule (user-selected)',
    );
  }

  if (confidence == NextConfidence.high && competing.isEmpty) {
    return NextPageResult(
      decision: NextDecision.proceed,
      considered: considered,
      chosen: decided,
      reason: 'high confidence via ${best.strategy.label}',
    );
  }
  if (confidence == NextConfidence.medium && competing.isEmpty) {
    return NextPageResult(
      decision: NextDecision.proceed,
      considered: considered,
      chosen: decided,
      reason: 'medium confidence, uncontested, via ${best.strategy.label}',
    );
  }

  if (!allowUserAssist) {
    return NextPageResult(
      decision: NextDecision.proceed,
      considered: considered,
      chosen: decided,
      reason: 'best effort (user assist disabled)',
    );
  }

  return NextPageResult(
    decision: NextDecision.askUser,
    considered: considered,
    chosen: decided,
    reason: competing.isNotEmpty
        ? '${competing.length + 1} candidates disagree '
              '(${best.strategy.label} vs ${competing.first.strategy.label})'
        : 'only a ${confidence.name}-confidence signal '
              '(${best.strategy.label})',
  );
}
