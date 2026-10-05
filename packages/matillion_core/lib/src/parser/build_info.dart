import 'dart:convert';

import '../registry/variants.dart';

/// Contents of the `.build_version` file at the repository root, e.g.
/// `{"version":"1.75.8","environment":"synapse"}`.
final class BuildInfo {
  const BuildInfo({this.version, this.environment});

  final String? version;

  /// The Matillion ETL variant that wrote the repository.
  final String? environment;

  VariantProfile get variant => VariantProfiles.forBuildEnvironment(environment);

  static BuildInfo parse(String? source) {
    if (source == null || source.trim().isEmpty) return const BuildInfo();
    try {
      final m = jsonDecode(source);
      if (m is Map<String, dynamic>) {
        return BuildInfo(version: m['version'] as String?, environment: m['environment'] as String?);
      }
    } on FormatException {
      // Fall through: an unreadable file is treated as missing.
    }
    return const BuildInfo();
  }
}
