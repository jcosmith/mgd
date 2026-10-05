import 'component_meta.dart';

/// Everything that differs between Matillion ETL variants (target platforms).
///
/// Adding a variant means adding a profile here and fixtures for it. The
/// parser and the diff engine do not change.
final class VariantProfile {
  const VariantProfile({
    required this.id,
    required this.displayName,
    required this.buildEnvironment,
    required this.sqlDialect,
    this.components,
    this.extraTypes = const {},
    this.metaOverrides = const {},
    this.confirmed = false,
    this.supported = true,
  });

  final String id;
  final String displayName;

  /// The `environment` value written to `.build_version` by this variant.
  final String buildEnvironment;
  final String sqlDialect;

  /// implementationIDs from the shared map that this variant offers.
  /// `null` means "all shared types" (used while the list is unconfirmed).
  final Set<int>? components;

  /// Types that exist only on this variant.
  final Map<int, String> extraTypes;

  /// Variant-specific overrides of [componentMeta], keyed by type name.
  final Map<String, ComponentMeta> metaOverrides;

  /// Whether [components] has been confirmed against a real installation.
  final bool confirmed;

  /// Whether this variant is supported by the current release.
  final bool supported;
}

/// Matillion ETL for Azure Synapse: the variant supported by the first release.
///
/// TODO(confirm): restrict [VariantProfile.components] to the types that
/// exist on Synapse, and confirm the `.build_version` environment value
/// ("synapse" is an assumption; public repositories only show "snowflake").
const synapseProfile = VariantProfile(
  id: 'synapse',
  displayName: 'Matillion ETL for Azure Synapse',
  buildEnvironment: 'synapse',
  sqlDialect: 'T-SQL',
);

abstract final class VariantProfiles {
  static const List<VariantProfile> supported = [synapseProfile];

  static const VariantProfile defaultProfile = synapseProfile;

  /// Picks the profile for a `.build_version` environment value. Unknown or
  /// not-yet-supported environments get a generic profile, so jobs still diff.
  static VariantProfile forBuildEnvironment(String? environment) {
    if (environment == null || environment.isEmpty) return defaultProfile;
    for (final p in supported) {
      if (p.buildEnvironment == environment.toLowerCase()) return p;
    }
    return VariantProfile(
      id: environment,
      displayName: 'Matillion ETL ($environment)',
      buildEnvironment: environment,
      sqlDialect: 'SQL',
      supported: false,
    );
  }
}
