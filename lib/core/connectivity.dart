import 'dart:io';

/// "Can this device reach the network right now?", cheaply and honestly.
///
/// A DNS lookup rather than a plugin: the whole need is one yes/no before
/// sending the user to a web page, and a connectivity plugin is exactly the
/// kind of dependency that rots for a question `dart:io` already answers.
///
/// It answers *reachability*, not *connectivity state*: a cached DNS record
/// can say yes on a device that has just lost its connection. That is the
/// right way round — a false yes lands the user on the browser's own error
/// page, which explains itself, while a false no would refuse a working
/// action.
class Connectivity {
  const Connectivity({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;

  /// True when [host] resolves. Any failure — no network, DNS refused,
  /// timeout — is a plain false; this must never throw into a tap handler.
  Future<bool> canReach(String host) async {
    if (host.trim().isEmpty) return false;
    try {
      final records = await InternetAddress.lookup(host).timeout(timeout);
      return records.isNotEmpty && records.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// Whether the device has a connection at all.
///
/// The one question that separates "this site is down" from "you are
/// offline" — two page states with different instructions for the user
/// (§14). Kept short: this runs inside an error callback, and a slow answer
/// would delay the error the user is already looking at.
Future<bool> hasNetwork() => const Connectivity(
  timeout: Duration(milliseconds: 1200),
).canReach('one.one.one.one');
