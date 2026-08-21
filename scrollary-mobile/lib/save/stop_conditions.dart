/// Why a multi-entry save run stops, and how each condition is recognised.
///
/// This file is the app's answer to "does it bypass anything". It only ever
/// *detects* and *stops*. There is no retry-with-different-headers, no
/// alternate-URL attempt, no cookie manipulation, no header spoofing and no
/// waiting-out of a rate limit anywhere in the codebase — a stop is final for
/// that run, it is named, and the user is told which condition it was.
///
/// Pure Dart over the probe signals, so each rule is unit-testable against a
/// literal fixture and none of them can accidentally acquire a hostname check.
library;

import '../browser/page_data.dart';
import '../core/url_utils.dart';

/// The complete set of reasons automatic continuation ends.
///
/// Every terminal save run records one of these. "Finished" and "was stopped by
/// the site" must never be reported as the same outcome, which is why this is a
/// column and not a log line.
enum StopReason {
  // --- the run did what it was asked ---------------------------------------
  /// The user's entry-count ceiling was reached.
  userLimitReached,

  /// The user's storage ceiling was reached.
  storageLimitReached,

  /// The user picked specific items and they are all saved.
  selectionComplete,

  /// No next page was found. The honest end of a chain.
  noNextPage,

  // --- the site said no. Detected, never worked around. --------------------
  authenticationRequired,
  paywallDetected,
  captchaDetected,
  accessDenied,
  rateLimited,

  // --- the structure stopped making sense ----------------------------------
  /// Navigation left the origin the run started on, without approval.
  crossOrigin,

  /// The same address came round again.
  repeatedUrl,

  /// A different address serving a document we already have (canonical match).
  navigationLoop,

  /// The next page is not something this app can read.
  unsupportedContent,

  /// A continuation candidate existed but was too weak to follow unattended.
  lowConfidence,

  /// The page shape changed enough that continuing would save the wrong thing.
  structureChanged,

  // --- this app's own policy -----------------------------------------------
  /// The address is on a commercial content service this app does not save
  /// from. Not something the *site* did — the app withheld capture, from a
  /// static host list it maintains itself. See `save/capture_policy.dart`.
  captureRestrictedForSite,

  // --- device and user -----------------------------------------------------
  insufficientStorage,
  cancelledByUser,
  interrupted;

  static StopReason? fromName(String? name) => name == null
      ? null
      : StopReason.values.where((r) => r.name == name).firstOrNull;

  /// True when the *site* stopped us, as opposed to the user, the device or the
  /// end of the content.
  bool get isAccessGate =>
      this == StopReason.authenticationRequired ||
      this == StopReason.paywallDetected ||
      this == StopReason.captchaDetected ||
      this == StopReason.accessDenied ||
      this == StopReason.rateLimited;

  /// True when the run genuinely did what it was asked to do.
  bool get isSuccess =>
      this == StopReason.userLimitReached ||
      this == StopReason.storageLimitReached ||
      this == StopReason.selectionComplete ||
      this == StopReason.noNextPage;

  /// One sentence for the user. Plain, specific and never suggests a workaround.
  String get message => switch (this) {
    StopReason.userLimitReached => 'Reached the limit you set.',
    StopReason.storageLimitReached => 'Reached the storage limit you set.',
    StopReason.selectionComplete => 'Saved everything you selected.',
    StopReason.noNextPage => 'No next page was found, so this is the end.',
    StopReason.authenticationRequired =>
      'Stopped: the site asked for a sign-in. Sign in yourself in the Browser '
          'if you have an account, then start again from that page.',
    StopReason.paywallDetected =>
      'Stopped: this page is behind a paywall. The app does not work around '
          'paywalls.',
    StopReason.captchaDetected =>
      'Stopped: the site showed a human-verification check. Complete it '
          'yourself in the Browser if you want to continue.',
    StopReason.accessDenied =>
      'Stopped: the site refused access to the next page.',
    StopReason.rateLimited =>
      'Stopped: the site asked for fewer requests. Try again later.',
    StopReason.crossOrigin =>
      'Stopped: the next page is on a different website.',
    StopReason.repeatedUrl => 'Stopped: that page had already been saved.',
    StopReason.navigationLoop =>
      'Stopped: the pages started repeating themselves.',
    StopReason.unsupportedContent =>
      'Stopped: the next page is not something this app can read offline.',
    StopReason.lowConfidence =>
      'Stopped: it was not clear which link continues the sequence.',
    StopReason.structureChanged =>
      'Stopped: the page layout changed, so continuing might have saved the '
          'wrong thing.',
    // Neutral and factual. It says what the app does; it never characterises
    // what the user was trying to do.
    StopReason.captureRestrictedForSite =>
      'Saving isn’t available on this '
          'site.',
    StopReason.insufficientStorage =>
      'Stopped: not enough space on the device. Nothing already saved was '
          'affected.',
    StopReason.cancelledByUser => 'Stopped at your request.',
    StopReason.interrupted => 'Interrupted before it finished.',
  };

  /// Short label for the Activity row.
  String get shortLabel => switch (this) {
    StopReason.userLimitReached => 'Limit reached',
    StopReason.storageLimitReached => 'Storage limit reached',
    StopReason.selectionComplete => 'Selection complete',
    StopReason.noNextPage => 'End of sequence',
    StopReason.authenticationRequired => 'Sign-in required',
    StopReason.paywallDetected => 'Paywall',
    StopReason.captchaDetected => 'Verification check',
    StopReason.accessDenied => 'Access denied',
    StopReason.rateLimited => 'Rate limited',
    StopReason.crossOrigin => 'Different website',
    StopReason.repeatedUrl => 'Already saved',
    StopReason.navigationLoop => 'Loop detected',
    StopReason.unsupportedContent => 'Unsupported page',
    StopReason.lowConfidence => 'Unclear next page',
    StopReason.structureChanged => 'Layout changed',
    StopReason.captureRestrictedForSite => 'Saving unavailable here',
    StopReason.insufficientStorage => 'Out of space',
    StopReason.cancelledByUser => 'Stopped',
    StopReason.interrupted => 'Interrupted',
  };
}

/// The result of inspecting a page before saving it.
class GateCheck {
  const GateCheck({this.reason, this.evidence = ''});

  const GateCheck.clear() : reason = null, evidence = '';

  /// Null when the page is fine to save.
  final StopReason? reason;
  final String evidence;

  bool get isBlocked => reason != null;
}

/// Does this page show an access gate?
///
/// The ordering is by how specific the evidence is. A structural signal (an
/// actual password input, an actual CAPTCHA widget, a `isAccessibleForFree=False`
/// declaration) stands on its own. A *phrase* never does: a page that mentions
/// "subscribe to continue" in its footer is not a paywall, and treating it as
/// one would stop half the web at random. A phrase counts only when the document
/// is otherwise empty — which is what a real interstitial looks like.
GateCheck detectAccessGate(PageAccessSignals access) {
  if (access.hasCaptchaWidget) {
    return const GateCheck(
      reason: StopReason.captchaDetected,
      evidence: 'a human-verification widget is present',
    );
  }
  if (access.hasPasswordField || access.hasLoginForm) {
    return GateCheck(
      reason: StopReason.authenticationRequired,
      evidence: access.hasPasswordField
          ? 'a password field is present'
          : 'a sign-in form is present',
    );
  }
  if (access.hasPaywallMarker) {
    return const GateCheck(
      reason: StopReason.paywallDetected,
      evidence: 'the page declares its content is not free',
    );
  }

  // Phrase hints, corroborated only.
  if (access.isEmptyDocument) {
    if (access.ratePhrase != null) {
      return GateCheck(
        reason: StopReason.rateLimited,
        evidence: 'near-empty page mentioning "${access.ratePhrase}"',
      );
    }
    if (access.deniedPhrase != null) {
      return GateCheck(
        reason: StopReason.accessDenied,
        evidence: 'near-empty page mentioning "${access.deniedPhrase}"',
      );
    }
    if (access.authPhrase != null) {
      return GateCheck(
        reason: StopReason.authenticationRequired,
        evidence: 'near-empty page mentioning "${access.authPhrase}"',
      );
    }
    if (access.paywallPhrase != null) {
      return GateCheck(
        reason: StopReason.paywallDetected,
        evidence: 'near-empty page mentioning "${access.paywallPhrase}"',
      );
    }
  }

  return const GateCheck.clear();
}

/// Would following [candidate] leave the origin the run started on?
///
/// Origin, not host: `http` → `https` and a port change are different origins
/// for cookies, and a save run that silently crosses one is a save run that
/// might be reading a different site's copy of the content.
///
/// [approvedOrigins] is the user's explicit consent, given per run. It starts
/// empty on every run — a host the user allowed while browsing is not thereby
/// allowed for unattended navigation.
GateCheck checkOrigin({
  required String candidate,
  required String startUrl,
  Set<String> approvedOrigins = const {},
}) {
  final from = _originOf(startUrl);
  final to = _originOf(candidate);
  if (to == null) {
    return const GateCheck(
      reason: StopReason.unsupportedContent,
      evidence: 'the next address is not a web page',
    );
  }
  if (from == null || to == from || approvedOrigins.contains(to)) {
    return const GateCheck.clear();
  }
  return GateCheck(reason: StopReason.crossOrigin, evidence: '$from → $to');
}

String? _originOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host.toLowerCase()}$port';
}

/// Have we been here before?
///
/// Two independent checks, because a loop that changes the address while serving
/// the same document is the one that a URL-only guard walks straight into:
///
/// * [visitedUrls] — normalised addresses already walked this run.
/// * [visitedCanonicals] — `rel=canonical` values already seen. A site that
///   paginates with a session parameter produces a fresh URL every time and the
///   same canonical every time.
GateCheck checkRepeat({
  required String candidate,
  String? candidateCanonical,
  required Set<String> visitedUrls,
  required Set<String> visitedCanonicals,
}) {
  final key = normalizeUrl(candidate);
  if (visitedUrls.contains(key)) {
    return GateCheck(
      reason: StopReason.repeatedUrl,
      evidence: 'already walked $key this run',
    );
  }
  final canonical = candidateCanonical?.trim();
  if (canonical != null && canonical.isNotEmpty) {
    final canonicalKey = normalizeUrl(canonical);
    if (visitedCanonicals.contains(canonicalKey)) {
      return GateCheck(
        reason: StopReason.navigationLoop,
        evidence:
            'a different address serving a document already saved '
            '($canonicalKey)',
      );
    }
  }
  return const GateCheck.clear();
}

/// Has the page changed shape enough that continuing is unsafe?
///
/// The case this catches: a sequence of image-heavy pages that suddenly becomes
/// a text index, or a long document that becomes a stub. Saving those under the
/// same collection would produce a library that quietly mixes two things.
GateCheck checkStructure({
  required PageContentSignals first,
  required PageContentSignals current,
}) {
  final wasImages = first.looksImageDominant;
  final nowImages = current.looksImageDominant;
  final wasProse = first.looksProse;
  final nowProse = current.looksProse;

  if (wasImages && !nowImages && nowProse) {
    return const GateCheck(
      reason: StopReason.structureChanged,
      evidence: 'image-heavy pages gave way to a text page',
    );
  }
  if (wasProse && !nowProse && !nowImages) {
    return const GateCheck(
      reason: StopReason.structureChanged,
      evidence: 'the page no longer has readable content',
    );
  }
  return const GateCheck.clear();
}
