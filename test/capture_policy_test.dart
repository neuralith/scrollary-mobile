import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/stop_conditions.dart';

/// The restricted-site capture policy, exercised against the shape a real
/// address takes.
///
/// This file names commercial content services because refusing them is what it
/// tests. Nothing here reaches the network: every case is a literal string.
void main() {
  group('restricted domains cover the apex and every subdomain', () {
    test('the apex itself', () {
      expect(isCaptureRestricted('https://youtube.com/watch'), isTrue);
      expect(isCaptureRestricted('https://netflix.com'), isTrue);
      expect(isCaptureRestricted('https://amazon.com'), isTrue);
    });

    test('one level down', () {
      expect(isCaptureRestricted('https://www.netflix.com/title/1'), isTrue);
      expect(isCaptureRestricted('https://www.amazon.com/dp/X'), isTrue);
      expect(isCaptureRestricted('https://read.amazon.com/reader'), isTrue);
      expect(isCaptureRestricted('https://music.amazon.com/albums/1'), isTrue);
      expect(isCaptureRestricted('https://seller.amazon.com'), isTrue);
    });

    test('deeply nested', () {
      expect(
        isCaptureRestricted('https://a.b.c.d.read.amazon.com/x'),
        isTrue,
        reason: 'the rule is a suffix test, not a one-label test',
      );
      expect(
        isCaptureRestricted('https://r1---sn-x.googlevideo.com/v'),
        isTrue,
      );
    });

    test('a country domain is its own entry', () {
      expect(isCaptureRestricted('https://amazon.com.tr/dp/X'), isTrue);
      expect(isCaptureRestricted('https://www.amazon.co.jp'), isTrue);
    });
  });

  group('restricted exact hosts cover that host and nothing else', () {
    test('the host itself', () {
      expect(isCaptureRestricted('https://tv.apple.com/show/1'), isTrue);
      expect(isCaptureRestricted('https://music.apple.com/album/1'), isTrue);
      expect(isCaptureRestricted('https://books.apple.com/book/1'), isTrue);
      expect(isCaptureRestricted('https://podcasts.apple.com/p/1'), isTrue);
      expect(
        isCaptureRestricted('https://play.google.com/store/books'),
        isTrue,
      );
      expect(
        isCaptureRestricted('https://books.google.com/books?id=1'),
        isTrue,
      );
    });

    test('the parent domain stays available', () {
      expect(isCaptureRestricted('https://apple.com/newsroom'), isFalse);
      expect(isCaptureRestricted('https://www.apple.com'), isFalse);
      expect(isCaptureRestricted('https://google.com/search'), isFalse);
      expect(isCaptureRestricted('https://www.google.com'), isFalse);
      expect(isCaptureRestricted('https://naver.com'), isFalse);
      expect(isCaptureRestricted('https://kakao.com'), isFalse);
    });

    test('sibling hosts stay available', () {
      expect(isCaptureRestricted('https://developer.apple.com/x'), isFalse);
      expect(isCaptureRestricted('https://support.apple.com/en/1'), isFalse);
      expect(isCaptureRestricted('https://developers.google.com/x'), isFalse);
      expect(isCaptureRestricted('https://support.google.com/x'), isFalse);
    });

    test('a subdomain of an exact host is not covered by it', () {
      expect(
        isCaptureRestricted('https://beta.tv.apple.com/show/1'),
        isFalse,
        reason:
            'an exact-host rule is exact; widening it is a deliberate edit, '
            'not a side effect',
      );
    });

    test('publisher reading services under broad parents', () {
      expect(
        isCaptureRestricted('https://mangaplus.shueisha.co.jp/titles/1'),
        isTrue,
      );
      expect(
        isCaptureRestricted('https://kmanga.kodansha.com/title/1'),
        isTrue,
      );
      expect(isCaptureRestricted('https://comic.naver.com/webtoon'), isTrue);
      expect(isCaptureRestricted('https://series.naver.com/novel'), isTrue);
      expect(isCaptureRestricted('https://page.kakao.com/content'), isTrue);
      expect(isCaptureRestricted('https://webtoon.kakao.com/content'), isTrue);
      // The parents themselves carry a great deal of unrelated content.
      expect(isCaptureRestricted('https://shueisha.co.jp/company'), isFalse);
      expect(isCaptureRestricted('https://kodansha.com/about'), isFalse);
    });

    test('a host already covered by a domain rule is still restricted', () {
      // `music.youtube.com` sits in the exact-host set for readability; the
      // `youtube.com` domain rule is what decides, and either way the answer
      // must be the same.
      expect(isCaptureRestricted('https://music.youtube.com/watch'), isTrue);
    });
  });

  group('normalisation', () {
    test('case is irrelevant', () {
      expect(isCaptureRestricted('https://WWW.NETFLIX.COM/title'), isTrue);
      expect(isCaptureRestricted('HTTPS://YouTube.Com/watch'), isTrue);
      expect(isCaptureRestricted('https://TV.Apple.COM/show'), isTrue);
    });

    test('a trailing dot is the same host', () {
      expect(isCaptureRestricted('https://youtube.com./watch'), isTrue);
      expect(isCaptureRestricted('https://tv.apple.com./show'), isTrue);
      expect(isCaptureRestricted('https://example.org./page'), isFalse);
    });

    test('a port does not change the host', () {
      expect(isCaptureRestricted('https://youtube.com:443/watch'), isTrue);
      expect(isCaptureRestricted('http://netflix.com:8080/x'), isTrue);
      expect(isCaptureRestricted('http://example.org:8080/x'), isFalse);
    });

    test('http and https are treated the same', () {
      expect(isCaptureRestricted('http://youtube.com/watch'), isTrue);
      expect(isCaptureRestricted('https://youtube.com/watch'), isTrue);
      expect(isCaptureRestricted('http://example.org/page'), isFalse);
      expect(isCaptureRestricted('https://example.org/page'), isFalse);
    });

    test('captureHostOf reports the normalised host, or nothing', () {
      expect(
        captureHostOf('https://WWW.Example.COM./p?q=1'),
        'www.example.com',
      );
      expect(captureHostOf('https://example.com:8443/p'), 'example.com');
      expect(captureHostOf('mailto:someone@example.com'), isNull);
      expect(captureHostOf('about:blank'), isNull);
      expect(captureHostOf(''), isNull);
      expect(captureHostOf(null), isNull);
    });
  });

  group('what must never match', () {
    test('a lookalike that merely starts or ends with the name', () {
      expect(isCaptureRestricted('https://notyoutube.com/watch'), isFalse);
      expect(isCaptureRestricted('https://fakeamazon.com/dp/X'), isFalse);
      expect(isCaptureRestricted('https://myyoutube.com'), isFalse);
      expect(isCaptureRestricted('https://netflixfan.com/reviews'), isFalse);
    });

    test('a restricted name used as a subdomain of something else', () {
      expect(isCaptureRestricted('https://youtube.com.example.org/p'), isFalse);
      expect(isCaptureRestricted('https://amazon.com.example.test/p'), isFalse);
    });

    test('a restricted name inside a query string', () {
      expect(
        isCaptureRestricted('https://example.org/?target=https://youtube.com'),
        isFalse,
        reason: 'only Uri.host is examined; there is no substring matching',
      );
      expect(
        isCaptureRestricted('https://example.org/redirect?to=amazon.com'),
        isFalse,
      );
    });

    test('a restricted name inside a path', () {
      expect(isCaptureRestricted('https://example.org/youtube.com/x'), isFalse);
      expect(
        isCaptureRestricted('https://example.com/blog/netflix.com-review'),
        isFalse,
      );
    });

    test('an ordinary allowed site', () {
      expect(isCaptureRestricted('https://example.com/article'), isFalse);
      expect(
        isCaptureRestricted('https://blog.example.org/2026/a-post'),
        isFalse,
      );
      expect(isCaptureRestricted('https://example.test'), isFalse);
    });

    test('malformed and hostless addresses answer false, not true', () {
      // Not on the list is the honest answer. Every capture path already
      // refuses these for its own reasons; this function only knows hosts.
      expect(isCaptureRestricted('not a url at all'), isFalse);
      expect(isCaptureRestricted('://'), isFalse);
      expect(isCaptureRestricted('/relative/path'), isFalse);
      expect(isCaptureRestricted('https://'), isFalse);
      expect(isCaptureRestricted(''), isFalse);
      expect(isCaptureRestricted(null), isFalse);
      expect(isCaptureRestricted('file:///etc/hosts'), isFalse);
    });
  });

  group('the host-only entry point', () {
    test('takes a bare host, with the same rules', () {
      expect(isRestrictedCaptureHost('www.amazon.com'), isTrue);
      expect(isRestrictedCaptureHost('AMAZON.COM.'), isTrue);
      expect(isRestrictedCaptureHost('tv.apple.com'), isTrue);
      expect(isRestrictedCaptureHost('developer.apple.com'), isFalse);
      expect(isRestrictedCaptureHost('fakeamazon.com'), isFalse);
      expect(isRestrictedCaptureHost(''), isFalse);
      expect(isRestrictedCaptureHost(null), isFalse);
    });
  });

  group('the gate shape the save run uses', () {
    test('a restricted address blocks with the policy reason', () {
      final gate = checkCaptureSite('https://www.netflix.com/title/1');
      expect(gate.isBlocked, isTrue);
      expect(gate.reason, StopReason.captureRestrictedForSite);
      expect(gate.evidence, contains('www.netflix.com'));
    });

    test('an allowed address is clear', () {
      expect(checkCaptureSite('https://example.com/a').isBlocked, isFalse);
      expect(checkCaptureSite(null).isBlocked, isFalse);
    });

    test('the user-facing sentence states what the app does, and no more', () {
      expect(
        StopReason.captureRestrictedForSite.message,
        kCaptureRestrictedMessage,
      );
      final wording =
          '${StopReason.captureRestrictedForSite.message} '
                  '${StopReason.captureRestrictedForSite.shortLabel}'
              .toLowerCase();
      for (final accusation in [
        'copyright',
        'illegal',
        'piracy',
        'infringe',
        'not allowed to',
        'you may not',
      ]) {
        expect(
          wording.contains(accusation),
          isFalse,
          reason: 'the refusal must never characterise the user\'s intent',
        );
      }
    });

    test('it is neither an access gate nor a success', () {
      // The *site* did not stop us — the app declined. Reporting it as an
      // access gate would claim something about the site that is not true.
      expect(StopReason.captureRestrictedForSite.isAccessGate, isFalse);
      expect(StopReason.captureRestrictedForSite.isSuccess, isFalse);
    });
  });

  group('the lists themselves', () {
    test('every entry is a bare lowercase host with no scheme or path', () {
      final pattern = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');
      for (final entry in {
        ...restrictedCaptureDomains,
        ...restrictedCaptureHosts,
      }) {
        expect(
          pattern.hasMatch(entry),
          isTrue,
          reason: '"$entry" is not a bare host — matching is on Uri.host only',
        );
      }
    });

    test('the baseline categories are all present', () {
      // A spot check per category, so deleting a whole group is a test
      // failure rather than a quiet shrinking of the policy.
      for (final domain in [
        'youtube.com', // video
        'blutv.com', // Turkish video
        'spotify.com', // music
        'audible.com', // audiobooks
        'webtoons.com', // licensed serialised reading
        'scribd.com', // ebooks
        'amazon.com', // retail, blocked whole
      ]) {
        expect(restrictedCaptureDomains, contains(domain));
      }
      for (final host in [
        'tv.apple.com',
        'play.google.com',
        'mangaplus.shueisha.co.jp',
        'page.kakao.com',
      ]) {
        expect(restrictedCaptureHosts, contains(host));
      }
    });

    test('no exact-host entry silently shadows a broader domain rule', () {
      // Except the one documented as deliberate: `music.youtube.com` is listed
      // for readability under a domain rule that already covers it.
      for (final host in restrictedCaptureHosts) {
        if (host == 'music.youtube.com') continue;
        for (final domain in restrictedCaptureDomains) {
          expect(
            host == domain || host.endsWith('.$domain'),
            isFalse,
            reason:
                '"$host" is already covered by the "$domain" domain rule; two '
                'rules for one host is how one of them stops being maintained',
          );
        }
      }
    });
  });
}
