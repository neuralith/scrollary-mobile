/// What the save engine may ask, and tell, about an asset origin.
///
/// An interface rather than the repository itself, for the reason every other
/// seam in `lib/save/` is one: the engine measures pages and spends requests,
/// and it has no business holding a database handle to do either. The
/// implementation that remembers anything is `data/asset_origin_repository.dart`;
/// the default here remembers nothing, so a caller that has not been given one
/// behaves exactly as the engine did before this existed.
library;

import '../data/asset_origin_repository.dart' show AssetOriginVerdict;

export '../data/asset_origin_repository.dart' show AssetOriginVerdict;

/// The engine's view of what this device has learned about an origin.
abstract interface class AssetOriginCapability {
  /// What is believed about [origin] right now, staleness already applied.
  Future<AssetOriginVerdict> verdictFor(String origin);

  /// The strongest verdict among origins at or under [domain].
  ///
  /// For sites that shard their assets across sibling hosts, where evidence
  /// about one shard is evidence about the delivery the site arranged. The
  /// caller is responsible for passing only a domain the page itself belongs
  /// to — see the implementation for why that constraint is the safety.
  Future<AssetOriginVerdict> verdictUnderDomain(String domain);

  /// A capture of [locationKey] was refused by [origin].
  Future<void> noteRefusedCapture({
    required String origin,
    required String locationKey,
  });

  /// [origin] handed over a file, whatever was believed before.
  Future<void> noteServed(String origin);
}

/// Learns nothing and believes nothing.
///
/// The default, and what every existing test gets: with this in place the
/// engine asks each origin the full question every time, which is the
/// behaviour that was there before any of this was learned.
class ForgetfulAssetOrigins implements AssetOriginCapability {
  const ForgetfulAssetOrigins();

  @override
  Future<AssetOriginVerdict> verdictFor(String origin) async =>
      AssetOriginVerdict.unknown;

  @override
  Future<AssetOriginVerdict> verdictUnderDomain(String domain) async =>
      AssetOriginVerdict.unknown;

  @override
  Future<void> noteRefusedCapture({
    required String origin,
    required String locationKey,
  }) async {}

  @override
  Future<void> noteServed(String origin) async {}
}
