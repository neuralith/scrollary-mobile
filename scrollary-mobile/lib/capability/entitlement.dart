import 'internal_build.dart';

/// What the app believes about the user's purchase.
///
/// Deliberately **not** a boolean. `unknown` is a real state — it is what an
/// entitlement source says before it has answered, and treating it as `free`
/// would flicker capabilities on launch while treating it as `pro` would give
/// away the product. Everything downstream resolves `unknown` the same way it
/// resolves `free`, but the two stay distinguishable in diagnostics.
enum Entitlement { unknown, free, pro }

/// What an internal build is pretending the entitlement is.
enum EntitlementOverride {
  /// Use the real source. The only value a production build can have.
  production,
  forceFree,
  forcePro;

  static EntitlementOverride parse(String? raw) => values.firstWhere(
    (v) => v.name == raw,
    orElse: () => EntitlementOverride.production,
  );

  String get label => switch (this) {
    EntitlementOverride.production => 'Production',
    EntitlementOverride.forceFree => 'Force Free',
    EntitlementOverride.forcePro => 'Force Pro',
  };
}

/// The single place an entitlement becomes an answer.
///
/// ```text
/// production source  +  internal override  ->  effective entitlement
///                                                     |
///                                              product capability
///                                                     |
///                                     capability AND user preference
/// ```
///
/// **Screens never read the override.** They ask for the effective value, so
/// when StoreKit or Play Billing eventually supplies [production] nothing above
/// this line changes — that is the whole reason the seam exists rather than a
/// boolean somewhere convenient.
Entitlement resolveEntitlement({
  required Entitlement production,
  required EntitlementOverride override,
  bool internalBuild = kInternalBuild,
}) {
  // A production build has no override to apply, whatever happens to be
  // persisted. Belt and braces: the UI that writes it does not exist there.
  if (!internalBuild) return production;
  return switch (override) {
    EntitlementOverride.production => production,
    EntitlementOverride.forceFree => Entitlement.free,
    EntitlementOverride.forcePro => Entitlement.pro,
  };
}

/// Is the paid capability available at all?
///
/// Separate from "is it switched on": availability is about entitlement, the
/// preference is about what the user asked for, and conflating them is how a
/// setting ends up lying about what it will do.
bool proCapabilityAvailable(Entitlement effective) =>
    effective == Entitlement.pro;

/// The one question the shell and the engines actually ask.
///
/// Both halves are required, and neither implies the other. Granting Pro must
/// not silently turn a behaviour on that the user never asked for, and a
/// preference stored while the user had Pro must not keep working after they
/// no longer do.
bool foregroundMultitaskingActive({
  required Entitlement effective,
  required bool preferenceEnabled,
}) => proCapabilityAvailable(effective) && preferenceEnabled;

/// Today's production entitlement source.
///
/// There is no billing in this build, so the honest answer is [Entitlement.free]
/// — not `unknown`, which would imply something is still loading, and certainly
/// not `pro`. When StoreKit or Play Billing lands it replaces the body of this
/// function and nothing else in the app moves.
Entitlement productionEntitlement() => Entitlement.free;
