/// What this device has learned about whether an origin hands over its files.
///
/// The point of the whole file is to stop the app asking a question it has
/// already had answered. A reading whose images are refused costs one request
/// per panel to discover that — seventy of them on a page measured during this
/// work — and the next Entry from the same site would pay it again, and the
/// one after that. None of those requests can succeed and every one of them is
/// made of a host that already said no.
///
/// **It is an observation, never a rule about a site.** Three properties keep
/// it that way, and each is load-bearing:
///
/// 1. **One ordinary refusal proves nothing.** A verdict is promoted only
///    after separate *Locations* were refused, so re-saving one page can never
///    promote it and a single bad afternoon on one address cannot either.
/// 2. **Any success clears it.** A host that hands over a file has answered
///    the question again, and the newer answer wins outright — counters and
///    all. This is what makes a site that changes its mind recover on its own.
/// 3. **A verdict goes stale.** [kVerdictFreshness] after it was established
///    it stops being believed and the ordinary path is tried in full again.
///    Nothing here is permanent, because nothing about a website is.
///
/// The judgement is pure over a row and a clock so it can be exercised against
/// literal fixtures; the store below only reads and writes.
library;

import 'package:drift/drift.dart';

import '../save/asset_origin_policy.dart';
import 'data_ids.dart' show utcNow;
import 'schema.dart';

/// How much this device believes an origin will refuse what it serves.
///
/// **Declared weakest to strongest**, and `index` is compared as such by
/// [AssetOriginRepository.verdictUnderDomain]. Reordering these reorders that
/// comparison.
enum AssetOriginVerdict {
  /// Nothing learned, or something learned and then contradicted.
  unknown,

  /// One capture was refused. Not enough: the ordinary path is still taken in
  /// full, because one page is not a pattern.
  suspected,

  /// Separate Locations were refused. The ordinary path is still *tried* —
  /// once, on a single asset — and abandoned as soon as that one is refused.
  refusing;

  static AssetOriginVerdict fromName(String? name) =>
      AssetOriginVerdict.values.firstWhere(
        (v) => v.name == name,
        orElse: () => AssetOriginVerdict.unknown,
      );
}

/// Separate Locations that must be refused before a verdict is believed.
///
/// Two, not one: a single page can be refused for reasons that have nothing to
/// do with the origin's settled behaviour — a rule that was rolled out and
/// rolled back, an address that was wrong. Two different readings refused is a
/// pattern; one is an afternoon.
const int kRefusalsToEstablish = 2;

/// How long a `refusing` verdict is believed before the full path is tried
/// again from scratch.
///
/// Websites change. A fortnight is long enough that a Collection saved over
/// several sittings does not re-pay the discovery cost each time, and short
/// enough that a site which fixed its delivery is noticed without the user
/// doing anything about it.
const Duration kVerdictFreshness = Duration(days: 14);

/// The verdict [row] carries *now* — which is not always the one stored.
///
/// Staleness is applied at read time rather than by sweeping the table: a
/// verdict nobody asks about does not need expiring, and a clock that only
/// runs when someone looks cannot drift.
AssetOriginVerdict verdictOf(AssetOriginRow? row, {DateTime? now}) {
  if (row == null) return AssetOriginVerdict.unknown;
  final stored = AssetOriginVerdict.fromName(row.verdict);
  if (stored != AssetOriginVerdict.refusing) return stored;
  final establishedAt = row.establishedAt;
  if (establishedAt == null) return stored;
  final age = (now ?? utcNow()).difference(establishedAt);
  // Stale, so it drops back to what a single refusal would have earned: the
  // full path is taken again, and if the site still refuses, one more capture
  // re-establishes it.
  return age > kVerdictFreshness
      ? AssetOriginVerdict.suspected
      : AssetOriginVerdict.refusing;
}

/// Reads and writes what has been learned about asset origins.
class AssetOriginRepository implements AssetOriginCapability {
  const AssetOriginRepository(this._db);

  final LibraryDatabase _db;

  Future<AssetOriginRow?> row(String origin) async {
    if (origin.isEmpty) return null;
    return (_db.select(
      _db.assetOrigins,
    )..where((t) => t.origin.equals(origin))).getSingleOrNull();
  }

  /// What this device believes about [origin] right now.
  @override
  Future<AssetOriginVerdict> verdictFor(String origin, {DateTime? now}) async =>
      verdictOf(await row(origin), now: now);

  /// The strongest verdict among origins that are, or sit under, [domain].
  ///
  /// **This exists because sites shard their assets.** Measured on a real one:
  /// two readings established a verdict against `s3.<site>`, and the next
  /// reading's panels came from `u1.<site>` — a host nothing had been learned
  /// about, so the whole discovery cost was paid again. A site's own shards
  /// sit under the site's own domain, and evidence about one of them is
  /// evidence about the delivery the site has arranged.
  ///
  /// The caller decides what [domain] may be, and the rule it applies is the
  /// safety here: only a domain the *page itself* belongs to. Widening to
  /// whatever a host's parent label happens to be would reach across a public
  /// suffix — every `co.uk` site judged by one of them — and this app ships no
  /// public-suffix list to tell the difference.
  @override
  Future<AssetOriginVerdict> verdictUnderDomain(
    String domain, {
    DateTime? now,
  }) async {
    if (domain.isEmpty) return AssetOriginVerdict.unknown;
    final rows = await _db.select(_db.assetOrigins).get();
    var strongest = AssetOriginVerdict.unknown;
    for (final row in rows) {
      final host = Uri.tryParse(row.origin)?.host;
      if (host == null) continue;
      if (host != domain && !host.endsWith('.$domain')) continue;
      final verdict = verdictOf(row, now: now);
      if (verdict.index > strongest.index) strongest = verdict;
    }
    return strongest;
  }

  /// Record that a capture of [locationKey] was refused by [origin].
  ///
  /// Counted per Location, so a re-save of the same page leaves the count
  /// exactly where it was — the second observation has to come from somewhere
  /// else to mean anything.
  @override
  Future<void> noteRefusedCapture({
    required String origin,
    required String locationKey,
    DateTime? now,
  }) async {
    if (origin.isEmpty) return;
    final at = now ?? utcNow();
    final existing = await row(origin);

    if (existing != null && existing.lastRefusedLocationKey == locationKey) {
      // The same reading again. Nothing new was learned.
      await _write(existing.copyWith(updatedAt: at));
      return;
    }

    final refused = (existing?.refusedCaptures ?? 0) + 1;
    final established = refused >= kRefusalsToEstablish;
    await _write(
      AssetOriginRow(
        origin: origin,
        verdict: established
            ? AssetOriginVerdict.refusing.name
            : AssetOriginVerdict.suspected.name,
        refusedCaptures: refused,
        lastRefusedLocationKey: locationKey,
        lastServedAt: existing?.lastServedAt,
        firstRefusedAt: existing?.firstRefusedAt ?? at,
        // Kept from the first time it was established, so staleness measures
        // the age of the belief rather than of the last thing that agreed
        // with it.
        establishedAt: established ? (existing?.establishedAt ?? at) : null,
        updatedAt: at,
      ),
    );
  }

  /// Record that [origin] handed over a file.
  ///
  /// The newer answer wins outright: the verdict and the counts both go, so a
  /// host that starts serving again is believed immediately rather than after
  /// the old evidence ages out.
  @override
  Future<void> noteServed(String origin, {DateTime? now}) async {
    if (origin.isEmpty) return;
    final at = now ?? utcNow();
    final existing = await row(origin);
    if (existing == null) return; // Nothing learned; nothing to unlearn.
    if (AssetOriginVerdict.fromName(existing.verdict) ==
            AssetOriginVerdict.unknown &&
        existing.refusedCaptures == 0) {
      return;
    }
    // A narrow writer, and it has to be one: `insertOnConflictUpdate` reads a
    // null field as *absent* and leaves the stored value alone, so writing a
    // row with `establishedAt: null` through it would keep the verdict's age
    // and the belief would never actually clear. Everything forgotten here is
    // spelled out as an explicit `Value(null)`.
    await (_db.update(
      _db.assetOrigins,
    )..where((t) => t.origin.equals(origin))).write(
      AssetOriginsCompanion(
        verdict: Value(AssetOriginVerdict.unknown.name),
        refusedCaptures: const Value(0),
        lastRefusedLocationKey: const Value(null),
        lastServedAt: Value(at),
        firstRefusedAt: const Value(null),
        establishedAt: const Value(null),
        updatedAt: Value(at),
      ),
    );
  }

  Future<void> forget(String origin) => (_db.delete(
    _db.assetOrigins,
  )..where((t) => t.origin.equals(origin))).go();

  Future<List<AssetOriginRow>> all() => _db.select(_db.assetOrigins).get();

  Future<void> _write(AssetOriginRow value) =>
      _db.into(_db.assetOrigins).insertOnConflictUpdate(value);
}
